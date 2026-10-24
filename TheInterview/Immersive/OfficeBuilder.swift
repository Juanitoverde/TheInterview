import Foundation
import RealityKit
import UIKit

/// Builds the office from primitives: a reception lobby, a corridor past an open-plan office, and
/// the interview room. All coordinates are metres in the world entity's space; the user starts at
/// the origin facing -Z, and the floor is y = 0.
///
///     z =  3 ┌───────── lobby ─────────┐
///            │   (user starts at 0,0)   │
///     z = -2 │      reception desk      │
///     z = -5 └──────┐ corridor ┌───────┘   x ∈ [1.2, 3.2]
///      open-plan    │          │
///      office       │          │
///     z = -15 ──────┴─door─┬───┘
///            interview room │  x ∈ [-1.25, 4.75]
///     z = -21 ──── window ──┘
@MainActor
struct OfficeBuilder {
    struct Cast {
        let receptionist: CharacterRig
        let interviewer: CharacterRig
        let colleagues: [CharacterRig]
        let chatPair: (CharacterRig, CharacterRig)
    }

    enum Layout {
        static let receptionistStart = SIMD3<Float>(0, 0, -2.75)
        static let interviewerChair = SIMD3<Float>(1.75, 0, -18.95)
        /// Where the user ends up, facing the interviewer across the desk.
        static let seat = SIMD3<Float>(1.75, 0, -17.2)
    }

    private enum Palette {
        static let wall: UInt32 = 0xE9E6E1
        static let ceiling: UInt32 = 0xF4F3F0
        static let stone: UInt32 = 0xD9D4CC
        static let carpet: UInt32 = 0x5F6670
        static let corridor: UInt32 = 0xB5A089
        static let woodFloor: UInt32 = 0xA67B5B
        static let wood: UInt32 = 0x8B5E3C
        static let lightWood: UInt32 = 0xB8875A
        static let white: UInt32 = 0xF2F1EE
        static let teal: UInt32 = 0x1F7A8C
        static let charcoal: UInt32 = 0x2C2C2E
        static let fabric: UInt32 = 0x3E5C76
        static let screen: UInt32 = 0x9CC3E6
        static let lightPanel: UInt32 = 0xFFFDF6
        static let window: UInt32 = 0xD4E7F5
        static let skirting: UInt32 = 0xF7F6F2
    }

    let companyName: String
    let interviewerName: String

    func build(into world: Entity) -> Cast {
        buildShell(world)
        buildLobby(world)
        let office = buildOpenPlanOffice(world)
        buildInterviewRoom(world)
        buildView(world)
        buildLighting(world)

        let receptionist = CharacterRig(appearance: CharacterAppearance(
            skin: 0xC68863, hair: 0x2B1B12, hairStyle: .long, top: Palette.teal, bottom: 0x2E2E36, eyes: 0x3B2A1E, scale: 0.96, build: 0.92
        ))
        receptionist.place(at: Layout.receptionistStart, yaw: 0)
        receptionist.setLooksAtUser(true)
        world.addChild(receptionist.root)

        let interviewer = CharacterRig(appearance: CharacterAppearance(
            skin: 0xE0B394, hair: 0x3B2F2A, hairStyle: .short, top: 0xF2F2F0, bottom: 0x2F3A4A, tie: 0x8C2F39, jacket: 0x2F3A4A,
            eyes: 0x56708C, build: 1.05
        ))
        interviewer.place(at: Layout.interviewerChair, yaw: 0)
        // Writing notes until the candidate arrives.
        interviewer.applyPose(.typing)
        world.addChild(interviewer.root)

        return Cast(receptionist: receptionist, interviewer: interviewer, colleagues: office.colleagues, chatPair: office.chatPair)
    }

    // MARK: Shell

