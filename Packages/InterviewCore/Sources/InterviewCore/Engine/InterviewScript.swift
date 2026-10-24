import Foundation

/// The spoken lines of the receptionist and interviewer, with a little variety so sessions don't feel canned.
public struct InterviewScript {
    public let candidate: CandidateProfile
    public let configuration: InterviewConfiguration
    private var generator: SeededGenerator
    private var usedReactions: Set<String> = []

    public init(candidate: CandidateProfile, configuration: InterviewConfiguration, seed: UInt64) {
        self.candidate = candidate
        self.configuration = configuration
        generator = SeededGenerator(seed: seed)
    }

    private var name: String? { candidate.addressedName }

    /// ", Ms. Rivera" or "" so lines read naturally with or without a name.
    private var commaName: String { name.map { ", \($0)" } ?? "" }

    private mutating func pick(_ options: [String]) -> String {
        options.randomElement(using: &generator) ?? options[0]
    }

    // MARK: Reception

    public func receptionGreeting(at date: Date, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let greeting = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        return "\(greeting), and welcome to \(configuration.companyName)!"
    }

    public func askPosition() -> String {
        "What position are you applying for today\(commaName)?"
    }

    public mutating func askPositionAgain() -> String {
        pick([
            "Sorry, I didn't quite catch that. Which position are you here to interview for?",
            "I'm sorry, could you tell me the job title once more?",
        ])
    }

    public func confirmAppointment(position: String) -> String {
        "Oh, I see your appointment right here: \(position), with \(configuration.interviewerName). Follow me this way."
    }

    public func positionFallback(position: String) -> String {
        "No problem. I have you down for the \(position) interview with \(configuration.interviewerName). Follow me this way."
    }

    public mutating func walkingSmallTalk() -> String {
        pick([
            "The team has been looking forward to meeting you.",
            "It's a busy day around here, but \(configuration.interviewerFirstName) has set aside time just for you.",
            "Did you find us all right? Parking can be tricky around here.",
        ])
    }

    public func arrival(position: String) -> String {
        "Here we are. \(configuration.interviewerFirstName), your \(position) candidate is here. Please, have a seat. Good luck!"
    }

    // MARK: Interview room

    public func interviewerIntro(position: String) -> String {
        "Hello\(commaName). I'm \(configuration.interviewerName), the hiring manager for the \(position) role. "
            + "Thank you for coming in today. Please, make yourself comfortable."
    }

    public func askReady() -> String {
        "Are you ready to begin\(commaName)?"
    }

    public mutating func askReadyAgain() -> String {
        pick(["Sorry, I didn't catch that. Shall we begin?", "Are you ready for the first question?"])
    }

    public func notReadyResponse() -> String {
        "Of course, take your time. Just let me know when you're ready."
    }

    public func proceedAnyway() -> String {
        "Let's go ahead and get started, then."
    }

    public func preparingQuestions() -> String {
        "Just give me a moment to pull up my notes."
    }

    public func startLine(questionCount: Int) -> String {
        "Great. I have \(questionCount) questions for you today. Take your time with each one, and when you've finished an answer, just tell me \"that's my answer\"."
    }

    public mutating func transition(index: Int, total: Int) -> String {
        if index == 0 { return "First question." }
        if index == total - 1 { return "And my last question." }
        return pick(["Next question.", "All right, moving on.", "Okay, let's talk about something else.", "Thank you. Next one."])
    }

    public func repeatPreface() -> String {
        "Of course. "
    }

    public func emptyAnswerReaction() -> String {
        "That's all right, let's move on."
    }

    public mutating func cannedReaction() -> String {
        let options = [
            "Thank you, I appreciate that.",
            "Okay, thanks for sharing that.",
            "Got it, that's helpful context.",
            "Interesting. Thank you.",
            "Thanks, that gives me a good picture.",
            "I see. Thank you for walking me through that.",
        ]
        let fresh = options.filter { !usedReactions.contains($0) }
        let line = pick(fresh.isEmpty ? options : fresh)
        usedReactions.insert(line)
        return line
    }

    public mutating func followUpQuestion(for reason: FollowUpReason) -> String {
        switch reason {
        case .tooBrief:
            pick(["Could you tell me a bit more about that?", "Can you expand on that a little?"])
        case .needsExample:
            pick(["Can you give me a specific example from your experience?", "Could you walk me through a time you actually did that?"])
        case .needsOutcome:
            pick(["And what was the outcome?", "How did that turn out in the end?"])
        }
    }

    public mutating func followUpThanks() -> String {
        pick(["Thank you, that helps.", "Great, thanks for adding that.", "Okay, thank you."])
    }

    public func inviteQuestions() -> String {
        "Before we wrap up, do you have any questions for me?"
    }

    public mutating func anythingElse() -> String {
        pick(["Is there anything else you'd like to ask?", "Anything else I can tell you?"])
    }

    public func noQuestionsResponse() -> String {
        "No problem at all."
    }

    /// An answer to the candidate's question when no AI is available, matched on its topic.
    public func answer(toCandidateQuestion question: String) -> String {
        let text = TextTools.normalizeApostrophes(question).lowercased()
        func mentions(_ keywords: [String]) -> Bool { keywords.contains { text.contains($0) } }
        let company = configuration.companyName
        if mentions(["next step", "hear back", "timeline", "process", "decision", "when will"]) {
            return "Good question. We're meeting a few candidates this week, and we aim to get back to everyone with next steps within about a week."
        }
        if mentions(["salary", "pay", "benefit", "compensation", "bonus", "holiday", "vacation"]) {
            return "Our HR team will take you through the full package at the next stage, but we aim to be competitive for this role."
        }
        if mentions(["remote", "hybrid", "hours", "schedule", "shift", "flexib", "work from home"]) {
            return "We keep a fairly standard schedule, with some flexibility depending on what the team needs that week. We can go through the details at the next stage."
        }
        if mentions(["training", "learn", "develop", "grow", "career", "progress", "promot", "mentor"]) {
            return "We take development seriously here. There's a structured onboarding period, and everyone has regular check-ins about their goals and a training budget."
        }
        if mentions(["team", "colleague", "work with", "report to", "manager"]) {
            return "You'd be joining a team of about eight people and reporting to me. They're a supportive group, and new starters are paired with an experienced colleague for the first few weeks."
        }
        if mentions(["typical day", "day to day", "day-to-day", "responsib", "look like", "involve"]) {
            return "Day to day, it's a mix of hands-on work and collaborating with the wider team. No two weeks are quite the same, which most people here enjoy."
        }
        if mentions(["success", "expect", "first 90", "first ninety", "first few months", "first year", "goal", "measure"]) {
            return "In the first few months, success means learning how we work, building relationships across the team, and starting to own some work independently."
        }
        if mentions(["culture", "environment", "like working", "enjoy", "values", "atmosphere"]) {
            return "People at \(company) are friendly and direct. We care about doing quality work and about helping each other out."
        }
        if mentions(["challenge", "difficult", "hardest"]) {
            return "Honestly, the pace. We're busy, so it suits someone who stays organised and communicates early when things change."
        }
        return "That's a good question. I'd say the best thing about this role is the variety and the people you'd be working with. We can go into more detail at the next stage."
    }

    public func closing() -> String {
        "That's all the questions I have for today. Thank you for your time\(commaName). We'll be in touch soon."
    }

    public func closingAfterQuestions() -> String {
        "Thank you for your time today\(commaName). It was good to meet you, and we'll be in touch soon."
    }

    public func endedEarlyClosing() -> String {
        "Understood, let's stop here. Thank you for your time today\(commaName)."
    }
}
