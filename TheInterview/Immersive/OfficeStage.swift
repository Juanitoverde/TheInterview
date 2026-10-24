import Foundation
import RealityKit
import UIKit
import InterviewCore

/// Runs the choreography in the immersive office.
///
/// The user stays where they are; "walking" moves the whole office around them. Everything that should
/// stay with the user (the control panel, ambient sound, the fade-to-black sphere) lives outside `world`.
@MainActor
final class OfficeStage: StageDirecting {
    let root = Entity()
    private let world: Entity
    private let hud = Entity()
    private let headAnchor = AnchorEntity(.head)
    private let fadeSphere: ModelEntity
    private let receptionist: any OfficeCharacter
    private let interviewer: any OfficeCharacter
    private let chatPair: (CharacterRig, CharacterRig)?
    private let layout: OfficeLayout
    private let comfortMode: Bool

    private var ambience: AudioPlaybackController?
    private var backgroundTasks: [Task<Void, Never>] = []
    /// The user's position in `world` coordinates.
    private var userPosition = SIMD3<Float>.zero

    /// Hand-tuned waypoints for the built-in office's walk.
    private enum Waypoint {
        static let besideDesk = SIMD3<Float>(1.6, 0, -2.9)
        static let corridorEntrance = SIMD3<Float>(2.2, 0, -3.7)
        static let guideLeads = SIMD3<Float>(2.2, 0, -5.0)
        static let userAtCorridor = SIMD3<Float>(2.2, 0, -1.3)
        static let guideInRoom = SIMD3<Float>(2.2, 0, -16.2)
        static let userAtDoor = SIMD3<Float>(2.2, 0, -14.4)
    }

    init(configuration: InterviewConfiguration, comfortMode: Bool, assets: OfficeAssets) {
        self.comfortMode = comfortMode
        let world = Entity()
        let cast = OfficeBuilder(companyName: configuration.companyName, interviewerName: configuration.interviewerName)
            .build(into: world, assets: assets)

        // A black sphere around the head for fading in and out. Negative scale renders its inside.
        let fadeSphere = ModelEntity(mesh: Meshes.sphere(0.35), materials: [UnlitMaterial(color: .black)])
        fadeSphere.scale = [-1, 1, 1]
        fadeSphere.components.set(OpacityComponent(opacity: 1))

        self.world = world
        self.fadeSphere = fadeSphere
        receptionist = cast.receptionist
        interviewer = cast.interviewer
        chatPair = cast.chatPair
        layout = cast.layout

        root.addChild(world)
        root.addChild(hud)
        root.addChild(headAnchor)
        headAnchor.addChild(fadeSphere)
        hud.position = [0, 1.0, -0.72]
    }

    /// World-space position of the interviewer's eyes, for eye-contact measurement.
    var interviewerEyePosition: SIMD3<Float> { interviewer.eyePosition }

    /// Places the SwiftUI control panel in front of the user, tilted up toward their eyes.
    func attachHUD(_ panel: Entity) {
        panel.orientation = simd_quatf(angle: -0.3, axis: [1, 0, 0])
        hud.addChild(panel)
    }

    // MARK: Lifecycle

    func start() {
        if let resource = try? AudioFileResource.load(named: "office_ambience.wav", configuration: .init(shouldLoop: true)) {
            let speaker = Entity()
            speaker.components.set(AmbientAudioComponent())
            hud.addChild(speaker)
            let controller = speaker.playAudio(resource)
            controller.gain = -14
            ambience = controller
        }

        // The two colleagues in the aisle take turns talking.
        guard let pair = chatPair else { return }
        backgroundTasks.append(Task {
            var turn = 0
            while !Task.isCancelled {
                pair.0.setTalking(turn.isMultiple(of: 2))
                pair.1.setTalking(!turn.isMultiple(of: 2))
                turn += 1
                try? await Task.sleep(for: .seconds(Double.random(in: 2.5...5.5)))
            }
        })
    }

    func tearDown() {
        backgroundTasks.forEach { $0.cancel() }
        backgroundTasks.removeAll()
        ambience?.stop()
        ambience = nil
    }

    func setSpeaking(_ speaker: Speaker?) {
        receptionist.setTalking(speaker == .receptionist)
        interviewer.setTalking(speaker == .interviewer)
    }

    /// Lowers the office ambience while the microphone is listening, and has the characters listen attentively.
    func setListening(_ listening: Bool) {
        ambience?.fade(to: listening ? -26 : -14, duration: 0.6)
        receptionist.setAttentive(listening)
        interviewer.setAttentive(listening)
    }

    /// Where a character's voice should come from, or nil if they've left the scene.
    func voiceSource(for speaker: Speaker) -> Entity? {
        switch speaker {
        case .receptionist: receptionist.root.isEnabled ? receptionist.voiceSource : nil
        case .interviewer: interviewer.voiceSource
        case .candidate: nil
        }
    }

    // MARK: StageDirecting

