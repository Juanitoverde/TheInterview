import Foundation

/// Scores an interview entirely on-device from the transcript, speech metrics and head-pose attention.
///
/// It is used when no OpenAI key is configured or the request fails, and it always supplies the
/// measured numbers (pace, filler words, eye contact) that the AI evaluation is layered on top of.
public struct HeuristicEvaluator: InterviewEvaluating {
    public init() {}

    public func evaluate(_ record: InterviewRecord) async throws -> InterviewReport {
        makeReport(for: record)
    }

    public func makeReport(for record: InterviewRecord, notes: [String] = []) -> InterviewReport {
        let feedback = record.answers.map { self.feedback(for: $0, position: record.position) }
        let eyeContact = eyeContactReport(for: record)
        let delivery = deliveryReport(for: record)

        let asked = max(record.answers.count, 1)
        let contentAverage = Double(feedback.reduce(0) { $0 + $1.score }) / Double(asked)
        var overall = contentAverage * 10
        if eyeContact.isAvailable {
            overall = overall * 0.85 + Double(eyeContact.score) * 0.15
        }
        let overallScore = clamp(Int(overall.rounded()), 0, 100)

        let strengths = overallStrengths(feedback: feedback, record: record, eyeContact: eyeContact)
        let improvements = overallImprovements(feedback: feedback, record: record, eyeContact: eyeContact)
        let answered = feedback.filter { !$0.fullAnswer.isEmpty }.count

        var summary = "You answered \(answered) of \(record.answers.count) question\(record.answers.count == 1 ? "" : "s") "
        summary += "for the \(record.position) interview and scored \(overallScore)/100."
        if let strength = strengths.first { summary += " Highlight: \(strength)" }
        if let improvement = improvements.first { summary += " Focus next on: \(improvement)" }

        return InterviewReport(
            createdAt: record.endedAt,
            candidateName: record.candidate.fullName,
            position: record.position,
            difficulty: record.configuration.difficulty,
            durationSeconds: record.endedAt.timeIntervalSince(record.startedAt),
            overallScore: overallScore,
            summary: summary,
            strengths: strengths,
            improvements: improvements,
            eyeContact: eyeContact,
            delivery: delivery,
            questions: feedback,
            analysisSource: .onDevice,
            notes: notes,
            endedEarly: record.endedEarly
        )
    }

    // MARK: Per question