    private func buildShell(_ world: Entity) {
        // Floors
        floor(world, center: [0, 0, -1], width: 9, depth: 8, material: Materials.textured(
            ProceduralTextures.tiles(width: 9, depth: 8, tileSize: 0.8, base: Palette.stone, grout: 0xBDB6AC), fallback: Palette.stone, roughness: 0.45))
        floor(world, center: [-0.65, 0, -10], width: 7.7, depth: 10, material: Materials.textured(
            ProceduralTextures.carpet(width: 7.7, depth: 10, base: Palette.carpet), fallback: Palette.carpet, roughness: 1))
        floor(world, center: [2.2, 0.002, -10], width: 2, depth: 10, material: Materials.textured(
            ProceduralTextures.woodPlanks(width: 2, depth: 10, base: Palette.corridor, seed: 2), fallback: Palette.corridor, roughness: 0.6))
        floor(world, center: [1.75, 0, -18], width: 6, depth: 6, material: Materials.textured(
            ProceduralTextures.woodPlanks(width: 6, depth: 6, base: Palette.woodFloor), fallback: Palette.woodFloor, roughness: 0.5))

        // Ceilings
        ceiling(world, center: [0, 3, -1], width: 9, depth: 8)
        ceiling(world, center: [-0.65, 3, -10], width: 7.7, depth: 10)
        ceiling(world, center: [1.75, 3, -18], width: 6, depth: 6)

        // Lobby walls (the back wall has an opening onto the corridor).
        wall(world, center: [0, 1.5, 3], size: [9, 3, 0.12])
        wall(world, center: [-4.5, 1.5, -1], size: [0.12, 3, 8])
        wall(world, center: [4.5, 1.5, -1], size: [0.12, 3, 8])
        wall(world, center: [-1.65, 1.5, -5], size: [5.7, 3, 0.12])
        wall(world, center: [3.85, 1.5, -5], size: [1.3, 3, 0.12])
        wall(world, center: [2.2, 2.7, -5], size: [2, 0.6, 0.12])

        // Office and corridor walls.
        wall(world, center: [-4.5, 1.5, -10], size: [0.12, 3, 10])
        wall(world, center: [3.2, 1.5, -10], size: [0.12, 3, 10])
        wall(world, center: [1.2, 0.55, -10], size: [0.08, 1.1, 8.8], color: Palette.white)
        world.add(makeModel(Meshes.box(0.1, 0.04, 8.8), Materials.matte(Palette.lightWood), at: [1.2, 1.12, -10]))

        // Wall between the office and the interview room, with a door opening.
        wall(world, center: [-1.45, 1.5, -15], size: [6.1, 3, 0.12])
        wall(world, center: [3.775, 1.5, -15], size: [1.95, 3, 0.12])
        wall(world, center: [2.2, 2.65, -15], size: [1.2, 0.7, 0.12])
        world.add(makeModel(Meshes.box(1.3, 0.06, 0.16), Materials.matte(Palette.wood), at: [2.2, 2.3, -15]))

        // Interview room walls; the back wall is built around a large window.
        wall(world, center: [-1.25, 1.5, -18], size: [0.12, 3, 6])
        wall(world, center: [4.75, 1.5, -18], size: [0.12, 3, 6])
        wall(world, center: [1.75, 0.425, -21], size: [6, 0.85, 0.12])
        wall(world, center: [1.75, 2.825, -21], size: [6, 0.35, 0.12])
        wall(world, center: [-0.95, 1.75, -21], size: [0.6, 1.8, 0.12])
        wall(world, center: [4.45, 1.75, -21], size: [0.6, 1.8, 0.12])
        let frame = Materials.metal(0x3A3D42)
        for x: Float in [-0.65, 0.95, 2.55, 4.15] {
            world.add(makeModel(Meshes.box(0.05, 1.8, 0.1), frame, at: [x, 1.75, -21]))
        }
        world.add(makeModel(Meshes.box(4.85, 0.05, 0.1), frame, at: [1.75, 0.85, -21]))
        world.add(makeModel(Meshes.box(4.85, 0.05, 0.1), frame, at: [1.75, 2.65, -21]))
        world.add(makeModel(Meshes.box(4.9, 0.04, 0.3), Materials.matte(Palette.white), at: [1.75, 0.87, -20.85]))

        // Skirting boards along the inner faces of the walls.
        skirting(world, z: -4.94...2.94, x: -4.43)
        skirting(world, z: -4.94...2.94, x: 4.43)
        skirting(world, x: -4.44...4.44, z: 2.93)
        skirting(world, x: -4.44...1.2, z: -4.93)
        skirting(world, x: 3.2...4.44, z: -4.93)
        skirting(world, z: -14.94 ... -5.06, x: -4.43)
        skirting(world, z: -14.94 ... -5.06, x: 3.13)
        skirting(world, x: -4.44...1.6, z: -14.93)
        skirting(world, z: -20.94 ... -15.06, x: -1.18)
        skirting(world, z: -20.94 ... -15.06, x: 4.68)
        skirting(world, x: -1.19...1.6, z: -15.07)
        skirting(world, x: 2.8...4.69, z: -15.07)
    }

    // MARK: Lobby