    func perform(_ cue: StageCue) async {
        switch cue {
        case .enterReception:
            positionHUD()
            await fade(to: 0, duration: 1.4)
        case .receptionistWaves:
            await receptionist.wave()
        case .receptionistPointsTheWay:
            // The corridor is to the receptionist's left as she faces the user.
            await receptionist.point(.left)
        case .walkToInterviewRoom:
            await walkToInterviewRoom()
        case .receptionistLeaves:
            await receptionist.walk(through: layout.exitRoute, duration: 4.5)
            await receptionist.fade(to: 0, duration: 0.6)
            receptionist.root.isEnabled = false
        case .interviewerStands:
            interviewer.setLooksAtUser(true, range: 9)
            await interviewer.setPose(.standing, duration: 0.9)
        case .interviewerSits:
            await interviewer.setPose(.sittingAtDesk, duration: 0.9)
        case .focusOnInterviewer:
            // Settle into the seat directly across the desk and bring the panel to the new eye height.
            await moveUser(to: layout.seat, duration: 0.8)
            positionHUD()
        case .interviewerNods:
            await interviewer.nod()
        case .exitOffice:
            ambience?.fade(to: -60, duration: 1.2)
            await fade(to: 1, duration: 1.2)
        }
    }

    // MARK: Choreography

    private func walkToInterviewRoom() async {
        receptionist.setLooksAtUser(false, range: 7)
        if comfortMode {
            await fade(to: 1, duration: 0.6)
            await moveUser(to: layout.seat, duration: 0)
            receptionist.place(at: layout.guideRoomSpot, yaw: Entity.yaw(toward: userPosition - layout.guideRoomSpot))
            await fade(to: 0, duration: 0.8)
            receptionist.setLooksAtUser(true, range: 7)
            return
        }
        if let route = layout.route {
            await walk(alongRoute: route)
        } else {
            await walkThroughBuiltInOffice()
        }
        await receptionist.turn(toward: userPosition, duration: 0.4)
        receptionist.setLooksAtUser(true, range: 7)
        await receptionist.point(.right)
    }

    private func walkThroughBuiltInOffice() async {
        // The receptionist comes around the desk...
        await receptionist.walk(through: [Waypoint.besideDesk, Waypoint.corridorEntrance], duration: 2.4)
        guard !Task.isCancelled else { return }

        // ...and leads the way while the user follows, down the corridor and into the interview room.
        let guide = receptionist
        async let guideStep: Void = guide.walk(through: [Waypoint.guideLeads], duration: 2.4)
        async let userStep: Void = moveUser(to: Waypoint.userAtCorridor, duration: 2.4, timing: .easeIn)
        _ = await (guideStep, userStep)
        guard !Task.isCancelled else { return }

        async let guideCorridor: Void = guide.walk(through: [Waypoint.guideInRoom], duration: 11)
        async let userCorridor: Void = moveUser(to: Waypoint.userAtDoor, duration: 11, timing: .linear)
        _ = await (guideCorridor, userCorridor)
        guard !Task.isCancelled else { return }

        async let guideAside: Void = guide.walk(through: [layout.guideRoomSpot], duration: 1.8)
        async let userSeat: Void = moveUser(to: layout.seat, duration: 2.6, timing: .easeOut)
        _ = await (guideAside, userSeat)
    }

    /// A downloaded office's route: the receptionist stays one waypoint ahead while the user follows.
    private func walk(alongRoute route: [SIMD3<Float>]) async {
        let guide = receptionist
        guard let first = route.first else { return }
        await guide.walk(through: [first], duration: walkingTime(from: guide.root.position, to: first))
        for (index, waypoint) in route.enumerated() {
            guard !Task.isCancelled else { return }
            let guideTarget = index + 1 < route.count ? route[index + 1] : layout.guideRoomSpot
            let legTime = walkingTime(from: userPosition, to: waypoint)
            async let guideLeg: Void = guide.walk(through: [guideTarget], duration: legTime)
            async let userLeg: Void = moveUser(to: waypoint, duration: legTime, timing: .linear)
            _ = await (guideLeg, userLeg)
        }
        if simd_distance(userPosition, layout.seat) > 0.05 {
            await moveUser(to: layout.seat, duration: walkingTime(from: userPosition, to: layout.seat), timing: .easeOut)
        }
    }

    /// About 1.1 m/s, a comfortable pace for being moved in VR.
    private func walkingTime(from start: SIMD3<Float>, to end: SIMD3<Float>) -> TimeInterval {
        let distance = simd_distance(SIMD2<Float>(start.x, start.z), SIMD2<Float>(end.x, end.z))
        return max(Double(distance) / 1.1, 0.8)
    }

    /// Moves the office so the user appears to be at `position` (in world coordinates).
    private func moveUser(to position: SIMD3<Float>, duration: TimeInterval, timing: AnimationTimingFunction = .easeInOut) async {
        userPosition = position
        var transform = world.transform
        transform.translation = SIMD3<Float>(-position.x, 0, -position.z)
        guard duration > 0 else {
            world.transform = transform
            return
        }
        world.move(to: transform, relativeTo: root, duration: duration, timingFunction: timing)
        try? await Task.sleep(for: .seconds(duration))
    }

    private func positionHUD() {
        let head = UserHeadPose.shared.position ?? SIMD3<Float>(0, 1.5, 0)
        hud.position = SIMD3<Float>(head.x, max(0.7, head.y - 0.5), head.z - 0.72)
    }

    private func fade(to opacity: Float, duration: TimeInterval) async {
        fadeSphere.isEnabled = true
        let start = fadeSphere.components[OpacityComponent.self]?.opacity ?? 0
        let steps = max(Int(duration * 45), 1)
        for step in 1...steps {
            fadeSphere.components.set(OpacityComponent(opacity: start + (opacity - start) * Float(step) / Float(steps)))
            try? await Task.sleep(for: .seconds(duration / Double(steps)))
        }
        if opacity <= 0 {
            fadeSphere.isEnabled = false
        }
    }
}
