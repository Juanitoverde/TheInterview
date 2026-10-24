import Foundation
import RealityKit

/// Per-character animation state read every frame by `CharacterAnimationSystem`.
struct CharacterAnimationComponent: Component {
    var joints: CharacterJoints
    var isTalking = false
    var isWalking = false
    var isTyping = false
    var looksAtUser = false
    /// Only look at the user when they're closer than this (metres).
    var lookRange: Float = 7
    /// Stride cycles per second while walking.
    var walkCadence: Float = 0.85

    var breathPhase = Float.random(in: 0..<(2 * .pi))
    var talkPhase: Float = 0
    var walkPhase: Float = 0
    var typingPhase = Float.random(in: 0..<(2 * .pi))
    var headYaw: Float = 0
    var headPitch: Float = 0

    init(joints: CharacterJoints) {
        self.joints = joints
    }
}

/// Breathing, talking, walking, typing and looking at the user, for every character in the scene.
struct CharacterAnimationSystem: System {
    static let query = EntityQuery(where: .has(CharacterAnimationComponent.self))

    /// Used when head tracking isn't available (e.g. the simulator): a typical standing eye height.
    private static let fallbackHead = SIMD3<Float>(0, 1.5, 0)

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let dt = Float(min(context.deltaTime, 0.1))
        let userHead = UserHeadPose.shared.position ?? Self.fallbackHead

        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var state = entity.components[CharacterAnimationComponent.self] else { continue }
            let joints = state.joints

            // Breathing
            state.breathPhase += dt * 1.7
            let breath = sin(state.breathPhase)
            joints.torsoMesh.scale = SIMD3<Float>(1 + 0.008 * breath, 1 + 0.012 * breath, 1 + 0.012 * breath)

            // Talking: the mouth opens and closes irregularly.
            if state.isTalking {
                state.talkPhase += dt * 15
                let open = 0.35 + 0.65 * abs(sin(state.talkPhase) * sin(state.talkPhase * 0.43 + 0.7))
                joints.mouth.scale = SIMD3<Float>(1, 1 + 3.2 * open, 1)
            } else if joints.mouth.scale.y != 1 {
                joints.mouth.scale = .one
            }

            // Walking: legs and arms swing in opposition with a slight bob.
            if state.isWalking {
                state.walkPhase += dt * state.walkCadence * 2 * .pi
                let swing = sin(state.walkPhase)
                joints.leftThigh.orientation = simd_quatf(angle: -0.42 * swing, axis: [1, 0, 0])
                joints.rightThigh.orientation = simd_quatf(angle: 0.42 * swing, axis: [1, 0, 0])
                joints.leftKnee.orientation = simd_quatf(angle: 0.1 + 0.45 * max(0, swing), axis: [1, 0, 0])
                joints.rightKnee.orientation = simd_quatf(angle: 0.1 + 0.45 * max(0, -swing), axis: [1, 0, 0])
                joints.leftShoulder.orientation = simd_quatf(angle: 0.32 * swing, axis: [1, 0, 0])
                joints.rightShoulder.orientation = simd_quatf(angle: -0.32 * swing, axis: [1, 0, 0])
                joints.body.position.y = 0.018 * abs(cos(state.walkPhase))
            }

            // Typing: small alternating forearm movements.
            if state.isTyping {
                state.typingPhase += dt * 9
                joints.leftElbow.orientation = simd_quatf(angle: -1.1 + 0.06 * sin(state.typingPhase), axis: [1, 0, 0])
                joints.rightElbow.orientation = simd_quatf(angle: -1.1 + 0.06 * sin(state.typingPhase + 1.9), axis: [1, 0, 0])
            }

            // Looking at the user, within a natural range of head rotation.
            var targetYaw: Float = 0
            var targetPitch: Float = 0
            if state.looksAtUser, let parent = joints.headPivot.parent {
                let local = parent.convert(position: userHead, from: nil) - joints.headPivot.position
                let horizontal = (local.x * local.x + local.z * local.z).squareRoot()
                let yaw = atan2(local.x, local.z)
                if simd_length(local) < state.lookRange, abs(yaw) < 1.4 {
                    targetYaw = max(-1.0, min(1.0, yaw))
                    targetPitch = max(-0.45, min(0.45, atan2(-local.y, horizontal)))
                }
            }
            let blend = min(1, dt * 4)
            state.headYaw += (targetYaw - state.headYaw) * blend
            state.headPitch += (targetPitch - state.headPitch) * blend
            joints.headPivot.orientation = simd_quatf(angle: state.headYaw, axis: [0, 1, 0]) * simd_quatf(angle: state.headPitch, axis: [1, 0, 0])

            entity.components[CharacterAnimationComponent.self] = state
        }
    }
}
