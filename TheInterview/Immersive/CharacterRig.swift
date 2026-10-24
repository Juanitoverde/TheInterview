import Foundation
import RealityKit
import UIKit

struct CharacterAppearance {
    enum Hair {
        case short
        case long
        case bun
        case curly
        case none
    }

    var skin: UInt32
    var hair: UInt32
    var hairStyle: Hair
    /// Shirt or blouse.
    var top: UInt32
    var bottom: UInt32
    var shoes: UInt32 = 0x2B2B2B
    var tie: UInt32?
    /// When set, a jacket with lapels is worn over `top`.
    var jacket: UInt32?
    var eyes: UInt32 = 0x4A3426
    var scale: Float = 1
    /// Shoulder and hip width multiplier.
    var build: Float = 1
}

/// The joints and expressive parts of a character, driven by pose animations and `CharacterAnimationSystem`.
struct CharacterJoints {
    let root: Entity
    /// Offset for sitting and the bob while walking.
    let body: Entity
    /// Shifted side to side for idle weight shifts.
    let hips: Entity
    /// Leans and sways slightly.
    let torso: Entity
    /// Scaled slightly for breathing.
    let torsoMesh: Entity
    let leftThigh: Entity
    let rightThigh: Entity
    let leftKnee: Entity
    let rightKnee: Entity
    let leftShoulder: Entity
    let rightShoulder: Entity
    let leftElbow: Entity
    let rightElbow: Entity
    /// Turned by the system to look at the user.
    let headPivot: Entity
    /// Nods and head tilts.
    let nodPivot: Entity
    let leftEye: Entity
    let rightEye: Entity
    let leftBrow: Entity
    let rightBrow: Entity
    /// The dark gap between the lips; opens while talking.
    let mouth: Entity
    let lowerLip: Entity
    /// Marker between the eyes; the target for eye-contact measurement.
    let eyes: Entity
    /// Where the character's voice comes from.
    let voice: Entity
}

/// A stylised person built from primitives, facing +Z, with procedural animation.
///
/// Characters face +Z in their local space. A character's left is therefore +X.
@MainActor
final class CharacterRig {
    enum Pose {
        case standing
        /// Seated with hands in the lap.
        case sitting
        /// Seated with forearms resting on a desk.
        case sittingAtDesk
        /// Seated and typing at a keyboard.
        case typing
    }

    enum Side {
        case left
        case right
    }

    let joints: CharacterJoints
    private(set) var pose: Pose = .standing

    var root: Entity { joints.root }

    /// World-space position between the eyes.
    var eyePosition: SIMD3<Float> { joints.eyes.position(relativeTo: nil) }

    /// The entity to play this character's voice from.
    var voiceSource: Entity { joints.voice }

    init(appearance: CharacterAppearance) {
        joints = Self.build(appearance)
        joints.root.components.set(CharacterAnimationComponent(joints: joints))
    }

    // MARK: Placement

    func place(at position: SIMD3<Float>, yaw: Float) {
        root.position = position
        root.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
    }

    func turn(toYaw yaw: Float, duration: TimeInterval) async {
        var transform = root.transform
        transform.rotation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        apply(transform, to: root, duration: duration)
        await pause(duration)
    }

    /// Turns to face a point given in the same space as the character's position.
    func turn(toward target: SIMD3<Float>, duration: TimeInterval) async {
        await turn(toYaw: Entity.yaw(toward: target - root.position), duration: duration)
    }

    // MARK: State for the animation system

    func setTalking(_ talking: Bool) {
        updateAnimation { $0.isTalking = talking }
    }

    func setLooksAtUser(_ looks: Bool, range: Float = 7) {
        updateAnimation {
            $0.looksAtUser = looks
            $0.lookRange = range
        }
    }

    /// Active listening: occasional small nods and a slight head tilt.
    func setAttentive(_ attentive: Bool) {
        updateAnimation { $0.isAttentive = attentive }
    }

    private func updateAnimation(_ change: (inout CharacterAnimationComponent) -> Void) {
        guard var component = root.components[CharacterAnimationComponent.self] else { return }
        change(&component)
        root.components.set(component)
    }

    // MARK: Poses

    /// Animates to `pose` and returns when it's reached.
    func setPose(_ pose: Pose, duration: TimeInterval = 0.8) async {
        applyPose(pose, duration: duration)
        await pause(duration)
        if pose == .typing { updateAnimation { $0.isTyping = true } }
    }