    func feedback(for answer: AnswerRecord, position: String) -> QuestionFeedback {
        // A follow-up reply counts toward the answer, as it would in a real interview.
        let text = answer.combinedText
        let metrics = answer.combinedMetrics
        let attention = answer.combinedAttention
        let followUpQuestion = answer.followUp?.question
        let followUpAnswer = answer.followUp.map { $0.utterance.text.trimmed }
        let eyePercent = attention.isAvailable ? Int((attention.engagedRatio * 100).rounded()) : nil

        guard !text.isEmpty else {
            return QuestionFeedback(
                index: answer.index,
                question: answer.question.text,
                category: answer.question.category,
                answer: "",
                inputMethod: answer.utterance.method,
                score: 0, relevance: 0, clarity: 0, structure: 0,
                feedback: "No answer was captured for this question.",
                suggestion: "Even when you're unsure, talk through how you would approach it. Interviewers value seeing how you think.",
                metrics: metrics,
                eyeContactPercent: eyePercent,
                followUpQuestion: followUpQuestion,
                followUpAnswer: followUpAnswer
            )
        }

        let category = answer.question.category
        let storyDriven = category == .behavioral || category == .situational
        let questionWords = TextTools.contentWords(in: answer.question.text).union(TextTools.contentWords(in: position))
        let overlap = questionWords.intersection(TextTools.contentWords(in: text)).count
        let star = Self.starComponents(in: text)
        let specific = Self.isSpecific(text)

        var relevance = 5.0 + Double(min(3, overlap))
        if metrics.wordCount < 12 { relevance -= 2 }
        if category == .behavioral { relevance += star >= 3 ? 2 : star >= 2 ? 1 : 0 }
        if specific { relevance += 1 }

        var clarity = 9.0
        if metrics.fillerRatio > 0.08 { clarity -= 3 } else if metrics.fillerRatio > 0.04 { clarity -= 2 } else if metrics.fillerRatio > 0.02 { clarity -= 1 }
        if let wpm = metrics.wordsPerMinute {
            if wpm < 95 || wpm > 185 { clarity -= 2 } else if !SpeechAnalyzer.idealWordsPerMinute.contains(wpm) { clarity -= 1 }
        }
        if metrics.averageSentenceLength > 40 { clarity -= 1 }
        if metrics.hedgeCount >= 3 { clarity -= 1 }

        var structure: Double = switch metrics.wordCount {
        case ..<15: 2
        case ..<35: 4
        case ..<70: 6
        case ...260: 8
        case ...380: 7
        default: 5
        }
        if storyDriven { structure += star >= 3 ? 2 : star >= 2 ? 1 : 0 }
        if specific { structure += 1 }

        let r = clamp(Int(relevance.rounded()), 0, 10)
        let c = clamp(Int(clarity.rounded()), 1, 10)
        let s = clamp(Int(structure.rounded()), 0, 10)
        let score = clamp(Int((0.4 * Double(r) + 0.3 * Double(c) + 0.3 * Double(s)).rounded()), 0, 10)

        var positives: [String] = []
        if storyDriven && star >= 3 { positives.append("You told a clear story with a situation, the actions you took and the result.") }
        if specific { positives.append("You backed your answer with specific details.") }
        if overlap >= 2 { positives.append("You stayed focused on what was asked.") }
        if c >= 8 { positives.append("Your delivery was clear and easy to follow.") }

        var issues: [(problem: String, fix: String)] = []
        if metrics.wordCount < 35 {
            issues.append(("This answer was quite brief.", "Expand with a concrete example: what you did, how you did it, and what happened as a result."))
        }
        if metrics.wordCount > 380 {
            issues.append(("This answer ran long.", "Aim for one to two minutes: lead with your main point, give one example, then wrap up."))
        }
        if category == .behavioral && star < 2 {
            issues.append(("It lacked a concrete example from your experience.", "Use the STAR method: describe the Situation, your Task, the Actions you took and the Result."))
        }
        if metrics.fillerRatio > 0.04 {
            let top = Self.topFillers(metrics.fillerWords, limit: 2).map { "\"\($0)\"" }.joined(separator: " and ")
            issues.append(("Filler words (\(top)) crept in.", "Pause silently instead of using filler words. A short pause sounds more confident."))
        }
        if let wpm = metrics.wordsPerMinute, wpm > 175 {
            issues.append(("You spoke quickly (about \(Int(wpm)) words per minute).", "Slow down slightly and pause between key points so each one lands."))
        }
        if let wpm = metrics.wordsPerMinute, wpm < 100 {
            issues.append(("Your pace was slow (about \(Int(wpm)) words per minute).", "Keep a steady pace. Pausing to think is fine, but try to keep sentences moving."))
        }
        if overlap == 0 && metrics.wordCount >= 15 && !storyDriven {
            issues.append(("The answer drifted from the question.", "Echo the key words of the question in your first sentence to anchor your answer."))
        }
        if metrics.hedgeCount >= 3 {
            issues.append(("Frequent hedging (\"I think\", \"maybe\") undercut your confidence.", "Replace hedges with direct statements about what you did and what you know."))
        }
        if !specific && metrics.wordCount >= 35 {
            issues.append(("Adding specifics would make it more memorable.", "Quantify your impact where you can: time saved, problems fixed, people helped."))
        }

        var feedbackText = positives.first ?? "You gave a reasonable answer."
        if let issue = issues.first { feedbackText += " " + issue.problem }
        let suggestion = issues.first?.fix ?? "This structure works. Finish with a one-line summary of the impact to make it stick."

        return QuestionFeedback(
            index: answer.index,
            question: answer.question.text,
            category: category,
            answer: answer.utterance.text.trimmed,
            inputMethod: answer.utterance.method,
            score: score,
            relevance: r,
            clarity: c,
            structure: s,
            feedback: feedbackText,
            suggestion: suggestion,
            metrics: metrics,
            eyeContactPercent: eyePercent,
            followUpQuestion: followUpQuestion,
            followUpAnswer: followUpAnswer
        )
    }

    // MARK: Eye contact

    func eyeContactReport(for record: InterviewRecord) -> EyeContactReport {
        let overall = record.overallAttention
        guard overall.isAvailable else {
            return EyeContactReport(
                isAvailable: false, score: 0, engagedPercent: 0, lookAwayCount: 0, longestLookAwaySeconds: 0,
                feedback: "Eye-contact tracking wasn't available for this session. It needs Apple Vision Pro with the immersive office open."
            )
        }
        let percent = clamp(Int((overall.engagedRatio * 100).rounded()), 0, 100)
        let score = clamp(percent + 10 - 3 * max(0, overall.lookAwayCount - 3), 0, 100)

        var feedback: String
        switch percent {
        case 80...:
            feedback = "Excellent eye contact: you stayed focused on the interviewer \(percent)% of the time."
        case 60..<80:
            feedback = "Good eye contact overall (\(percent)% of the time), with a few moments of looking away."
        default:
            feedback = "Your eyes were wandering: you faced the interviewer only \(percent)% of the time. Keep your gaze on the interviewer to project confidence."
        }

        var byCategory: [QuestionCategory: (engaged: Double, tracked: Double)] = [:]
        for answer in record.answers {
            let attention = answer.combinedAttention
            guard attention.isAvailable else { continue }
            let entry = byCategory[answer.question.category] ?? (0, 0)
            byCategory[answer.question.category] = (entry.engaged + attention.engagedRatio * attention.trackedSeconds, entry.tracked + attention.trackedSeconds)
        }
        let ratios = byCategory.compactMapValues { $0.tracked > 0 ? $0.engaged / $0.tracked : nil }
        if ratios.count >= 2, let worst = ratios.min(by: { $0.value < $1.value }), worst.value < 0.6 {
            feedback += " Your attention drifted most during the \(worst.key.feedbackPhrase). Try to maintain eye contact there to show confidence."
        }
        if overall.longestLookAwaySeconds >= 4 {
            feedback += " Your longest look-away lasted about \(Int(overall.longestLookAwaySeconds.rounded())) seconds."
        }

        return EyeContactReport(
            isAvailable: true,
            score: score,
            engagedPercent: percent,
            lookAwayCount: overall.lookAwayCount,
            longestLookAwaySeconds: overall.longestLookAwaySeconds,
            feedback: feedback
        )
    }

