import Foundation
import RealityKit

/// Optional 3D models dropped into the app bundle to replace the built-in office and characters.
///
/// - `Office.usdz` replaces the built-in office. Name entities inside it to position the scene
///   (see `OfficeLayout`).
/// - `Receptionist.usdz` and `Interviewer.usdz` replace the built-in people.
/// - `Anim_Idle.usdz`, `Anim_Walk.usdz`, `Anim_Sit.usdz`, … animate them (see `CharacterClip`).
///
/// Anything missing falls back to the procedural version.
@MainActor
struct OfficeAssets {
    var office: Entity?
    var receptionist: ModelCharacter?
    var interviewer: ModelCharacter?

    static func load() async -> OfficeAssets {
        let library = await AnimationLibrary.load()
        let office = try? await Entity(named: "Office", in: .main)
        let receptionist = await ModelCharacter.load(named: "Receptionist", height: 1.66, library: library)
        let interviewer = await ModelCharacter.load(named: "Interviewer", height: 1.78, library: library)
        return OfficeAssets(office: office, receptionist: receptionist, interviewer: interviewer)
    }
}

/// Where people stand and how the receptionist leads the user to the interview room.
///
/// The user starts at the origin facing -Z; place the reception desk ahead of them and arrange the
/// office so the interviewer is in the -Z direction from the candidate's seat.
struct OfficeLayout {
    var receptionistStart: SIMD3<Float>
    var interviewerChair: SIMD3<Float>
    /// Where the user ends up, facing the interviewer.
    var seat: SIMD3<Float>
    /// Where the receptionist stands after showing the user into the interview room.
    var guideRoomSpot: SIMD3<Float>
    /// Waypoints from reception to the interview room in a downloaded office.
    /// Nil means the built-in office, which has its own hand-tuned choreography.
    var route: [SIMD3<Float>]?

    static let builtIn = OfficeLayout(
        receptionistStart: [0, 0, -2.75],
        interviewerChair: [1.75, 0, -18.95],
        seat: [1.75, 0, -17.2],
        guideRoomSpot: [3.3, 0, -17.4],
        route: nil
    )

    /// The receptionist's way out after showing the user in.
    var exitRoute: [SIMD3<Float>] {
        guard let route else { return [[2.2, 0, -15.6], [2.2, 0, -12.5]] }
        return Array(route.reversed().prefix(2))
    }
}

extension OfficeLayout {
    /// Reads named marker entities from an office model, keeping built-in positions for any that are missing:
    /// `ReceptionistSpot`, `InterviewerChair`, `CandidateSeat`, `ReceptionistRoomSpot`, and `Route1`…`Route12`
    /// for the walk from reception to the interview room.
    init(markersIn office: Entity) {
        func marker(_ name: String) -> SIMD3<Float>? {
            office.findEntity(named: name)?.position(relativeTo: office)
        }
        let defaults = OfficeLayout.builtIn
        receptionistStart = marker("ReceptionistSpot") ?? defaults.receptionistStart
        interviewerChair = marker("InterviewerChair") ?? defaults.interviewerChair
        seat = marker("CandidateSeat") ?? defaults.seat
        guideRoomSpot = marker("ReceptionistRoomSpot") ?? defaults.guideRoomSpot
        let waypoints = (1...12).compactMap { marker("Route\($0)") }
        route = waypoints.isEmpty ? [seat] : waypoints
    }
}
