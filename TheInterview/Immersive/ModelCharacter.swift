import Foundation
import RealityKit

/// What the stage needs from a character, whether built from primitives or loaded from a USDZ model.
@MainActor
protocol OfficeCharacter: AnyObject {
    var root: Entity { get }
    /// World-space position between the eyes; the target for eye-contact measurement.
    var eyePosition: SIMD3<Float> { get }
    /// Where the character's voice comes from.
    var voiceSource: Entity { get }
    func place(at position: SIMD3<Float>, yaw: Float)
    func turn(toward target: SIMD3<Float>, duration: TimeInterval) async
    func setTalking(_ talking: Bool)
    func setLooksAtUser(_ looks: Bool, range: Float)
    func setAttentive(_ attentive: Bool)
    func setPose(_ pose: CharacterRig.Pose, duration: TimeInterval) async
    func applyPose(_ pose: CharacterRig.Pose, duration: TimeInterval)
    func walk(through points: [SIMD3<Float>], duration: TimeInterval) async
    func wave() async
    func point(_ side: CharacterRig.Side) async
    func nod() async
    func fade(to opacity: Float, duration: TimeInterval) async
}

extension CharacterRig: OfficeCharacter {}

/// Animation clips for downloaded characters, loaded from `Anim_<name>.usdz` files in the app bundle.
/// All clips should come from the same skeleton (for example, Mixamo animations for one Mixamo character).
enum CharacterClip: String, CaseIterable {
    case idle = "Idle"
    case walk = "Walk"
    case talk = "Talk"
    case sit = "Sit"
    case sitTalk = "SitTalk"
    case type = "Type"
    case sitDown = "SitDown"
    case standUp = "StandUp"
    case wave = "Wave"
    case point = "Point"
    case nod = "Nod"
}

@MainActor
final class AnimationLibrary {
    private(set) var clips: [CharacterClip: AnimationResource] = [:]

    var isEmpty: Bool { clips.isEmpty }

    static func load() async -> AnimationLibrary {
        let library = AnimationLibrary()
        for clip in CharacterClip.allCases {
            if let entity = try? await Entity(named: "Anim_\(clip.rawValue)", in: .main),
               let animation = entity.availableAnimations.first {
                library.clips[clip] = animation
            }
        }
        return library
    }
}

/// A character loaded from a USDZ model (Mixamo, Character Creator, a converted MetaHuman, …),
/// animated with clips from an `AnimationLibrary`.
///
/// The model should face +Z with its feet at the origin, like a Mixamo export. It's scaled to `height`.
@MainActor
final class ModelCharacter: OfficeCharacter {
    let root = Entity()
    let voiceSource = Entity()
    private let model: Entity
    private let eyes = Entity()
    private let library: AnimationLibrary
    private var pose: CharacterRig.Pose = .standing
    private var isTalking = false
    private var isWalking = false
    private var isPlayingGesture = false
    private var currentLoop: CharacterClip?

    var eyePosition: SIMD3<Float> { eyes.position(relativeTo: nil) }

    /// Loads `<name>.usdz` from the app bundle, or returns nil if there isn't one.
    static func load(named name: String, height: Float, library: AnimationLibrary) async -> ModelCharacter? {
        guard let model = try? await Entity(named: name, in: .main) else { return nil }
        return ModelCharacter(model: model, height: height, library: library)
    }

    private init(model: Entity, height: Float, library: AnimationLibrary) {
        self.model = model
        self.library = library

        // Scale to a realistic height and stand the feet on the floor.
        let bounds = model.visualBounds(relativeTo: nil)
        model.scale *= height / max(bounds.extents.y, 0.01)
        model.position.y -= model.visualBounds(relativeTo: nil).min.y
        root.addChild(model)

        eyes.position = [0, height * 0.93, 0.09]
        root.addChild(eyes)
        voiceSource.position = [0, height * 0.88, 0.1]
        root.addChild(voiceSource)

        // Use the model's own animation as the idle loop if no clips were provided.
        if library.isEmpty, let own = model.availableAnimations.first {
            model.playAnimation(own.repeat(), transitionDuration: 0, startsPaused: false)
        } else {
            refreshLoop(transition: 0)
        }
    }