    // MARK: Delivery

    func deliveryReport(for record: InterviewRecord) -> DeliveryReport {
        let voiced = record.answers.filter { $0.utterance.method == .voice && $0.combinedMetrics.wordCount > 0 }
        let paced = voiced.filter { $0.combinedMetrics.wordsPerMinute != nil }
        let pacedWords = paced.reduce(0) { $0 + $1.combinedMetrics.wordCount }
        let pacedSeconds = paced.reduce(0) { $0 + $1.combinedMetrics.speakingSeconds }
        let averageWPM = pacedSeconds > 0 ? Int((Double(pacedWords) / (pacedSeconds / 60)).rounded()) : nil

        var fillers: [String: Int] = [:]
        for answer in record.answers {
            for (word, count) in answer.combinedMetrics.fillerWords { fillers[word, default: 0] += count }
        }
        let fillerCount = fillers.values.reduce(0, +)
        let totalWords = record.answers.reduce(0) { $0 + $1.combinedMetrics.wordCount }
        let ratio = totalWords > 0 ? Double(fillerCount) / Double(totalWords) : 0

        var sentences: [String] = []
        if let wpm = averageWPM {
            switch wpm {
            case ..<100: sentences.append("Your pace was on the slow side (about \(wpm) words per minute); aim for 120–160.")
            case 100...175: sentences.append("Your speaking pace was comfortable (about \(wpm) words per minute).")
            default: sentences.append("You spoke quickly (about \(wpm) words per minute); slowing to 120–160 will help your points land.")
            }
        }
        if fillerCount == 0 {
            sentences.append("No filler words were detected.")
        } else if ratio > 0.04 {
            let top = Self.topFillers(fillers, limit: 3).map { "\"\($0)\"" }.joined(separator: ", ")
            sentences.append("Filler words came up \(fillerCount) times (mostly \(top)). Avoid them and focus on clear, concise answers.")
        } else {
            sentences.append("Filler words were rare (\(fillerCount) in total).")
        }
        let answeredCount = max(record.answers.filter { $0.combinedMetrics.wordCount > 0 }.count, 1)
        let averageLength = totalWords / answeredCount
        if averageLength > 0 && averageLength < 40 {
            sentences.append("Your answers averaged \(averageLength) words, which is brief; fuller answers give the interviewer more to go on.")
        } else if averageLength > 300 {
            sentences.append("Your answers averaged \(averageLength) words; tightening them would make them easier to follow.")
        }

        return DeliveryReport(
            totalSpeakingSeconds: voiced.reduce(0) { $0 + $1.combinedMetrics.speakingSeconds },
            totalWords: totalWords,
            averageWordsPerMinute: averageWPM,
            fillerCount: fillerCount,
            topFillers: Self.topFillers(fillers, limit: 3),
            feedback: sentences.isEmpty ? "No spoken answers were captured." : sentences.joined(separator: " ")
        )
    }

    // MARK: Overall

    func overallStrengths(feedback: [QuestionFeedback], record: InterviewRecord, eyeContact: EyeContactReport) -> [String] {
        let answered = feedback.filter { !$0.fullAnswer.isEmpty }
        guard !answered.isEmpty else { return [] }
        var strengths: [String] = []
        if eyeContact.isAvailable && eyeContact.engagedPercent >= 75 {
            strengths.append("Confident, steady eye contact with the interviewer.")
        }
        let specificCount = answered.filter { Self.isSpecific($0.fullAnswer) }.count
        if specificCount * 2 >= answered.count {
            strengths.append("Concrete, specific examples that make your answers credible.")
        }
        let totalWords = answered.reduce(0) { $0 + $1.metrics.wordCount }
        let fillers = answered.reduce(0) { $0 + $1.metrics.fillerCount }
        if totalWords >= 60 && Double(fillers) / Double(totalWords) < 0.02 {
            strengths.append("Clean delivery with very few filler words.")
        }
        let averageRelevance = Double(answered.reduce(0) { $0 + $1.relevance }) / Double(answered.count)
        if averageRelevance >= 7 {
            strengths.append("Answers that stayed on topic and addressed the question.")
        }
        if answered.count == feedback.count && feedback.count == record.plannedQuestionCount {
            strengths.append("You answered every question.")
        }
        if strengths.isEmpty {
            strengths.append("You completed a practice interview, which is the most important step.")
        }
        return Array(strengths.prefix(4))
    }

