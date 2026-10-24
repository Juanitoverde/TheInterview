import ARKit
import Foundation
import QuartzCore
import simd
import InterviewCore

/// The latest head position, shared with the RealityKit animation system so characters can look at you.
final class UserHeadPose: @unchecked Sendable {
    static let shared = UserHeadPose()

    private let lock = NSLock()
    private var storedPosition: SIMD3<Float>?

    var position: SIMD3<Float>? {
        get { lock.withLock { storedPosition } }
        set { lock.withLock { storedPosition = newValue } }
    }
}

/// Measures "eye contact" from head pose.
///
/// visionOS never exposes where a person's eyes are looking, so this uses ARKit's device pose
/// (head position and facing direction) and checks whether you're facing the interviewer's eyes.
@MainActor
final class HeadPoseAttentionTracker: AttentionTracking {
    /// Where the interviewer's eyes are, in world space. Set by the immersive scene.
    var target: (() -> SIMD3<Float>?)?
    /// Live engagement for the optional indicator: true/false while recording, nil otherwise.
    var onEngagementChange: ((Bool?) -> Void)?

    private let recorder = AttentionRecorder()
    private var session: ARKitSession?
    private var worldTracking: WorldTrackingProvider?
    private var pollTask: Task<Void, Never>?
    private var lastEngagement: Bool?

    static var isSupported: Bool { WorldTrackingProvider.isSupported }

    /// Starts device tracking. Requires an open immersive space; safe to call more than once.
    func startSession() async {
        guard Self.isSupported, session == nil else { return }
        let session = ARKitSession()
        let provider = WorldTrackingProvider()
        self.session = session
        do {
            try await session.run([provider])
        } catch {
            print("World tracking failed to start: \(error)")
            self.session = nil
            return
        }
        worldTracking = provider
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func stopSession() {
        pollTask?.cancel()
        pollTask = nil
        session?.stop()
        session = nil
        worldTracking = nil
        UserHeadPose.shared.position = nil
    }

    private func poll() {
        guard let provider = worldTracking, provider.state == .running,
              let anchor = provider.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()),
              anchor.isTracked
        else { return }

        let transform = anchor.originFromAnchorTransform
        let position = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        // The device looks down its -Z axis.
        let forward = -SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        UserHeadPose.shared.position = position

        guard recorder.isRecording, let target = target?() else { return }
        recorder.record(AttentionSample(
            time: CACurrentMediaTime(),
            headPosition: Vector3(position),
            headForward: Vector3(forward),
            target: Vector3(target)
        ))
        let engaged = recorder.isCurrentlyEngaged
        if engaged != lastEngagement {
            lastEngagement = engaged
            onEngagementChange?(engaged)
        }
    }

    // MARK: AttentionTracking

    func startTracking() {
        recorder.start()
    }

    func beginSegment() {
        recorder.beginSegment()
    }

    func endSegment() -> AttentionSummary {
        recorder.endSegment()
    }

    func stopTracking() -> AttentionSummary {
        let summary = recorder.stop()
        lastEngagement = nil
        onEngagementChange?(nil)
        return summary
    }
}

extension Vector3 {
    init(_ vector: SIMD3<Float>) {
        self.init(Double(vector.x), Double(vector.y), Double(vector.z))
    }
}
