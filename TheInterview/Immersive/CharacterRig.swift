import Foundation
import RealityKit
import UIKit

struct CharacterAppearance {
    enum Hair {
        case short
        case long
        case bun
        case none
    }

    var skin: UInt32
    var hair: UInt32
    var hairStyle: Hair
    var top: UInt32
    var bottom: UInt32
    var shoes: UInt32 = 0x2B2B2B
    var tie: UInt32?
    var scale: Float = 1
    /// Shoulder and hip width multiplier.
    var build: Float = 1
}

/// The joints of a character. Pose animations and `CharacterAnimationSystem` rotate these.
struct CharacterJoints {
    let root: Entity
    /// Offset for sitting and the bob while walking.
    let body: Entity
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
    /// Rotated by nod animations, independent of looking.
    let nodPivot: Entity
    let mouth: Entity
    /// Marker between the eyes; the target for eye-contact measurement.
    let eyes: Entity
}

/// A stylised person built from primitives, facing +Z, with simple procedural animation.
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

    // MARK: State flags for the animation system

    func setTalking(_ talking: Bool) {
        updateAnimation { $0.isTalking = talking }
    }

    func setLooksAtUser(_ looks: Bool, range: Float = 7) {
        updateAnimation {
            $0.looksAtUser = looks
            $0.lookRange = range
        }
    }

    private func setTyping(_ typing: Bool) {
        updateAnimation { $0.isTyping = typing }
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
        if pose == .typing { setTyping(true) }
    }

    /// Starts animating to `pose` without waiting. With a zero duration the pose is applied immediately.
    func applyPose(_ pose: Pose, duration: TimeInterval = 0) {
        self.pose = pose
        let j = joints
        setTyping(false)
        switch pose {
        case .standing:
            move(j.body, to: .zero, duration: duration)
            for joint in [j.leftThigh, j.rightThigh, j.leftKnee, j.rightKnee, j.leftShoulder, j.rightShoulder] {
                rotate(joint, duration: duration)
            }
            rotate(j.leftElbow, x: -0.12, duration: duration)
            rotate(j.rightElbow, x: -0.12, duration: duration)
        case .sitting, .sittingAtDesk, .typing:
            // Thighs forward, shins down: hips drop to seat height.
            move(j.body, to: [0, -0.44, -0.05], duration: duration)
            rotate(j.leftThigh, x: -.pi / 2, duration: duration)
            rotate(j.rightThigh, x: -.pi / 2, duration: duration)
            rotate(j.leftKnee, x: .pi / 2, duration: duration)
            rotate(j.rightKnee, x: .pi / 2, duration: duration)
            let (shoulder, elbow): (Float, Float) = switch pose {
            case .sittingAtDesk: (-0.5, -1.15)
            case .typing: (-0.45, -1.1)
            default: (-0.15, -0.9)
            }
            for joint in [j.leftShoulder, j.rightShoulder] { rotate(joint, x: shoulder, duration: duration) }
            for joint in [j.leftElbow, j.rightElbow] { rotate(joint, x: elbow, duration: duration) }
        }
        if pose == .typing && duration <= 0 { setTyping(true) }
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
        // The right arm swings out to the side (-X) and up.
        rotate(j.rightShoulder, z: -2.6, duration: 0.4)
        await pause(0.4)
        for index in 0..<4 {
            rotate(j.rightElbow, z: index.isMultiple(of: 2) ? 0.4 : -0.3, duration: 0.22)
            await pause(0.22)
        }
        rotate(j.rightElbow, x: -0.12, duration: 0.3)
        rotate(j.rightShoulder, duration: 0.45)
        await pause(0.45)
    }

    func point(_ side: Side) async {
        let shoulder = side == .left ? joints.leftShoulder : joints.rightShoulder
        let elbow = side == .left ? joints.leftElbow : joints.rightElbow
        rotate(shoulder, x: -0.4, z: side == .left ? 1.25 : -1.25, duration: 0.45)
        rotate(elbow, x: -0.2, duration: 0.45)
        await pause(1.6)
        rotate(shoulder, duration: 0.5)
        rotate(elbow, x: -0.12, duration: 0.5)
        await pause(0.5)
    }

    func nod() async {
        for angle: Float in [0.22, 0, 0.16, 0] {
            rotate(joints.nodPivot, x: angle, duration: 0.18)
            await pause(0.18)
        }
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
        let skin = Materials.matte(look.skin, roughness: 0.7)
        let hair = Materials.matte(look.hair, roughness: 0.9)
        let top = Materials.matte(look.top)
        let bottom = Materials.matte(look.bottom)
        let shoes = Materials.gloss(look.shoes, roughness: 0.4)
        let dark = Materials.gloss(0x1C1C1C, roughness: 0.2)
        let width = look.build

        let root = Entity()
        root.scale = SIMD3<Float>(repeating: look.scale)
        let body = root.add(Entity())

        let hips = body.add(Entity())
        hips.position = [0, 0.97, 0]
        hips.add(makeModel(Meshes.box(0.34 * width, 0.18, 0.22, radius: 0.05), bottom, shadow: true))

        func leg(x: Float) -> (thigh: Entity, knee: Entity) {
            let thigh = hips.add(Entity())
            thigh.position = [x, -0.05, 0]
            thigh.add(makeModel(Meshes.cylinder(height: 0.44, radius: 0.07), bottom, at: [0, -0.22, 0], shadow: true))
            let knee = thigh.add(Entity())
            knee.position = [0, -0.44, 0]
            knee.add(makeModel(Meshes.cylinder(height: 0.42, radius: 0.055), bottom, at: [0, -0.21, 0], shadow: true))
            knee.add(makeModel(Meshes.box(0.1, 0.06, 0.24, radius: 0.025), shoes, at: [0, -0.45, 0.05], shadow: true))
            return (thigh, knee)
        }
        let leftLeg = leg(x: 0.095 * width)
        let rightLeg = leg(x: -0.095 * width)

        let torso = hips.add(Entity())
        torso.position = [0, 0.05, 0]
        let torsoMesh = torso.add(makeModel(Meshes.box(0.38 * width, 0.52, 0.22, radius: 0.07), top, at: [0, 0.26, 0], shadow: true))
        if let tie = look.tie {
            torso.add(makeModel(Meshes.box(0.05, 0.3, 0.01, radius: 0.004), Materials.matte(tie), at: [0, 0.3, 0.112]))
            torso.add(makeModel(Meshes.box(0.15, 0.05, 0.012, radius: 0.004), Materials.matte(0xF4F4F2), at: [0, 0.49, 0.105]))
        }

        func arm(x: Float) -> (shoulder: Entity, elbow: Entity) {
            let shoulder = torso.add(Entity())
            shoulder.position = [x, 0.47, 0]
            shoulder.add(makeModel(Meshes.sphere(0.055), top, shadow: true))
            shoulder.add(makeModel(Meshes.cylinder(height: 0.28, radius: 0.047), top, at: [0, -0.14, 0], shadow: true))
            let elbow = shoulder.add(Entity())
            elbow.position = [0, -0.29, 0]
            elbow.orientation = simd_quatf(angle: -0.12, axis: [1, 0, 0])
            elbow.add(makeModel(Meshes.cylinder(height: 0.26, radius: 0.04), top, at: [0, -0.13, 0], shadow: true))
            elbow.add(makeModel(Meshes.sphere(0.045), skin, at: [0, -0.29, 0], shadow: true))
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
        nodPivot.add(makeModel(Meshes.sphere(0.016), skin, at: [0, 0.085, 0.108]))
        for x: Float in [0.038, -0.038] {
            nodPivot.add(makeModel(Meshes.sphere(0.013), dark, at: [x, 0.12, 0.098]))
            nodPivot.add(makeModel(Meshes.box(0.034, 0.006, 0.01, radius: 0.002), hair, at: [x, 0.145, 0.099]))
        }
        let mouth = nodPivot.add(makeModel(Meshes.box(0.044, 0.008, 0.012, radius: 0.003), Materials.matte(0x7A3B3B), at: [0, 0.052, 0.1]))

        switch look.hairStyle {
        case .short:
            nodPivot.add(makeModel(Meshes.sphere(0.118), hair, at: [0, 0.13, -0.025]))
        case .long:
            nodPivot.add(makeModel(Meshes.sphere(0.118), hair, at: [0, 0.13, -0.025]))
            nodPivot.add(makeModel(Meshes.box(0.23, 0.32, 0.08, radius: 0.035), hair, at: [0, -0.01, -0.085]))
        case .bun:
            nodPivot.add(makeModel(Meshes.sphere(0.118), hair, at: [0, 0.13, -0.025]))
            nodPivot.add(makeModel(Meshes.sphere(0.055), hair, at: [0, 0.2, -0.11]))
        case .none:
            break
        }

        let eyes = nodPivot.add(Entity())
        eyes.position = [0, 0.12, 0.09]

        return CharacterJoints(
            root: root,
            body: body,
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
            mouth: mouth,
            eyes: eyes
        )
    }
}