    /// Starts moving to `pose` without waiting. With a zero duration the pose is applied immediately.
    /// Legs and hips are animated here; the arms and lean are eased by `CharacterAnimationSystem`.
    func applyPose(_ pose: Pose, duration: TimeInterval = 0) {
        self.pose = pose
        let j = joints
        let arms: (shoulder: Float, elbow: Float, lean: Float)
        switch pose {
        case .standing:
            move(j.body, to: .zero, duration: duration)
            for joint in [j.leftThigh, j.rightThigh, j.leftKnee, j.rightKnee] {
                rotate(joint, duration: duration)
            }
            arms = (0, -0.12, 0)
        case .sitting, .sittingAtDesk, .typing:
            // Thighs forward, shins down: the hips drop to seat height.
            move(j.body, to: [0, -0.44, -0.05], duration: duration)
            rotate(j.leftThigh, x: -.pi / 2, duration: duration)
            rotate(j.rightThigh, x: -.pi / 2, duration: duration)
            rotate(j.leftKnee, x: .pi / 2, duration: duration)
            rotate(j.rightKnee, x: .pi / 2, duration: duration)
            arms = switch pose {
            case .sittingAtDesk: (-0.5, -1.15, 0.06)
            case .typing: (-0.45, -1.1, 0.08)
            default: (-0.15, -0.9, 0.03)
            }
        }
        updateAnimation {
            $0.isTyping = pose == .typing && duration <= 0
            $0.shoulderTarget = arms.shoulder
            $0.elbowTarget = arms.elbow
            $0.leanTarget = arms.lean
            if duration <= 0 {
                $0.shoulderLeft = arms.shoulder
                $0.shoulderRight = arms.shoulder
                $0.elbowLeft = arms.elbow
                $0.elbowRight = arms.elbow
                $0.lean = arms.lean
            }
        }
    }

    // MARK: Movement

    /// Walks through `points` (in the parent's space), turning at each corner, over `duration` seconds.
    func walk(through points: [SIMD3<Float>], duration: TimeInterval) async {
        var previous = root.position
        var total: Float = 0
        for point in points {
            total += simd_distance(previous, point)
            previous = point
        }
        guard total > 0.01, duration > 0 else { return }

        if pose != .standing { await setPose(.standing, duration: 0.6) }
        let turnTime: TimeInterval = 0.3
        let moveTime = max(duration - turnTime * Double(points.count), 0.3)
        let speed = Double(total) / moveTime
        updateAnimation {
            $0.isWalking = true
            // Roughly 1.3 m per stride cycle.
            $0.walkCadence = Float(speed / 1.3)
        }

        var start = root.position
        for point in points {
            if Task.isCancelled { break }
            let segment = point - start
            let length = simd_length(segment)
            guard length > 0.01 else { continue }
            await turn(toYaw: Entity.yaw(toward: segment), duration: turnTime)
            let time = moveTime * Double(length / total)
            var transform = root.transform
            transform.translation = point
            apply(transform, to: root, duration: time, timing: .linear)
            await pause(time)
            start = point
        }

        updateAnimation { $0.isWalking = false }
        joints.body.position = .zero
        await setPose(.standing, duration: 0.25)
    }

    // MARK: Gestures

    func wave() async {
        let j = joints
        updateAnimation { $0.gestureActive = true }
        // The right arm swings out to the side (-X) and up.
        rotate(j.rightShoulder, z: -2.6, duration: 0.4)
        await pause(0.4)
        for index in 0..<4 {
            rotate(j.rightElbow, z: index.isMultiple(of: 2) ? 0.4 : -0.3, duration: 0.22)
            await pause(0.22)
        }
        await returnArmsToRest(duration: 0.45)
    }

    func point(_ side: Side) async {
        let shoulder = side == .left ? joints.leftShoulder : joints.rightShoulder
        let elbow = side == .left ? joints.leftElbow : joints.rightElbow
        updateAnimation { $0.gestureActive = true }
        rotate(shoulder, x: -0.4, z: side == .left ? 1.25 : -1.25, duration: 0.45)
        rotate(elbow, x: -0.2, duration: 0.45)
        await pause(1.6)
        await returnArmsToRest(duration: 0.5)
    }

