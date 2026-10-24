import Foundation
import RealityKit

/// Per-character animation state read and advanced every frame by `CharacterAnimationSystem`.
struct CharacterAnimationComponent: Component {
    var joints: CharacterJoints
    var isTalking = false
    var isWalking = false
    var isTyping = false
    var isAttentive = false
    var looksAtUser = false
    /// While a scripted gesture (wave, point) is animating the arms, the system leaves them alone.
    var gestureActive = false
    /// Only look at the user when they're closer than this (metres).
    var lookRange: Float = 7
    /// Stride cycles per second while walking.
    var walkCadence: Float = 0.85

    // Arm and lean targets for the current pose, and the eased current values.
    var shoulderTarget: Float = 0
    var elbowTarget: Float = -0.12
    /// Keeps the right forearm raised, e.g. holding a cup.
    var rightElbowOverride: Float?
    var leanTarget: Float = 0
    var shoulderLeft: Float = 0
    var shoulderRight: Float = 0
    var elbowLeft: Float = -0.12
    var elbowRight: Float = -0.12
    var lean: Float = 0

    // A scripted nod: time into it (negative when idle), how deep, how many dips.
    var nodTime: Float = -1
    var nodStrength: Float = 0
    var nodCount: Int = 0

    var time = Float.random(in: 0..<100)
    var talkPhase: Float = 0
    var walkPhase: Float = 0
    var gestureBlend: Float = 0
    var headYaw: Float = 0
    var headPitch: Float = 0
    var headRoll: Float = 0
    var blinkCountdown = Float.random(in: 1...4)
    var blinkRemaining: Float = 0
    var listeningNodCountdown = Float.random(in: 3...7)

    init(joints: CharacterJoints) {
        self.joints = joints
    }
}

/// Breathing, blinking, talking, gesturing, walking, typing, nodding and looking at the user.
struct CharacterAnimationSystem: System {
    static let query = EntityQuery(where: .has(CharacterAnimationComponent.self))

    /// Used when head tracking isn't available (e.g. the simulator): a typical standing eye height.
    private static let fallbackHead = SIMD3<Float>(0, 1.5, 0)

    private static let browRestY: Float = 0.146
    private static let lowerLipRestY: Float = 0.045

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let dt = Float(min(context.deltaTime, 0.1))
        let userHead = UserHeadPose.shared.position ?? Self.fallbackHead

        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var state = entity.components[CharacterAnimationComponent.self] else { continue }
            let j = state.joints
            state.time += dt
            let t = state.time

            // Breathing.
            let breath = sin(t * 1.7)
            j.torsoMesh.scale = SIMD3<Float>(1 + 0.008 * breath, 1 + 0.012 * breath, 1 + 0.012 * breath)

            // Blinking every few seconds.
            state.blinkCountdown -= dt
            if state.blinkCountdown <= 0 {
                state.blinkRemaining = 0.13
                state.blinkCountdown = Float.random(in: 2...5.5)
            }
            let eyeOpen: Float = state.blinkRemaining > 0 ? 0.12 : 1
            state.blinkRemaining = max(0, state.blinkRemaining - dt)
            j.leftEye.scale = SIMD3<Float>(1, eyeOpen, 1)
            j.rightEye.scale = SIMD3<Float>(1, eyeOpen, 1)

            // Talking: lips part irregularly and the brows lift on emphasis.
            var open: Float = 0
            var browLift: Float = 0
            if state.isTalking {
                state.talkPhase += dt * 15
                open = 0.3 + 0.7 * abs(sin(state.talkPhase) * sin(state.talkPhase * 0.43 + 0.7))
                browLift = max(0, sin(state.talkPhase * 0.17)) * 0.004
            }
            j.mouth.scale = SIMD3<Float>(1, 1 + 3.5 * open, 1)
            j.lowerLip.position.y = Self.lowerLipRestY - 0.007 * open
            j.leftBrow.position.y = Self.browRestY + browLift
            j.rightBrow.position.y = Self.browRestY + browLift

            // Idle weight shift and a gentle lean toward the pose's target.
            state.lean += (state.leanTarget - state.lean) * min(1, dt * 3)
            j.hips.position.x = state.isWalking ? 0 : 0.007 * sin(t * 0.45)
            j.torso.orientation = simd_quatf(angle: 0.025 * sin(t * 0.31 + 1), axis: [0, 1, 0])
                * simd_quatf(angle: state.lean + 0.01 * sin(t * 0.53), axis: [1, 0, 0])

            updateArms(&state, joints: j, dt: dt)
            updateHead(&state, joints: j, dt: dt, userHead: userHead)

