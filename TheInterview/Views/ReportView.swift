import SwiftUI
import InterviewCore

struct ReportView: View {
    @Environment(AppModel.self) private var model
    let report: InterviewReport

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    statTiles
                    HStack(alignment: .top, spacing: 20) {
                        ListCard(title: "Strengths", systemImage: "hand.thumbsup", items: report.strengths)
                        ListCard(title: "Focus next on", systemImage: "target", items: report.improvements)
                    }
                    FeedbackCard(title: "Eye contact", systemImage: "eye", text: report.eyeContact.feedback)
                    FeedbackCard(title: "Delivery", systemImage: "waveform", text: report.delivery.feedback)

                    Text("Question by question")
                        .font(.title2.bold())
                        .padding(.top, 8)
                    ForEach(report.questions) { question in
                        QuestionCard(feedback: question)
                    }

                    footer
                }
                .padding(32)
            }
            .navigationTitle("Interview feedback")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        model.goHome()
                    } label: {
                        Label("Home", systemImage: "chevron.left")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: report.plainText, subject: Text("Interview feedback: \(report.position)")) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 32) {
            ScoreRing(score: report.overallScore)
                .frame(width: 170, height: 170)
            VStack(alignment: .leading, spacing: 8) {
                Text(report.rating)
                    .font(.title.bold())
                Text("\(report.position) · \(report.difficulty.displayName) · \(report.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(report.summary)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
    }

    private var statTiles: some View {
        let eye = report.eyeContact
        let delivery = report.delivery
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
            StatTile(
                label: "Eye contact",
                value: eye.isAvailable ? "\(eye.engagedPercent)%" : "–",
                detail: eye.isAvailable ? "\(eye.lookAwayCount) look-away\(eye.lookAwayCount == 1 ? "" : "s")" : "Not tracked"
            )
            StatTile(
                label: "Speaking pace",
                value: delivery.averageWordsPerMinute.map { "\($0) wpm" } ?? "–",
                detail: "Comfortable: 120–160 wpm"
            )
            StatTile(
                label: "Filler words",
                value: "\(delivery.fillerCount)",
                detail: delivery.topFillers.isEmpty ? "None detected" : "Mostly " + delivery.topFillers.map { "“\($0)”" }.joined(separator: ", ")
            )
            StatTile(
                label: "Speaking time",
                value: formattedDuration(delivery.totalSpeakingSeconds),
                detail: "\(delivery.totalWords) words"
            )
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                report.analysisSource == .openAI ? "Feedback written by OpenAI (\(report.analysisModel ?? "model"))." : "Scored on device.",
                systemImage: report.analysisSource == .openAI ? "sparkles" : "cpu"
            )
            if report.endedEarly {
                Label("You ended this interview early.", systemImage: "flag.checkered")
            }
            ForEach(report.notes, id: \.self) { note in
                Label(note, systemImage: "info.circle")
            }
            Button {
                model.goHome()
            } label: {
                Label("Practise again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

private struct ListCard: View {
    let title: String
    let systemImage: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•")
                    Text(item)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.callout)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
    }
}

private struct FeedbackCard: View {
    let title: String
    let systemImage: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
    }
}

private struct QuestionCard: View {
    let feedback: QuestionFeedback
    @State private var showsAnswer = false
    @State private var showsExample = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Q\(feedback.index + 1) · \(feedback.category.displayName)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(feedback.score)")
                    .font(.title2.weight(.semibold))
                Text("/10")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(feedback.question)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            ScoreMeter(value: feedback.score, maximum: 10)
                .accessibilityHidden(true)

            DisclosureGroup("Your answer", isExpanded: $showsAnswer) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(feedback.answer.isEmpty ? "No answer was captured." : feedback.answer)
                        .foregroundStyle(.secondary)
                    if let followUp = feedback.followUpQuestion {
                        Text("Follow-up: \(followUp)")
                            .font(.subheadline.weight(.semibold))
                        Text(feedback.followUpAnswer?.isEmpty == false ? feedback.followUpAnswer ?? "" : "No answer was captured.")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            }
            if feedback.followUpQuestion != nil && !showsAnswer {
                Label("The interviewer asked a follow-up", systemImage: "arrow.turn.down.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(feedback.feedback)
                .fixedSize(horizontal: false, vertical: true)
            if !feedback.suggestion.isEmpty {
                Label {
                    Text(feedback.suggestion)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lightbulb")
                }
            }

            if let example = feedback.exampleAnswer {
                DisclosureGroup("A stronger answer might sound like", isExpanded: $showsExample) {
                    Text(example)
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 24) {
                SubScore(label: "Relevance", value: feedback.relevance)
                SubScore(label: "Clarity", value: feedback.clarity)
                SubScore(label: "Structure", value: feedback.structure)
                Spacer()
                Text(metricsSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(22)
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
    }

    private var metricsSummary: String {
        var parts: [String] = []
        let metrics = feedback.metrics
        if metrics.wordCount > 0 { parts.append("\(metrics.wordCount) words") }
        if let wpm = metrics.wordsPerMinute { parts.append("\(Int(wpm.rounded())) wpm") }
        if metrics.fillerCount > 0 { parts.append("\(metrics.fillerCount) filler\(metrics.fillerCount == 1 ? "" : "s")") }
        if let eye = feedback.eyeContactPercent { parts.append("\(eye)% eye contact") }
        if feedback.inputMethod == .typed { parts.append("typed") }
        return parts.joined(separator: " · ")
    }
}

private struct SubScore: View {
    let label: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)/10")
                .font(.subheadline.weight(.semibold))
        }
    }
}