    // MARK: OfficeCharacter

    func place(at position: SIMD3<Float>, yaw: Float) {
        root.position = position
        root.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
    }

    func turn(toward target: SIMD3<Float>, duration: TimeInterval) async {
        await turn(toYaw: Entity.yaw(toward: target - root.position), duration: duration)
    }

    func setTalking(_ talking: Bool) {
        isTalking = talking
        refreshLoop()
    }

    // Model characters keep their animated head pose; these have no effect.
    func setLooksAtUser(_ looks: Bool, range: Float) {}
    func setAttentive(_ attentive: Bool) {}

    func setPose(_ pose: CharacterRig.Pose, duration: TimeInterval) async {
        let sitting = pose != .standing
        let wasSitting = self.pose != .standing
        if sitting != wasSitting {
            await playOnce(sitting ? .sitDown : .standUp)
        }
        applyPose(pose, duration: 0.3)
    }

    func applyPose(_ pose: CharacterRig.Pose, duration: TimeInterval) {
        self.pose = pose
        refreshLoop(transition: duration)
    }

    func walk(through points: [SIMD3<Float>], duration: TimeInterval) async {
        var previous = root.position
        var total: Float = 0
        for point in points {
            total += simd_distance(previous, point)
            previous = point
        }
        guard total > 0.01, duration > 0 else { return }
        pose = .standing
        isWalking = true
        refreshLoop()
        let turnTime: TimeInterval = 0.3
        let moveTime = max(duration - turnTime * Double(points.count), 0.3)
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
            root.move(to: transform, relativeTo: root.parent, duration: time, timingFunction: .linear)
            try? await Task.sleep(for: .seconds(time))
            start = point
        }
        isWalking = false
        refreshLoop()
    }

    func wave() async {
        await playOnce(.wave)
    }

    func point(_ side: CharacterRig.Side) async {
        await playOnce(.point)
    }

    func nod() async {
        await playOnce(.nod)
    }

    func fade(to opacity: Float, duration: TimeInterval) async {
        let start = root.components[OpacityComponent.self]?.opacity ?? 1
        let steps = max(Int(duration * 30), 1)
        for step in 1...steps {
            root.components.set(OpacityComponent(opacity: start + (opacity - start) * Float(step) / Float(steps)))
            try? await Task.sleep(for: .seconds(duration / Double(steps)))
        }
    }

    // MARK: Animation

    private func turn(toYaw yaw: Float, duration: TimeInterval) async {
        var transform = root.transform
        transform.rotation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        root.move(to: transform, relativeTo: root.parent, duration: duration, timingFunction: .easeInOut)
        try? await Task.sleep(for: .seconds(duration))
    }

    /// The looping clip for the current state, falling back to simpler clips that exist.
    private func loopClip() -> CharacterClip? {
        let available = library.clips
        func first(_ candidates: [CharacterClip]) -> CharacterClip? {
            candidates.first { available[$0] != nil }
        }
        if isWalking { return first([.walk, .idle]) }
        switch pose {
        case .standing:
            return isTalking ? first([.talk, .idle]) : first([.idle])
        case .typing:
            return first([.type, .sit, .idle])
        case .sitting, .sittingAtDesk:
            return isTalking ? first([.sitTalk, .sit, .idle]) : first([.sit, .idle])
        }
    }

    private func refreshLoop(transition: TimeInterval = 0.35) {
        guard !isPlayingGesture, let clip = loopClip(), clip != currentLoop, let animation = library.clips[clip] else { return }
        currentLoop = clip
        model.playAnimation(animation.repeat(), transitionDuration: transition, startsPaused: false)
    }

    private func playOnce(_ clip: CharacterClip) async {
        guard let animation = library.clips[clip] else { return }
        isPlayingGesture = true
        currentLoop = nil
        model.playAnimation(animation, transitionDuration: 0.25, startsPaused: false)
        try? await Task.sleep(for: .seconds(max(animation.definition.duration - 0.25, 0.1)))
        isPlayingGesture = false
        refreshLoop(transition: 0.25)
    }
}