    private func buildLobby(_ world: Entity) {
        // Feature wall with the company name behind the receptionist.
        world.add(makeModel(Meshes.box(2.8, 2.6, 0.15), Materials.textured(ProceduralTextures.woodGrain(base: Palette.wood), fallback: Palette.wood, roughness: 0.55), at: [-0.2, 1.3, -3.9], shadow: true))
        let logo = makeTextLabel(companyName.uppercased(), size: 0.2, weight: .bold, color: 0xF5EBDD, depth: 0.02)
        logo.position = [-0.2, 1.95, -3.815]
        world.addChild(logo)
        world.add(makeModel(Meshes.box(1.6, 0.012, 0.01), Materials.matte(0xE2B866, roughness: 0.3), at: [-0.2, 1.72, -3.82]))
        let tagline = makeTextLabel("Welcome", size: 0.07, weight: .regular, color: 0xF5EBDD, depth: 0.005)
        tagline.position = [-0.2, 1.6, -3.82]
        world.addChild(tagline)

        // Reception desk.
        world.add(makeModel(Meshes.box(2.4, 1.05, 0.7, radius: 0.03), Materials.matte(Palette.white, roughness: 0.5), at: [0, 0.525, -2.0], shadow: true))
        world.add(makeModel(Meshes.box(2.5, 0.05, 0.38, radius: 0.015), Materials.textured(ProceduralTextures.woodGrain(base: Palette.lightWood), fallback: Palette.lightWood, roughness: 0.35), at: [0, 1.1, -1.72], shadow: true))
        world.add(makeModel(Meshes.box(2.42, 0.08, 0.02), Materials.matte(Palette.teal), at: [0, 0.75, -1.645]))
        // Monitor facing the receptionist.
        world.add(makeModel(Meshes.box(0.56, 0.34, 0.03, radius: 0.01), Materials.gloss(Palette.charcoal), at: [-0.55, 1.33, -2.2]))
        let receptionScreen = makeModel(Meshes.panel(0.52, 0.3), Materials.glow(Palette.screen), at: [-0.55, 1.33, -2.216])
        receptionScreen.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        world.addChild(receptionScreen)
        world.add(makeModel(Meshes.cylinder(height: 0.12, radius: 0.02), Materials.metal(0x8A8D91), at: [-0.55, 1.1, -2.2]))
        // Flowers and a brochure stand on the counter.
        world.add(makeModel(Meshes.cylinder(height: 0.22, radius: 0.06), Materials.gloss(0xFAFAFA), at: [0.85, 1.235, -1.72], shadow: true))
        let flowers: [(offset: SIMD3<Float>, color: UInt32)] = [
            ([0, 0.4, 0], 0xE85D75), ([0.06, 0.36, 0.03], 0xF2C14E), ([-0.05, 0.37, -0.02], 0xF7F3E8), ([0.02, 0.43, -0.05], 0xE85D75),
        ]
        for (offset, color) in flowers {
            world.add(makeModel(Meshes.sphere(0.045), Materials.matte(color), at: SIMD3<Float>(0.85, 1.0, -1.72) + offset))
        }
        world.add(makeModel(Meshes.box(0.2, 0.02, 0.14), Materials.matte(0x2F6F8F), at: [-0.75, 1.135, -1.7]))

        // Waiting area: sofa, coffee table, rug.
        world.add(makeModel(Meshes.floor(2.2, 2.8), Materials.textured(
            ProceduralTextures.rug(width: 2.2, depth: 2.8, base: 0x8C8579, border: 0x4A4038, accent: 0xC9A66B), fallback: 0x8C8579, roughness: 1), at: [-3.2, 0.006, -1]))
        let sofa = Materials.matte(Palette.fabric)
        world.add(makeModel(Meshes.box(0.8, 0.42, 2.0, radius: 0.06), sofa, at: [-3.75, 0.21, -1], shadow: true))
        world.add(makeModel(Meshes.box(0.22, 0.5, 2.0, radius: 0.06), sofa, at: [-4.1, 0.65, -1], shadow: true))
        world.add(makeModel(Meshes.box(0.8, 0.6, 0.18, radius: 0.05), sofa, at: [-3.75, 0.3, 0.05], shadow: true))
        world.add(makeModel(Meshes.box(0.8, 0.6, 0.18, radius: 0.05), sofa, at: [-3.75, 0.3, -2.05], shadow: true))
        world.add(makeModel(Meshes.box(0.6, 0.04, 1.0, radius: 0.01), Materials.gloss(Palette.lightWood), at: [-2.8, 0.42, -1], shadow: true))
        for z: Float in [-0.6, -1.4] {
            for x: Float in [-3.05, -2.55] {
                world.add(makeModel(Meshes.cylinder(height: 0.4, radius: 0.02), Materials.metal(0x2F2F2F), at: [x, 0.2, z]))
            }
        }
        world.add(makeModel(Meshes.box(0.22, 0.015, 0.3), Materials.matte(0xC9463D), at: [-2.8, 0.448, -0.85]))
        world.add(makeModel(Meshes.box(0.22, 0.015, 0.3), Materials.matte(0x3D7DC9), at: [-2.75, 0.462, -1.2]))

        // Entrance doors behind the user.
        for x: Float in [-0.55, 0.55] {
            world.add(makeModel(Meshes.box(1.04, 2.44, 0.04), Materials.metal(0x3A3D42), at: [x, 1.22, 2.95]))
            let glass = makeModel(Meshes.panel(0.96, 2.36), Materials.glow(0xC8DCEB), at: [x, 1.22, 2.92])
            glass.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
            world.addChild(glass)
        }

        // Pendant lights over the desk.
        for x: Float in [-0.8, 0, 0.8] {
            world.add(makeModel(Meshes.cylinder(height: 0.55, radius: 0.004), Materials.matte(0x222222), at: [x, 2.72, -2.0]))
            world.add(makeModel(Meshes.cylinder(height: 0.12, radius: 0.16), Materials.gloss(0x1E1E1E), at: [x, 2.4, -2.0]))
            world.add(makeModel(Meshes.cylinder(height: 0.01, radius: 0.14), Materials.glow(0xFFE8C2), at: [x, 2.335, -2.0]))
        }

        plant(world, at: [-4.0, 0, -4.45], height: 1.5)
        plant(world, at: [3.95, 0, -4.45], height: 1.3)
        plant(world, at: [-4.0, 0, 2.45], height: 1.2)
        plant(world, at: [4.0, 0, 2.45], height: 1.4)

        // Artwork on the right lobby wall.
        world.add(makeModel(Meshes.box(0.04, 1.0, 1.5), Materials.matte(0x1F1F1F), at: [4.42, 1.65, -1.2]))
        world.add(makeModel(Meshes.box(0.02, 0.9, 1.4), Materials.matte(0xD9A441), at: [4.4, 1.65, -1.2]))
        world.add(makeModel(Meshes.box(0.02, 0.5, 0.6), Materials.matte(Palette.teal), at: [4.39, 1.75, -1.4]))
        world.add(makeModel(Meshes.sphere(0.18), Materials.matte(0xC9463D), at: [4.45, 1.5, -0.9]))

        lightPanels(world, xs: [-2.5, 0, 2.5], zs: [1.2, -1.2, -3.6])
    }

