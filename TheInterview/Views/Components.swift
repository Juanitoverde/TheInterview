import SwiftUI

enum Theme {
    /// Single accent hue for scores and meters (blue 400 of the reference sequential ramp).
    static let accent = Color(red: 0x39 / 255, green: 0x87 / 255, blue: 0xE5 / 255)
    /// Unfilled meter track: the same hue, much lighter, so the whole bar reads as one scale.
    static let track = accent.opacity(0.22)
}

/// The overall score: the report's one hero figure, inside a ring meter.
struct ScoreRing: View {
    let score: Int
    var maximum = 100
    var lineWidth: CGFloat = 14

    private var fraction: Double {
        maximum > 0 ? min(max(Double(score) / Double(maximum), 0), 1) : 0
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(score)")
                    .font(.system(size: 56, weight: .semibold))
                Text("out of \(maximum)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(lineWidth / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Overall score \(score) out of \(maximum)")
    }
}

/// A labelled headline number with an optional supporting detail.
struct StatTile: View {
    let label: String
    let value: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.regularMaterial, in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }
}

/// A horizontal meter for a score out of `maximum`.
struct ScoreMeter: View {
    let value: Int
    let maximum: Int

    var body: some View {
        GeometryReader { geometry in
            let fraction = maximum > 0 ? min(max(CGFloat(value) / CGFloat(maximum), 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: max(geometry.size.width * fraction, fraction > 0 ? 8 : 0))
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel("\(value) out of \(maximum)")
    }
}

/// Animated bars showing microphone input level.
struct MicLevelView: View {
    let level: Float
    private let weights: [CGFloat] = [0.45, 0.8, 1, 0.7, 0.4]

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(weights.indices, id: \.self) { index in
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: 5, height: 6 + CGFloat(level) * weights[index] * 28)
            }
        }
        .frame(width: 42, height: 36)
        .animation(.linear(duration: 0.08), value: level)
        .accessibilityHidden(true)
    }
}

/// Plain-English duration such as "3 min 20 s".
func formattedDuration(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    let minutes = total / 60
    let remainder = total % 60
    if minutes == 0 { return "\(remainder) s" }
    return remainder == 0 ? "\(minutes) min" : "\(minutes) min \(remainder) s"
}