    func overallImprovements(feedback: [QuestionFeedback], record: InterviewRecord, eyeContact: EyeContactReport) -> [String] {
        var improvements: [String] = []
        let answered = feedback.filter { !$0.fullAnswer.isEmpty }
        if eyeContact.isAvailable && eyeContact.engagedPercent < 60 {
            improvements.append("Maintain eye contact with the interviewer, especially while answering.")
        }
        if answered.count < feedback.count {
            improvements.append("Attempt every question, even briefly; silence leaves the interviewer guessing.")
        }
        if !answered.isEmpty {
            let averageWords = answered.reduce(0) { $0 + $1.metrics.wordCount } / answered.count
            if averageWords < 40 {
                improvements.append("Give fuller answers with a specific example for each question.")
            } else if averageWords > 300 {
                improvements.append("Be more concise: lead with your main point and support it with one example.")
            }
            let totalWords = answered.reduce(0) { $0 + $1.metrics.wordCount }
            let fillers = answered.reduce(0) { $0 + $1.metrics.fillerCount }
            if totalWords > 0 && Double(fillers) / Double(totalWords) > 0.04 {
                improvements.append("Cut down on filler words; pause instead.")
            }
            let behavioral = answered.filter { $0.category == .behavioral }
            if !behavioral.isEmpty && behavioral.filter({ Self.starComponents(in: $0.fullAnswer) >= 2 }).count * 2 < behavioral.count {
                improvements.append("Use the STAR method (Situation, Task, Action, Result) for behavioral questions.")
            }
            let speeds = answered.compactMap(\.metrics.wordsPerMinute)
            if !speeds.isEmpty {
                let average = speeds.reduce(0, +) / Double(speeds.count)
                if average > 175 { improvements.append("Slow your pace a little so key points land.") }
                if average < 100 { improvements.append("Keep a steadier pace; plan your first sentence before you start.") }
            }
            if !answered.contains(where: { Self.isSpecific($0.fullAnswer) }) {
                improvements.append("Quantify your impact with numbers, results or concrete details.")
            }
        }
        if improvements.isEmpty {
            improvements.append("Keep stretching yourself: try a harder difficulty or a different question focus next time.")
        }
        return Array(improvements.prefix(4))
    }

    // MARK: Helpers

    static let starMarkers: [[String]] = [
        // Situation
        ["when i", "at my", "in my previous", "in my last", "there was", "we had", "one time", "last year", "years ago",
         "project", "while i was", "in my role", "at the time", "a customer", "a client"],
        // Task
        ["my goal", "i needed to", "i had to", "my responsibility", "i was responsible", "the task", "the challenge",
         "we needed to", "assigned", "the problem was", "the issue was", "my job was"],
        // Action
        ["i decided", "i started", "i created", "i built", "i fixed", "i led", "i organized", "i spoke", "i talked",
         "i worked", "i implemented", "i reached out", "i set up", "i trained", "i made", "i took", "i developed",
         "i designed", "i analyzed", "i diagnosed", "i replaced", "i repaired", "i proposed", "i suggested", "i asked",
         "i checked", "i tested", "i communicated", "so i", "i would"],
        // Result
        ["as a result", "result", "outcome", "in the end", "ended up", "which led", "improved", "reduced", "increased",
         "saved", "learned", "achieved", "resolved", "successfully", "percent", "%", "on time", "under budget"],
    ]

    static func starComponents(in text: String) -> Int {
        let lowered = " " + TextTools.normalizeApostrophes(text).lowercased() + " "
        return starMarkers.filter { markers in markers.contains { lowered.contains($0) } }.count
    }

    static func mentionsOutcome(_ text: String) -> Bool {
        let lowered = " " + TextTools.normalizeApostrophes(text).lowercased() + " "
        return starMarkers[3].contains { lowered.contains($0) }
    }

    static func isSpecific(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return TextTools.containsDigits(text)
            || ["for example", "for instance", "specifically", "such as", "percent"].contains { lowered.contains($0) }
    }

    static func topFillers(_ fillers: [String: Int], limit: Int) -> [String] {
        fillers.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(limit).map(\.key)
    }
}

func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
    min(max(value, lower), upper)
}
