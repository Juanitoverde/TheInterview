import Foundation

enum Prompts {
    // MARK: Questions

    static let questionSystem = """
    You are an experienced hiring manager conducting a realistic, professional job interview. \
    You write interview questions that will be spoken aloud by a virtual interviewer. Respond only with JSON.
    """

    static func questionUser(for request: QuestionRequest) -> String {
        """
        Write \(request.count) interview questions for a candidate applying for the position of "\(request.position)".

        Candidate level: \(request.difficulty.promptDescription).
        Question mix: \(request.focus.promptDescription).

        Requirements:
        - The first question is a warm opener about the candidate's background or interest in the role.
        - The last question is a forward-looking or closing question.
        - Questions in between must be specific to the day-to-day realities of a \(request.position), not generic.
        - Each question is spoken aloud: conversational, under 40 words, one question at a time (no lists or multi-part questions).
        - Never ask about age, family, religion, health, nationality, or other protected characteristics.
        - Make this set different from a typical list; variety token: \(request.varietyToken.prefix(8)).

        Return JSON exactly in this shape:
        {"questions": [{"text": "question text", "category": "opener|technical|behavioral|situational|motivation|closing", "intent": "what a strong answer demonstrates"}]}
        """
    }

    // MARK: Reactions

    static let reactionSystem = """
    You are a friendly, professional hiring manager in a live interview. Respond only with JSON.
    """

    static func reactionUser(question: InterviewQuestion, answer: String, position: String, allowFollowUp: Bool) -> String {
        let followUpRule = allowFollowUp
            ? """
            Only if the answer was vague, gave no concrete example, or left out how things turned out, write ONE short, \
            natural follow-up question (at most 25 words) that probes for what's missing. Otherwise use null. \
            Most solid answers need no follow-up.
            """
            : "Always null."
        return """
        You are interviewing a candidate for "\(position)". You asked: "\(question.text)"
        The candidate answered (speech-to-text, may contain errors): "\(answer.prefix(1500))"

        "reaction": the brief, natural thing you say right after this answer.
        - At most 15 words, spoken style, neutral to warm.
        - Don't judge the answer's quality and don't give feedback.
        - You may reference one specific detail they mentioned.
        - Don't ask a question in the reaction.

        "followUp": \(followUpRule)

        Return JSON: {"reaction": "...", "followUp": "..." or null}
        """
    }

    static func candidateQuestionUser(question: String, position: String, companyName: String) -> String {
        """
        You are the hiring manager at \(companyName), interviewing a candidate for "\(position)". At the end of the \
        interview you asked whether they had any questions, and they asked (speech-to-text, may contain errors):
        "\(question.prefix(600))"

        Answer in character, the way a real hiring manager would in conversation:
        - 2-3 spoken sentences, at most 60 words, warm and specific.
        - Invent plausible, unremarkable details about the team or company where needed; don't promise anything.
        - For salary or benefits, say HR will cover the package at the next stage.

        Return JSON: {"answer": "..."}
        """
    }

    // MARK: Evaluation

    static let evaluationSystem = """
    You are an expert interview coach and hiring manager. You evaluate mock interview transcripts and give candid, \
    specific, encouraging feedback addressed directly to the candidate ("you"). Answers come from speech recognition \
    and may contain transcription errors; don't penalise obvious recognition mistakes. Respond only with JSON.
    """

    struct EvaluationPayload: Encodable {
        struct Question: Encodable {
            let index: Int
            let category: String
            let question: String
            let whatAStrongAnswerShows: String?
            let answer: String
            let followUpQuestion: String?
            let followUpAnswer: String?
            let answeredBy: String
            let speakingSeconds: Int
            let wordsPerMinute: Int?
            let fillerWords: Int
            let longPauses: Int?
            let eyeContactPercent: Int?
        }

        let position: String
        let candidateLevel: String
        let endedEarly: Bool
        let eyeContactTracked: Bool
        let overallEyeContactPercent: Int?
        let lookAwayCount: Int?
        let averageWordsPerMinute: Int?
        let totalFillerWords: Int
        let interviewerInvitedQuestions: Bool
        let candidateQuestions: [String]
        let questions: [Question]
    }