    /// Animates both arms back to where the animation system holds them, then hands control back.
    private func returnArmsToRest(duration: TimeInterval) async {
        guard let state = root.components[CharacterAnimationComponent.self] else { return }
        rotate(joints.leftShoulder, x: state.shoulderLeft, duration: duration)
        rotate(joints.rightShoulder, x: state.shoulderRight, duration: duration)
        rotate(joints.leftElbow, x: state.elbowLeft, duration: duration)
        rotate(joints.rightElbow, x: state.elbowRight, duration: duration)
        await pause(duration)
        updateAnimation { $0.gestureActive = false }
    }

    /// Puts an object in the right hand and keeps that forearm raised.
    func hold(_ object: Entity) {
        let raised: Float = -1.3
        // Counter-rotate so the object stays upright in the raised hand.
        object.position = [0, -0.3, 0.045]
        object.orientation = simd_quatf(angle: -raised, axis: [1, 0, 0])
        joints.rightElbow.addChild(object)
        updateAnimation { $0.rightElbowOverride = raised }
    }

    func nod() async {
        updateAnimation {
            $0.nodTime = 0
            $0.nodStrength = 0.2
            $0.nodCount = 2
        }
        await pause(1.4)
    }

    func fade(to opacity: Float, duration: TimeInterval) async {
        let start = root.components[OpacityComponent.self]?.opacity ?? 1
        let steps = max(Int(duration * 30), 1)
        for step in 1...steps {
            root.components.set(OpacityComponent(opacity: start + (opacity - start) * Float(step) / Float(steps)))
            await pause(duration / Double(steps))
        }
    }

    // MARK: Helpers