            entity.components[CharacterAnimationComponent.self] = state
        }
    }

    private func updateArms(_ state: inout CharacterAnimationComponent, joints j: CharacterJoints, dt: Float) {
        if state.isWalking {
            // Legs and arms swing in opposition, with a slight bob.
            state.walkPhase += dt * state.walkCadence * 2 * .pi
            let swing = sin(state.walkPhase)
            j.leftThigh.orientation = simd_quatf(angle: -0.42 * swing, axis: [1, 0, 0])
            j.rightThigh.orientation = simd_quatf(angle: 0.42 * swing, axis: [1, 0, 0])
            j.leftKnee.orientation = simd_quatf(angle: 0.1 + 0.45 * max(0, swing), axis: [1, 0, 0])
            j.rightKnee.orientation = simd_quatf(angle: 0.1 + 0.45 * max(0, -swing), axis: [1, 0, 0])
            j.body.position.y = 0.018 * abs(cos(state.walkPhase))
            state.shoulderLeft = 0.32 * swing
            state.shoulderRight = -0.32 * swing
            state.elbowLeft = -0.25
            state.elbowRight = -0.25
        } else if !state.gestureActive {
            let ease = min(1, dt * 4)
            state.shoulderLeft += (state.shoulderTarget - state.shoulderLeft) * ease
            state.shoulderRight += (state.shoulderTarget - state.shoulderRight) * ease
            state.elbowLeft += (state.elbowTarget - state.elbowLeft) * ease
            state.elbowRight += ((state.rightElbowOverride ?? state.elbowTarget) - state.elbowRight) * ease
        } else {
            return
        }

        // Hands move naturally while talking (unless walking or typing).
        let gesturing = state.isTalking && !state.isWalking && !state.isTyping
        state.gestureBlend += ((gesturing ? 1 : 0) - state.gestureBlend) * min(1, dt * 2.5)
        let g = state.gestureBlend
        let t = state.time
        let leftWave = 0.5 + 0.5 * sin(t * 1.3)
        // A hand holding something stays still.
        let rightWave = state.rightElbowOverride == nil ? 0.5 + 0.5 * sin(t * 1.05 + 2) : 0

        var leftElbow = state.elbowLeft - g * 0.35 * leftWave
        var rightElbow = state.elbowRight - g * 0.3 * rightWave
        if state.isTyping {
            leftElbow += 0.06 * sin(t * 9)
            rightElbow += 0.06 * sin(t * 9 + 1.9)
        }
        j.leftShoulder.orientation = simd_quatf(angle: state.shoulderLeft - g * 0.08 * leftWave, axis: [1, 0, 0])
            * simd_quatf(angle: g * 0.1 * leftWave, axis: [0, 0, 1])
        j.rightShoulder.orientation = simd_quatf(angle: state.shoulderRight - g * 0.08 * rightWave, axis: [1, 0, 0])
            * simd_quatf(angle: -g * 0.1 * rightWave, axis: [0, 0, 1])
        j.leftElbow.orientation = simd_quatf(angle: leftElbow, axis: [1, 0, 0])
        j.rightElbow.orientation = simd_quatf(angle: rightElbow, axis: [1, 0, 0])
    }

    private func updateHead(_ state: inout CharacterAnimationComponent, joints j: CharacterJoints, dt: Float, userHead: SIMD3<Float>) {
        // Active listening: an occasional small nod.
        if state.isAttentive && !state.isTalking && state.nodTime < 0 {
            state.listeningNodCountdown -= dt
            if state.listeningNodCountdown <= 0 {
                state.nodTime = 0
                state.nodStrength = 0.09
                state.nodCount = 1
                state.listeningNodCountdown = Float.random(in: 3.5...8)
            }
        }
        var nod: Float = 0
        if state.nodTime >= 0 {
            state.nodTime += dt
            let frequency: Float = 1.5
            if state.nodTime < Float(state.nodCount) / frequency {
                nod = state.nodStrength * max(0, sin(state.nodTime * frequency * 2 * .pi))
            } else {
                state.nodTime = -1
            }
        }
        // A slight head tilt while listening attentively.
        let rollTarget: Float = state.isAttentive && !state.isTalking ? 0.06 : 0.015 * sin(state.time * 0.4)
        state.headRoll += (rollTarget - state.headRoll) * min(1, dt * 2)
        j.nodPivot.orientation = simd_quatf(angle: nod, axis: [1, 0, 0]) * simd_quatf(angle: state.headRoll, axis: [0, 0, 1])

        // Look at the user, within a natural range of head rotation.
        var targetYaw: Float = 0
        var targetPitch: Float = 0
        if state.looksAtUser, let parent = j.headPivot.parent {
            let local = parent.convert(position: userHead, from: nil) - j.headPivot.position
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
        j.headPivot.orientation = simd_quatf(angle: state.headYaw, axis: [0, 1, 0]) * simd_quatf(angle: state.headPitch, axis: [1, 0, 0])
    }
}