    // MARK: Open-plan office

    private func buildOpenPlanOffice(_ world: Entity) -> (colleagues: [CharacterRig], chatPair: (CharacterRig, CharacterRig)) {
        let looks: [CharacterAppearance] = [
            CharacterAppearance(skin: 0x8D5524, hair: 0x111111, hairStyle: .curly, top: 0xE2E2DC, bottom: 0x2E3440),
            CharacterAppearance(skin: 0xF1C27D, hair: 0x6B4423, hairStyle: .bun, top: 0x7A4E8A, bottom: 0x2E2E2E, scale: 0.95, build: 0.9),
            CharacterAppearance(skin: 0xE0AC69, hair: 0x2A2A2A, hairStyle: .short, top: 0xDCE6F0, bottom: 0x3B3B45, jacket: 0x4A4F57),
            CharacterAppearance(skin: 0xC68642, hair: 0x1B1B1B, hairStyle: .long, top: 0xD97B4A, bottom: 0x2E2E36, scale: 0.94, build: 0.9),
            CharacterAppearance(skin: 0xFFDBAC, hair: 0xB08850, hairStyle: .short, top: 0x5577AA, bottom: 0x2B2B2B, eyes: 0x4F7A5A),
        ]
        // Desk centres; every desk but one has someone working at it.
        let desks: [(SIMD3<Float>, Bool)] = [
            ([-0.3, 0, -7], true), ([-0.3, 0, -10], false), ([-0.3, 0, -13], true),
            ([-2.7, 0, -7], true), ([-2.7, 0, -10], true), ([-2.7, 0, -13], true),
        ]
        var colleagues: [CharacterRig] = []
        var lookIndex = 0
        for (center, occupied) in desks {
            desk(world, center: center, chairPulledOut: !occupied)
            guard occupied else { continue }
            let colleague = CharacterRig(appearance: looks[lookIndex % looks.count])
            lookIndex += 1
            // Seated facing the corridor (+X).
            colleague.place(at: center + [-0.72, 0, 0], yaw: .pi / 2)
            colleague.applyPose(.typing)
            colleague.setLooksAtUser(true, range: 3.5)
            world.addChild(colleague.root)
            colleagues.append(colleague)
        }

        // Two colleagues chatting in the aisle; one holds a coffee.
        let first = CharacterRig(appearance: CharacterAppearance(skin: 0xD9A066, hair: 0x3D2B1F, hairStyle: .short, top: 0xF0EEE8, bottom: 0x23262B, jacket: 0x6B7F8E))
        first.place(at: [-1.85, 0, -11.15], yaw: .pi)
        let second = CharacterRig(appearance: CharacterAppearance(skin: 0xA66E4E, hair: 0x101010, hairStyle: .bun, top: 0xC44E5F, bottom: 0x2B2B33, scale: 0.95, build: 0.9))
        second.place(at: [-1.85, 0, -11.85], yaw: 0)
        second.hold(makeModel(Meshes.cylinder(height: 0.1, radius: 0.04), Materials.gloss(0xFAFAFA)))
        for person in [first, second] {
            person.setLooksAtUser(false)
            world.addChild(person.root)
        }

        // Daylight windows along the outer wall.
        for z: Float in [-7, -10, -13] {
            world.add(makeModel(Meshes.box(0.03, 1.7, 2.5), Materials.metal(0x3A3D42), at: [-4.43, 1.65, z]))
            let window = makeModel(Meshes.panel(2.4, 1.6), Materials.glow(Palette.window), at: [-4.41, 1.65, z])
            window.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
            world.addChild(window)
        }

        // Corridor wall: framed art and a meeting-room door.
        let artworks: [(z: Float, color: UInt32)] = [(-7.2, 0x3D7DC9), (-12.0, 0xD9A441)]
        for (z, color) in artworks {
            world.add(makeModel(Meshes.box(0.04, 0.85, 1.2), Materials.matte(0x1F1F1F), at: [3.13, 1.6, z]))
            world.add(makeModel(Meshes.box(0.02, 0.75, 1.1), Materials.matte(0xF3EFE7), at: [3.11, 1.6, z]))
            world.add(makeModel(Meshes.box(0.02, 0.4, 0.5), Materials.matte(color), at: [3.1, 1.65, z + 0.15]))
        }
        world.add(makeModel(Meshes.box(0.06, 2.1, 0.95), Materials.matte(Palette.wood, roughness: 0.6), at: [3.15, 1.05, -9.6]))
        world.add(makeModel(Meshes.box(0.05, 0.03, 0.14), Materials.metal(0xB0B3B8), at: [3.1, 1.0, -9.25]))
        let sign = makeTextLabel("Meeting Room 2", size: 0.06, weight: .medium, color: 0x2C2C2E, depth: 0.004)
        sign.position = [3.12, 2.25, -9.6]
        sign.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 1, 0])
        world.addChild(sign)

        plant(world, at: [2.95, 0, -5.5], height: 1.1)
        plant(world, at: [-4.05, 0, -14.5], height: 1.6)
        lightPanels(world, xs: [-2.5, -0.3, 2.2], zs: [-6.5, -9, -11.5, -14])

        return (colleagues, (first, second))
    }

    private func desk(_ world: Entity, center: SIMD3<Float>, chairPulledOut: Bool) {
        let top = Materials.gloss(Palette.white, roughness: 0.4)
        let metal = Materials.metal(0x9A9DA1)
        world.add(makeModel(Meshes.box(0.7, 0.04, 1.4, radius: 0.01), top, at: center + [0, 0.74, 0], shadow: true))
        for dx: Float in [-0.3, 0.3] {
            for dz: Float in [-0.62, 0.62] {
                world.add(makeModel(Meshes.box(0.04, 0.72, 0.04), metal, at: center + [dx, 0.36, dz]))
            }
        }
        // Modesty panel on the corridor side.
        world.add(makeModel(Meshes.box(0.03, 0.5, 1.36), Materials.matte(0xC9CCD1), at: center + [0.33, 0.47, 0]))
        // Monitor facing the person sitting at the desk (-X).
        world.add(makeModel(Meshes.box(0.03, 0.32, 0.54, radius: 0.008), Materials.gloss(Palette.charcoal), at: center + [0.2, 1.0, 0]))
        let screen = makeModel(Meshes.panel(0.5, 0.28), Materials.glow(Palette.screen), at: center + [0.183, 1.0, 0])
        screen.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 1, 0])
        world.addChild(screen)
        world.add(makeModel(Meshes.cylinder(height: 0.14, radius: 0.02), metal, at: center + [0.2, 0.83, 0]))
        world.add(makeModel(Meshes.box(0.15, 0.015, 0.42, radius: 0.004), Materials.matte(0x3A3A3C), at: center + [-0.27, 0.768, 0]))
        world.add(makeModel(Meshes.cylinder(height: 0.1, radius: 0.04), Materials.gloss(0xD9534F), at: center + [-0.05, 0.81, -0.5]))

        // Chair
        let chairCenter = center + (chairPulledOut ? SIMD3<Float>(-1.1, 0, 0.35) : SIMD3<Float>(-0.8, 0, 0))
        let fabric = Materials.matte(0x34383E)
        world.add(makeModel(Meshes.box(0.48, 0.07, 0.48, radius: 0.02), fabric, at: chairCenter + [0, 0.39, 0], shadow: true))
        world.add(makeModel(Meshes.box(0.06, 0.55, 0.45, radius: 0.02), fabric, at: chairCenter + [-0.26, 0.72, 0], shadow: true))
        world.add(makeModel(Meshes.cylinder(height: 0.34, radius: 0.025), metal, at: chairCenter + [0, 0.2, 0]))
        world.add(makeModel(Meshes.cylinder(height: 0.03, radius: 0.27), Materials.matte(0x222222), at: chairCenter + [0, 0.03, 0]))
    }

    // MARK: Interview room

    private func buildInterviewRoom(_ world: Entity) {
        world.add(makeModel(Meshes.floor(3.2, 2.6), Materials.textured(
            ProceduralTextures.rug(width: 3.2, depth: 2.6, base: 0x7D6E5D, border: 0x3E3A36, accent: 0xB89A6A), fallback: 0x7D6E5D, roughness: 1), at: [1.75, 0.004, -18.2]))

        // Desk: top, side panels and a modesty panel facing the candidate.
        let deskWood = Materials.textured(ProceduralTextures.woodGrain(base: Palette.wood), fallback: Palette.wood, roughness: 0.35)
        world.add(makeModel(Meshes.box(1.8, 0.05, 0.85, radius: 0.012), deskWood, at: [1.75, 0.75, -18.3], shadow: true))
        world.add(makeModel(Meshes.box(0.05, 0.73, 0.8), deskWood, at: [0.9, 0.365, -18.3], shadow: true))
        world.add(makeModel(Meshes.box(0.05, 0.73, 0.8), deskWood, at: [2.6, 0.365, -18.3], shadow: true))
        world.add(makeModel(Meshes.box(1.7, 0.55, 0.03), deskWood, at: [1.75, 0.45, -17.92], shadow: true))

        // On the desk: notepad and pen, laptop, mug, name plate, small plant.
        world.add(makeModel(Meshes.box(0.21, 0.006, 0.29), Materials.matte(0xFBFBF8), at: [1.75, 0.778, -18.42]))
        let pen = makeModel(Meshes.cylinder(height: 0.14, radius: 0.005), Materials.gloss(0x1D3557), at: [1.9, 0.782, -18.4])
        pen.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        world.addChild(pen)
        world.add(makeModel(Meshes.box(0.34, 0.015, 0.24, radius: 0.005), Materials.metal(0xB9BCC0), at: [2.3, 0.783, -18.5]))
        let lid = Entity()
        lid.position = [2.3, 0.79, -18.38]
        lid.orientation = simd_quatf(angle: 0.3, axis: [1, 0, 0])
        lid.add(makeModel(Meshes.box(0.34, 0.23, 0.008, radius: 0.004), Materials.metal(0xB9BCC0), at: [0, 0.115, 0]))
        let laptopScreen = makeModel(Meshes.panel(0.31, 0.2), Materials.glow(Palette.screen), at: [0, 0.115, -0.005])
        laptopScreen.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        lid.addChild(laptopScreen)
        world.addChild(lid)
        world.add(makeModel(Meshes.cylinder(height: 0.1, radius: 0.04), Materials.gloss(0xFAFAFA), at: [1.15, 0.825, -18.5], shadow: true))
        world.add(makeModel(Meshes.cylinder(height: 0.005, radius: 0.034), Materials.matte(0x4B2E1E), at: [1.15, 0.873, -18.5]))
        world.add(makeModel(Meshes.box(0.34, 0.07, 0.03, radius: 0.005), Materials.gloss(Palette.charcoal), at: [1.75, 0.81, -17.95]))
        let namePlate = makeTextLabel(interviewerName, size: 0.032, weight: .medium, color: 0xF5EBDD, depth: 0.002)
        namePlate.position = [1.75, 0.81, -17.934]
        world.addChild(namePlate)
        world.add(makeModel(Meshes.cylinder(height: 0.09, radius: 0.045), Materials.matte(0xEDEBE6), at: [0.98, 0.82, -18.05]))
        world.add(makeModel(Meshes.sphere(0.07), Materials.matte(0x4E8C45), at: [0.98, 0.91, -18.05]))

        // The interviewer's chair, behind the desk.
        let chair = Materials.matte(0x1F2124, roughness: 0.6)
        let chairCenter = SIMD3<Float>(1.75, 0, -19.15)
        world.add(makeModel(Meshes.box(0.55, 0.08, 0.5, radius: 0.03), chair, at: chairCenter + [0, 0.38, 0], shadow: true))
        world.add(makeModel(Meshes.box(0.55, 0.8, 0.08, radius: 0.03), chair, at: chairCenter + [0, 0.86, -0.27], shadow: true))
        world.add(makeModel(Meshes.cylinder(height: 0.32, radius: 0.03), Materials.metal(0x8A8D91), at: chairCenter + [0, 0.2, 0]))
        world.add(makeModel(Meshes.cylinder(height: 0.04, radius: 0.3), chair, at: chairCenter + [0, 0.04, 0]))

        // A second visitor chair beside the candidate.
        let visitor = SIMD3<Float>(2.75, 0, -17.3)
        let visitorFabric = Materials.matte(Palette.fabric)
        world.add(makeModel(Meshes.box(0.5, 0.08, 0.5, radius: 0.03), visitorFabric, at: visitor + [0, 0.45, 0], shadow: true))
        world.add(makeModel(Meshes.box(0.5, 0.45, 0.07, radius: 0.03), visitorFabric, at: visitor + [0, 0.75, 0.24], shadow: true))
        for dx: Float in [-0.21, 0.21] {
            for dz: Float in [-0.21, 0.21] {
                world.add(makeModel(Meshes.cylinder(height: 0.42, radius: 0.015), Materials.metal(0x2F2F2F), at: visitor + [dx, 0.21, dz]))
            }
        }

        // Bookshelf on the left wall.
        let shelfWood = Materials.matte(Palette.lightWood, roughness: 0.6)
        world.add(makeModel(Meshes.box(0.35, 2.0, 1.6), shelfWood, at: [-1.0, 1.0, -19.4], shadow: true))
        let bookColors: [UInt32] = [0x8C2F39, 0x1D3557, 0x2A9D8F, 0xE9C46A, 0x6D597A, 0x264653, 0xE76F51]
        for (row, y) in [Float(0.45), 0.95, 1.45].enumerated() {
            world.add(makeModel(Meshes.box(0.33, 0.02, 1.52), shelfWood, at: [-0.98, y - 0.21, -19.4]))
            var z: Float = -20.1
            var index = row * 2
            while z < -18.75 {
                let height: Float = 0.24 + Float(index % 3) * 0.03
                world.add(makeModel(Meshes.box(0.2, height, 0.05), Materials.matte(bookColors[index % bookColors.count]), at: [-0.9, y - 0.2 + height / 2, z]))
                z += 0.065
                index += 1
            }
        }

        // Whiteboard and framed certificates on the right wall.
        world.add(makeModel(Meshes.box(0.03, 1.0, 1.6), Materials.gloss(0xFDFDFD, roughness: 0.2), at: [4.68, 1.5, -17.4]))
        world.add(makeModel(Meshes.box(0.04, 0.03, 1.6), Materials.metal(0x9A9DA1), at: [4.66, 0.99, -17.4]))
        for z: Float in [-19.3, -20.1] {
            world.add(makeModel(Meshes.box(0.03, 0.42, 0.32), Materials.matte(0x2B2B2B), at: [4.68, 1.6, z]))
            world.add(makeModel(Meshes.box(0.02, 0.36, 0.26), Materials.matte(0xF6F1E4), at: [4.665, 1.6, z]))
        }

        // Wall clock above the door (visible to the interviewer).
        let clock = Entity()
        clock.position = [0.4, 2.3, -15.08]
        clock.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        clock.add(makeModel(Meshes.cylinder(height: 0.03, radius: 0.16), Materials.matte(0xFAFAFA)))
        world.addChild(clock)

        plant(world, at: [-0.75, 0, -20.45], height: 1.5)
        plant(world, at: [4.25, 0, -20.45], height: 1.3)
        lightPanels(world, xs: [0.6, 2.9], zs: [-16.6, -19.2])
    }

    /// The city seen through the interview-room window.
    private func buildView(_ world: Entity) {
        let sky = makeModel(Meshes.panel(40, 34), Materials.sky(), at: [1.75, 3, -45])
        world.addChild(sky)
        let towers: [(x: Float, z: Float, width: Float, height: Float, color: UInt32)] = [
            (-6, -30, 4, 14, 0x7F93A8), (-1, -26, 3, 9, 0x6A7F96), (2.5, -34, 5, 18, 0x8EA3B8),
            (6.5, -27, 3.5, 11, 0x667B92), (10, -32, 4, 15, 0x8297AC), (-3.5, -36, 4.5, 20, 0x94A8BC),
            (4.5, -24, 2.5, 6, 0x5C7189), (-8.5, -25, 3, 8, 0x60758C),
        ]
        for tower in towers {
            // Towers rise from well below the window, as if the office is on a high floor.
            let height = tower.height + 20
            world.add(makeModel(Meshes.box(tower.width, height, tower.width), Materials.glow(tower.color), at: [tower.x, -20 + height / 2, tower.z]))
        }
    }

    // MARK: Lighting

    private func buildLighting(_ world: Entity) {
        // Daylight streaming in through the interview-room window, toward the candidate.
        let sun = Entity()
        var daylight = DirectionalLightComponent()
        daylight.color = UIColor(hex: 0xFFF1DC)
        daylight.intensity = 1800
        sun.components.set(daylight)
        sun.orientation = simd_quatf(from: [0, 0, -1], to: simd_normalize(SIMD3<Float>(0.25, -0.6, 1)))
        world.addChild(sun)

        for position: SIMD3<Float> in [[0, 2.7, -1.2], [2.2, 2.7, -7.5], [-1.8, 2.7, -10], [2.2, 2.7, -12.5], [1.75, 2.7, -17.6]] {
            let lamp = Entity()
            var light = PointLightComponent()
            light.color = UIColor(hex: 0xFFF4E5)
            light.intensity = 9000
            light.attenuationRadius = 7
            lamp.components.set(light)
            lamp.position = position
            world.addChild(lamp)
        }
    }

    // MARK: Pieces

    private func floor(_ world: Entity, center: SIMD3<Float>, width: Float, depth: Float, material: RealityKit.Material) {
        world.add(makeModel(Meshes.floor(width, depth), material, at: center))
    }

    private func ceiling(_ world: Entity, center: SIMD3<Float>, width: Float, depth: Float) {
        let tiles = ProceduralTextures.tiles(width: width, depth: depth, tileSize: 0.6, base: Palette.ceiling, grout: 0xD9D7D2, variation: 0.01, speckle: false)
        let ceiling = makeModel(Meshes.floor(width, depth), Materials.textured(tiles, fallback: Palette.ceiling, roughness: 0.9), at: center)
        // Planes face up; flip it so it's visible from below.
        ceiling.orientation = simd_quatf(angle: .pi, axis: [1, 0, 0])
        world.addChild(ceiling)
    }

    private func wall(_ world: Entity, center: SIMD3<Float>, size: SIMD3<Float>, color: UInt32 = Palette.wall) {
        world.add(makeModel(Meshes.box(size.x, size.y, size.z), Materials.matte(color), at: center))
    }

    /// A skirting board along a wall that runs in X, at the wall's inner face `z`.
    private func skirting(_ world: Entity, x: ClosedRange<Float>, z: Float) {
        let length = x.upperBound - x.lowerBound
        world.add(makeModel(Meshes.box(length, 0.1, 0.02), Materials.matte(Palette.skirting, roughness: 0.5), at: [(x.lowerBound + x.upperBound) / 2, 0.05, z]))
    }

    /// A skirting board along a wall that runs in Z, at the wall's inner face `x`.
    private func skirting(_ world: Entity, z: ClosedRange<Float>, x: Float) {
        let length = z.upperBound - z.lowerBound
        world.add(makeModel(Meshes.box(0.02, 0.1, length), Materials.matte(Palette.skirting, roughness: 0.5), at: [x, 0.05, (z.lowerBound + z.upperBound) / 2]))
    }

    private func lightPanels(_ world: Entity, xs: [Float], zs: [Float]) {
        let glow = Materials.glow(Palette.lightPanel)
        for x in xs {
            for z in zs {
                world.add(makeModel(Meshes.box(1.2, 0.02, 0.6), glow, at: [x, 2.985, z]))
            }
        }
    }

    private func plant(_ world: Entity, at position: SIMD3<Float>, height: Float) {
        let group = world.add(Entity())
        group.position = position
        group.add(makeModel(Meshes.cylinder(height: 0.42, radius: 0.19), Materials.matte(0xEDEBE6, roughness: 0.6), at: [0, 0.21, 0], shadow: true))
        group.add(makeModel(Meshes.cylinder(height: 0.02, radius: 0.17), Materials.matte(0x4A3A2A), at: [0, 0.42, 0]))
        let stem = max(height - 0.5, 0.2)
        group.add(makeModel(Meshes.cylinder(height: stem, radius: 0.025), Materials.matte(0x5A4632), at: [0, 0.42 + stem / 2, 0]))
        let greens: [UInt32] = [0x3F7D3A, 0x4E8C45, 0x35692F]
        let blobs: [(SIMD3<Float>, Float)] = [
            ([0, height - 0.1, 0], 0.24), ([0.14, height - 0.3, 0.05], 0.2), ([-0.13, height - 0.28, -0.04], 0.21),
            ([0.02, height - 0.45, 0.13], 0.18), ([-0.05, height + 0.08, -0.06], 0.16),
        ]
        for (index, blob) in blobs.enumerated() {
            group.add(makeModel(Meshes.sphere(blob.1), Materials.matte(greens[index % greens.count]), at: blob.0, shadow: true))
        }
    }
}