    private func pause(_ seconds: TimeInterval) async {
        guard seconds > 0 else { return }
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func rotate(_ entity: Entity, x: Float = 0, y: Float = 0, z: Float = 0, duration: TimeInterval) {
        var transform = entity.transform
        transform.rotation = simd_quatf(angle: y, axis: [0, 1, 0]) * simd_quatf(angle: x, axis: [1, 0, 0]) * simd_quatf(angle: z, axis: [0, 0, 1])
        apply(transform, to: entity, duration: duration)
    }

    private func move(_ entity: Entity, to translation: SIMD3<Float>, duration: TimeInterval) {
        var transform = entity.transform
        transform.translation = translation
        apply(transform, to: entity, duration: duration)
    }

    private func apply(_ transform: Transform, to entity: Entity, duration: TimeInterval, timing: AnimationTimingFunction = .easeInOut) {
        if duration <= 0 {
            entity.transform = transform
        } else {
            entity.move(to: transform, relativeTo: entity.parent, duration: duration, timingFunction: timing)
        }
    }

    // MARK: Construction

    private static func build(_ look: CharacterAppearance) -> CharacterJoints {
        let skin = Materials.matte(look.skin, roughness: 0.65)
        let hair = Materials.matte(look.hair, roughness: 0.9)
        let shirt = Materials.matte(look.top)
        let outer = look.jacket.map { Materials.matte($0, roughness: 0.75) } ?? shirt
        let bottom = Materials.matte(look.bottom)
        let shoes = Materials.gloss(look.shoes, roughness: 0.35)
        let lips = Materials.matte(blend(look.skin, 0x9E4B4B, 0.45), roughness: 0.5)
        let width = look.build

        let root = Entity()
        root.scale = SIMD3<Float>(repeating: look.scale)
        let body = root.add(Entity())

        let hips = body.add(Entity())
        hips.position = [0, 0.97, 0]
        hips.add(makeModel(Meshes.box(0.34 * width, 0.18, 0.22, radius: 0.05), bottom, shadow: true))
        if look.jacket == nil {
            hips.add(makeModel(Meshes.box(0.345 * width, 0.03, 0.225, radius: 0.01), Materials.gloss(0x2A211B), at: [0, 0.075, 0]))
        }

        func leg(x: Float) -> (thigh: Entity, knee: Entity) {
            let thigh = hips.add(Entity())
            thigh.position = [x, -0.05, 0]
            thigh.add(makeModel(Meshes.cylinder(height: 0.44, radius: 0.07), bottom, at: [0, -0.22, 0], shadow: true))
            let knee = thigh.add(Entity())
            knee.position = [0, -0.44, 0]
            knee.add(makeModel(Meshes.cylinder(height: 0.42, radius: 0.055), bottom, at: [0, -0.21, 0], shadow: true))
            knee.add(makeModel(Meshes.box(0.1, 0.06, 0.25, radius: 0.028), shoes, at: [0, -0.45, 0.05], shadow: true))
            return (thigh, knee)
        }
        let leftLeg = leg(x: 0.095 * width)
        let rightLeg = leg(x: -0.095 * width)

        let torso = hips.add(Entity())
        torso.position = [0, 0.05, 0]
        let torsoMesh = torso.add(makeModel(Meshes.box(0.38 * width, 0.52, 0.22, radius: 0.07), outer, at: [0, 0.26, 0], shadow: true))

        if let jacket = look.jacket {
            // Shirt showing in the V of the jacket, with lapels either side.
            torso.add(makeModel(Meshes.box(0.11, 0.24, 0.01, radius: 0.004), shirt, at: [0, 0.35, 0.111]))
            let lapel = Materials.matte(blend(jacket, 0x000000, 0.18), roughness: 0.7)
            for side: Float in [1, -1] {
                let piece = torso.add(makeModel(Meshes.box(0.05, 0.27, 0.012, radius: 0.005), lapel, at: [0.052 * side, 0.355, 0.114]))
                piece.orientation = simd_quatf(angle: -0.32 * side, axis: [0, 0, 1])
            }
        }
        if let tie = look.tie {
            torso.add(makeModel(Meshes.box(0.045, 0.28, 0.01, radius: 0.004), Materials.matte(tie), at: [0, 0.33, 0.119]))
            torso.add(makeModel(Meshes.box(0.05, 0.035, 0.014, radius: 0.005), Materials.matte(tie), at: [0, 0.465, 0.112]))
        }
        // Collar.
        for side: Float in [1, -1] {
            let collar = torso.add(makeModel(Meshes.box(0.06, 0.035, 0.012, radius: 0.004), shirt, at: [0.035 * side, 0.505, 0.088]))
            collar.orientation = simd_quatf(angle: 0.5 * side, axis: [0, 0, 1])
        }

        func arm(x: Float) -> (shoulder: Entity, elbow: Entity) {
            let shoulder = torso.add(Entity())
            shoulder.position = [x, 0.47, 0]
            shoulder.add(makeModel(Meshes.sphere(0.056), outer, shadow: true))
            shoulder.add(makeModel(Meshes.cylinder(height: 0.28, radius: 0.047), outer, at: [0, -0.14, 0], shadow: true))
            let elbow = shoulder.add(Entity())
            elbow.position = [0, -0.29, 0]
            elbow.orientation = simd_quatf(angle: -0.12, axis: [1, 0, 0])
            elbow.add(makeModel(Meshes.cylinder(height: 0.25, radius: 0.04), outer, at: [0, -0.125, 0], shadow: true))
            elbow.add(makeModel(Meshes.cylinder(height: 0.02, radius: 0.034), shirt, at: [0, -0.255, 0]))
            // Hand: a flattened palm with the thumb forward.
            elbow.add(makeModel(Meshes.box(0.028, 0.085, 0.075, radius: 0.013), skin, at: [0, -0.305, 0], shadow: true))
            elbow.add(makeModel(Meshes.sphere(0.017), skin, at: [0, -0.29, 0.042]))
            return (shoulder, elbow)
        }
        let leftArm = arm(x: 0.235 * width)
        let rightArm = arm(x: -0.235 * width)

        torso.add(makeModel(Meshes.cylinder(height: 0.1, radius: 0.048), skin, at: [0, 0.56, 0]))
        let headPivot = torso.add(Entity())
        headPivot.position = [0, 0.6, 0]
        let nodPivot = headPivot.add(Entity())
        nodPivot.add(makeModel(Meshes.sphere(0.11), skin, at: [0, 0.1, 0], shadow: true))
        nodPivot.add(makeModel(Meshes.sphere(0.022), skin, at: [0.105, 0.1, 0]))
        nodPivot.add(makeModel(Meshes.sphere(0.022), skin, at: [-0.105, 0.1, 0]))
        let nose = nodPivot.add(makeModel(Meshes.sphere(0.016), skin, at: [0, 0.083, 0.106]))
        nose.scale = [0.8, 1.15, 0.9]

        // Eyes: white, iris and pupil, grouped so they can blink by squashing.
        let sclera = Materials.gloss(0xF4F1EC, roughness: 0.25)
        let iris = Materials.gloss(look.eyes, roughness: 0.2)
        let pupil = Materials.gloss(0x0D0D0D, roughness: 0.1)
        func eye(x: Float) -> Entity {
            let group = nodPivot.add(Entity())
            group.position = [x, 0.12, 0.09]
            group.add(makeModel(Meshes.sphere(0.016), sclera))
            group.add(makeModel(Meshes.sphere(0.0085), iris, at: [0, 0, 0.0105]))
            group.add(makeModel(Meshes.sphere(0.0042), pupil, at: [0, 0, 0.0152]))
            return group
        }
        let leftEye = eye(x: 0.038)
        let rightEye = eye(x: -0.038)

        func brow(x: Float) -> Entity {
            let piece = nodPivot.add(makeModel(Meshes.box(0.036, 0.007, 0.01, radius: 0.003), hair, at: [x, 0.146, 0.099]))
            // The outer end sits slightly lower.
            piece.orientation = simd_quatf(angle: x > 0 ? -0.12 : 0.12, axis: [0, 0, 1])
            return piece
        }
        let leftBrow = brow(x: 0.038)
        let rightBrow = brow(x: -0.038)

        nodPivot.add(makeModel(Meshes.box(0.046, 0.008, 0.012, radius: 0.003), lips, at: [0, 0.058, 0.099]))
        let mouth = nodPivot.add(makeModel(Meshes.box(0.036, 0.005, 0.011, radius: 0.002), Materials.matte(0x3A1E1E), at: [0, 0.0515, 0.0975]))
        let lowerLip = nodPivot.add(makeModel(Meshes.box(0.042, 0.009, 0.012, radius: 0.003), lips, at: [0, 0.045, 0.098]))

        switch look.hairStyle {
        case .short:
            nodPivot.add(makeModel(Meshes.sphere(0.118), hair, at: [0, 0.13, -0.025]))
        case .long:
            nodPivot.add(makeModel(Meshes.sphere(0.118), hair, at: [0, 0.13, -0.025]))
            nodPivot.add(makeModel(Meshes.box(0.23, 0.32, 0.08, radius: 0.035), hair, at: [0, -0.01, -0.085]))
            for side: Float in [1, -1] {
                nodPivot.add(makeModel(Meshes.box(0.035, 0.2, 0.09, radius: 0.015), hair, at: [0.104 * side, 0.04, -0.02]))
            }
        case .bun:
            nodPivot.add(makeModel(Meshes.sphere(0.118), hair, at: [0, 0.13, -0.025]))
            nodPivot.add(makeModel(Meshes.sphere(0.055), hair, at: [0, 0.2, -0.11]))
        case .curly:
            nodPivot.add(makeModel(Meshes.sphere(0.115), hair, at: [0, 0.13, -0.028]))
            let curls: [SIMD3<Float>] = [
                [0, 0.235, -0.01], [0.07, 0.215, 0.01], [-0.07, 0.215, 0.01], [0.095, 0.17, -0.04],
                [-0.095, 0.17, -0.04], [0.04, 0.2, -0.09], [-0.04, 0.2, -0.09], [0, 0.15, -0.12],
            ]
            for curl in curls {
                nodPivot.add(makeModel(Meshes.sphere(0.045), hair, at: curl))
            }
        case .none:
            break
        }

        let eyes = nodPivot.add(Entity())
        eyes.position = [0, 0.12, 0.09]
        let voice = nodPivot.add(Entity())
        voice.position = [0, 0.05, 0.1]

        return CharacterJoints(
            root: root,
            body: body,
            hips: hips,
            torso: torso,
            torsoMesh: torsoMesh,
            leftThigh: leftLeg.thigh,
            rightThigh: rightLeg.thigh,
            leftKnee: leftLeg.knee,
            rightKnee: rightLeg.knee,
            leftShoulder: leftArm.shoulder,
            rightShoulder: rightArm.shoulder,
            leftElbow: leftArm.elbow,
            rightElbow: rightArm.elbow,
            headPivot: headPivot,
            nodPivot: nodPivot,
            leftEye: leftEye,
            rightEye: rightEye,
            leftBrow: leftBrow,
            rightBrow: rightBrow,
            mouth: mouth,
            lowerLip: lowerLip,
            eyes: eyes,
            voice: voice
        )
    }

    /// Mixes two RGB colours; `amount` 0 gives `a`, 1 gives `b`.
    private static func blend(_ a: UInt32, _ b: UInt32, _ amount: Float) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let ca = Float((a >> shift) & 0xFF)
            let cb = Float((b >> shift) & 0xFF)
            return UInt32((ca + (cb - ca) * amount).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }
}
