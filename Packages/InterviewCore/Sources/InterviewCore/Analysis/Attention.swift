import Foundation

/// Minimal 3D vector so attention maths stays platform-independent and testable (no simd on Linux).
public struct Vector3: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static func - (lhs: Vector3, rhs: Vector3) -> Vector3 {
        Vector3(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
    }

    public var length: Double { (x * x + y * y + z * z).squareRoot() }

    public var horizontalLength: Double { (x * x + z * z).squareRoot() }

    public var normalized: Vector3 {
        let l = length
        return l > 0 ? Vector3(x / l, y / l, z / l) : self
    }

    public func dot(_ other: Vector3) -> Double {
        x * other.x + y * other.y + z * other.z
    }
}

/// One head-pose reading: where the candidate's head is, which way it faces, and where the interviewer's eyes are.
///
/// visionOS does not give apps access to eye-tracking data, so "eye contact" is approximated from head
/// orientation: people naturally turn their head toward whoever they are looking at.
public struct AttentionSample: Codable, Equatable, Sendable {
    public var time: TimeInterval
    public var headPosition: Vector3
    public var headForward: Vector3
    public var target: Vector3

    public init(time: TimeInterval, headPosition: Vector3, headForward: Vector3, target: Vector3) {
        self.time = time
        self.headPosition = headPosition
        self.headForward = headForward
        self.target = target
    }
}

public struct AttentionThresholds: Equatable, Sendable {
    /// Maximum left/right deviation from the interviewer that still counts as eye contact.
    public var yawDegrees: Double
    /// Maximum up/down deviation that still counts as eye contact.
    public var pitchDegrees: Double
    /// Looking away for less than this (a natural glance) isn't counted as a look-away.
    public var minimumLookAwaySeconds: Double
    /// Gaps between samples longer than this (tracking loss) are capped so they don't skew durations.
    public var maximumSampleGap: Double

    public init(yawDegrees: Double = 20, pitchDegrees: Double = 18, minimumLookAwaySeconds: Double = 1.0, maximumSampleGap: Double = 0.5) {
        self.yawDegrees = yawDegrees
        self.pitchDegrees = pitchDegrees
        self.minimumLookAwaySeconds = minimumLookAwaySeconds
        self.maximumSampleGap = maximumSampleGap
    }

    public static let standard = AttentionThresholds()
}

public struct AttentionSummary: Codable, Equatable, Sendable {
    public var sampleCount: Int
    public var trackedSeconds: Double
    /// Fraction of tracked time spent facing the interviewer, 0...1.
    public var engagedRatio: Double
    public var lookAwayCount: Int
    public var longestLookAwaySeconds: Double
    public var averageDeviationDegrees: Double

    public init(sampleCount: Int, trackedSeconds: Double, engagedRatio: Double, lookAwayCount: Int, longestLookAwaySeconds: Double, averageDeviationDegrees: Double) {
        self.sampleCount = sampleCount
        self.trackedSeconds = trackedSeconds
        self.engagedRatio = engagedRatio
        self.lookAwayCount = lookAwayCount
        self.longestLookAwaySeconds = longestLookAwaySeconds
        self.averageDeviationDegrees = averageDeviationDegrees
    }

    public static let unavailable = AttentionSummary(
        sampleCount: 0, trackedSeconds: 0, engagedRatio: 0, lookAwayCount: 0, longestLookAwaySeconds: 0, averageDeviationDegrees: 0
    )

    /// True when enough data was collected for the numbers to mean something.
    public var isAvailable: Bool { sampleCount >= 3 && trackedSeconds > 0.5 }
}

public enum AttentionAnalyzer {
    private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }

    /// Horizontal (yaw) and vertical (pitch) angle in degrees between where the head faces and the target.
    public static func deviation(of sample: AttentionSample) -> (yaw: Double, pitch: Double) {
        let forward = sample.headForward.normalized
        let toTarget = (sample.target - sample.headPosition).normalized

        var yaw = 0.0
        let fh = forward.horizontalLength
        let th = toTarget.horizontalLength
        if fh > 1e-6, th > 1e-6 {
            let cosine = (forward.x * toTarget.x + forward.z * toTarget.z) / (fh * th)
            yaw = degrees(acos(min(max(cosine, -1), 1)))
        }
        let pitch = abs(degrees(atan2(forward.y, fh)) - degrees(atan2(toTarget.y, th)))
        return (yaw, pitch)
    }

    public static func isEngaged(_ sample: AttentionSample, thresholds: AttentionThresholds = .standard) -> Bool {
        let d = deviation(of: sample)
        return d.yaw <= thresholds.yawDegrees && d.pitch <= thresholds.pitchDegrees
    }

    public static func summarize(_ samples: [AttentionSample], thresholds: AttentionThresholds = .standard) -> AttentionSummary {
        guard !samples.isEmpty else { return .unavailable }
        let sorted = samples.sorted { $0.time < $1.time }

        var tracked = 0.0
        var engaged = 0.0
        var lookAways = 0
        var longest = 0.0
        var currentRun = 0.0
        var deviationTotal = 0.0
        var lastInterval = 0.1

        func closeRun() {
            if currentRun >= thresholds.minimumLookAwaySeconds {
                lookAways += 1
                longest = max(longest, currentRun)
            }
            currentRun = 0
        }

        for (index, sample) in sorted.enumerated() {
            let interval: Double
            if index + 1 < sorted.count {
                interval = min(max(sorted[index + 1].time - sample.time, 0), thresholds.maximumSampleGap)
                lastInterval = interval
            } else {
                interval = lastInterval
            }
            tracked += interval

            let forward = sample.headForward.normalized
            let toTarget = (sample.target - sample.headPosition).normalized
            deviationTotal += degrees(acos(min(max(forward.dot(toTarget), -1), 1)))

            if isEngaged(sample, thresholds: thresholds) {
                engaged += interval
                closeRun()
            } else {
                currentRun += interval
            }
        }
        closeRun()

        return AttentionSummary(
            sampleCount: sorted.count,
            trackedSeconds: tracked,
            engagedRatio: tracked > 0 ? engaged / tracked : 0,
            lookAwayCount: lookAways,
            longestLookAwaySeconds: longest,
            averageDeviationDegrees: deviationTotal / Double(sorted.count)
        )
    }
}

/// Collects head-pose samples for a whole interview and for labelled segments (each question / answer).
public final class AttentionRecorder {
    public var thresholds: AttentionThresholds
    public private(set) var samples: [AttentionSample] = []
    public private(set) var isRecording = false
    private var segment: [AttentionSample]?

    public init(thresholds: AttentionThresholds = .standard) {
        self.thresholds = thresholds
    }

    public func start() {
        samples = []
        segment = nil
        isRecording = true
    }

    public func record(_ sample: AttentionSample) {
        guard isRecording else { return }
        samples.append(sample)
        segment?.append(sample)
    }

    public func beginSegment() {
        segment = []
    }

    @discardableResult
    public func endSegment() -> AttentionSummary {
        let collected = segment ?? []
        segment = nil
        return AttentionAnalyzer.summarize(collected, thresholds: thresholds)
    }

    @discardableResult
    public func stop() -> AttentionSummary {
        isRecording = false
        segment = nil
        return AttentionAnalyzer.summarize(samples, thresholds: thresholds)
    }

    /// Whether the most recent sample counts as eye contact; drives the optional live indicator.
    public var isCurrentlyEngaged: Bool? {
        samples.last.map { AttentionAnalyzer.isEngaged($0, thresholds: thresholds) }
    }
}