    static func evaluationUser(record: InterviewRecord, baseline: InterviewReport, maxAnswerCharacters: Int = 4000) -> String {
        let followUpLimit = max(maxAnswerCharacters / 2, 200)
        let payload = EvaluationPayload(
            position: record.position,
            candidateLevel: record.configuration.difficulty.displayName,
            endedEarly: record.endedEarly,
            eyeContactTracked: baseline.eyeContact.isAvailable,
            overallEyeContactPercent: baseline.eyeContact.isAvailable ? baseline.eyeContact.engagedPercent : nil,
            lookAwayCount: baseline.eyeContact.isAvailable ? baseline.eyeContact.lookAwayCount : nil,
            averageWordsPerMinute: baseline.delivery.averageWordsPerMinute,
            totalFillerWords: baseline.delivery.fillerCount,
            interviewerInvitedQuestions: record.candidateQuestionsInvited,
            candidateQuestions: record.candidateQuestions.map { String($0.prefix(300)) },
            questions: record.answers.map { answer in
                let feedback = baseline.questions.first { $0.index == answer.index }
                let metrics = answer.combinedMetrics
                let followUpReply = answer.followUp?.utterance.text ?? ""
                return .init(
                    index: answer.index,
                    category: answer.question.category.rawValue,
                    question: answer.question.text,
                    whatAStrongAnswerShows: answer.question.intent,
                    answer: answer.utterance.text.isEmpty ? "(no answer)" : String(answer.utterance.text.prefix(maxAnswerCharacters)),
                    followUpQuestion: answer.followUp?.question,
                    followUpAnswer: answer.followUp.map { _ in followUpReply.isEmpty ? "(no answer)" : String(followUpReply.prefix(followUpLimit)) },
                    answeredBy: answer.utterance.method == .typed ? "typing" : "speaking",
                    speakingSeconds: Int(metrics.speakingSeconds.rounded()),
                    wordsPerMinute: metrics.wordsPerMinute.map { Int($0.rounded()) },
                    fillerWords: metrics.fillerCount,
                    longPauses: Prosody.combined(answer.utterance.prosody, answer.followUp?.utterance.prosody)?.longPauseCount,
                    eyeContactPercent: feedback?.eyeContactPercent
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = (try? encoder.encode(payload)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        return """
        Evaluate this mock interview. Eye contact was estimated from head orientation toward the interviewer.

        \(json)

        Scoring rubric for each question (0-10), judging the answer together with any follow-up answer:
        - 0: no answer. 1-3: off-topic, very vague, or no real substance. 4-5: relevant but generic, little evidence.
        - 6-7: solid and relevant with a concrete example. 8-9: specific, well structured, clear personal contribution and a measurable result.
        - 10: exceptional; would stand out among strong candidates. Most good answers are 6-8; reserve 9-10.
        - relevance: does it answer what was asked? clarity: easy to follow, concise, confident? structure: logical order; STAR for behavioral questions.
        - For technical questions, judge whether the content would be credible to an experienced practitioner of this role.
        - Penalise speaking negatively about past employers, claiming only team credit ("we") without the candidate's own part, and rambling.
        - exampleAnswer shows how a strong candidate might answer that question, in first person, 2-4 spoken sentences. Build on the candidate's own experience and details where possible; for unanswered questions, write a plausible example for this role.
        - Reward specific examples, measurable results and clear structure (STAR for behavioral questions). Penalise vague, off-topic or rambling answers.
        - contentScore is 0-100 for the quality of the answers only. Don't factor in delivery or eye contact; those are measured separately.
        - If the interviewer invited questions, comment in strengths or improvements on the candidate's questions (or the lack of them).
        - Feedback must quote or reference what the candidate actually said. Suggestions must be concrete and actionable.
        - If eyeContactTracked is false, return an empty string for eyeContactFeedback.

        Return JSON exactly in this shape:
        {
          "contentScore": 0,
          "summary": "2-3 sentences addressed to the candidate",
          "strengths": ["2-4 short items"],
          "improvements": ["2-4 short, actionable items"],
          "eyeContactFeedback": "1-2 sentences, or empty",
          "deliveryFeedback": "1-2 sentences on pace, filler words and conciseness",
          "questions": [{"index": 0, "score": 0, "relevance": 0, "clarity": 0, "structure": 0, "feedback": "1-2 sentences", "suggestion": "1 sentence", "exampleAnswer": "2-4 sentences"}]
        }
        """
    }
}
