import Foundation

/// Built-in questions used when no OpenAI key is configured, the network is unavailable, or the AI
/// returns too few questions. `{position}` is replaced with the role the candidate named.
public struct QuestionBank: Sendable {
    struct Template: Sendable {
        let text: String
        let intent: String
        let difficulties: Set<Difficulty>

        init(_ text: String, _ intent: String, _ difficulties: Set<Difficulty> = Set(Difficulty.allCases)) {
            self.text = text
            self.intent = intent
            self.difficulties = difficulties
        }
    }

    static let templates: [QuestionCategory: [Template]] = [
        .opener: [
            Template("To start, could you tell me a little about yourself and what brings you to the {position} role?", "A concise, relevant summary of background that connects to the role."),
            Template("What interested you in this {position} position?", "Genuine motivation and understanding of the role."),
            Template("Walk me through your background and how it has prepared you to work as a {position}.", "A clear narrative linking experience to the job's needs."),
        ],
        .technical: [
            Template("What tools, equipment or technologies do you consider essential for a {position}, and how have you used them?", "Hands-on familiarity with the core tools of the job."),
            Template("Describe the most technically challenging problem you've solved in work related to being a {position}.", "Depth of skill and a methodical approach to hard problems."),
            Template("How do you approach troubleshooting when something isn't working and the cause isn't obvious?", "A systematic diagnostic process rather than guesswork."),
            Template("How do you keep your skills current as a {position}?", "Ongoing learning habits and awareness of the field."),
            Template("What does high-quality work look like in the {position} role, and how do you make sure you deliver it?", "Clear quality standards and concrete checking habits."),
            Template("How would you approach your first thirty days as a {position} here?", "Initiative, learning plan and realistic priorities."),
            Template("Which safety or compliance practices matter most in {position} work, and how do you apply them day to day?", "Awareness of standards and responsible habits."),
            Template("Tell me about a time you had to make a technical trade-off. How did you decide?", "Judgment, weighing options and explaining reasoning.", [.intermediate, .senior]),
            Template("How have you improved a process or system in your past work?", "Ownership and measurable improvement.", [.intermediate, .senior]),
        ],
        .behavioral: [
            Template("Tell me about a time you made a mistake at work. How did you handle it?", "Accountability, learning and corrective action."),
            Template("Describe a situation where you had to work with a difficult colleague or customer.", "Professionalism, empathy and conflict resolution."),
            Template("Tell me about a time you had to meet a tight deadline.", "Prioritisation, focus and communication under pressure."),
            Template("Give me an example of when you took initiative beyond your normal responsibilities.", "Proactivity and ownership."),
            Template("Tell me about a time you had to learn something new quickly.", "Learning agility and resourcefulness."),
            Template("Describe a time you disagreed with a decision. What did you do?", "Respectful disagreement and constructive outcomes."),
            Template("Tell me about a school, volunteer or personal project you're proud of.", "Drive and transferable skills.", [.entry]),
            Template("Tell me about a time you mentored someone or led a team through a difficult project.", "Leadership and developing others.", [.senior]),
            Template("Describe a significant decision you made with incomplete information. What was the outcome?", "Judgment under ambiguity.", [.senior]),
        ],
        .situational: [
            Template("Imagine you're halfway through an important task and your manager asks you to switch to something urgent. How would you handle it?", "Prioritisation and clear communication."),
            Template("If you noticed a coworker cutting corners on safety or quality, what would you do?", "Integrity and tactful escalation."),
            Template("Suppose a customer is unhappy with work you completed. How would you respond?", "Customer focus and ownership."),
            Template("If you were given a task with unclear instructions, how would you proceed?", "Asking good questions and avoiding wasted effort."),
            Template("What would you do if you realised you couldn't finish an assignment on time?", "Early communication and problem solving."),
            Template("If two senior colleagues gave you conflicting instructions, how would you handle it?", "Diplomacy and seeking alignment.", [.intermediate, .senior]),
        ],
        .motivation: [
            Template("What kind of work environment helps you do your best work?", "Self-awareness and fit."),
            Template("Why should we choose you for this {position} position?", "A confident, evidence-based pitch."),
            Template("What would you hope to accomplish in your first year as a {position}?", "Ambition grounded in the role's goals."),
        ],
        .closing: [
            Template("Where do you see yourself professionally in the next three to five years?", "Direction and commitment."),
            Template("Finally, what's one thing you'd like me to remember about you after today?", "A memorable, relevant closing statement."),
            Template("To wrap up, why is now the right time for you to take on a {position} role?", "Readiness and motivation."),
        ],
    ]

    static func middlePlan(for focus: InterviewFocus) -> [QuestionCategory] {
        switch focus {
        case .balanced: [.technical, .behavioral, .situational, .technical, .behavioral, .motivation, .situational, .technical]
        case .behavioral: [.behavioral, .behavioral, .technical, .behavioral, .situational, .behavioral, .motivation]
        case .technical: [.technical, .technical, .behavioral, .technical, .situational, .technical, .motivation]
        case .situational: [.situational, .situational, .behavioral, .situational, .technical, .situational, .motivation]
        }
    }

    public init() {}

    public func questions(for request: QuestionRequest) -> [InterviewQuestion] {
        var generator = SystemRandomNumberGenerator()
        return questions(for: request, using: &generator)
    }

    public func questions<G: RandomNumberGenerator>(for request: QuestionRequest, using generator: inout G) -> [InterviewQuestion] {
        let count = min(max(request.count, 1), 15)
        var pools: [QuestionCategory: [Template]] = [:]
        for (category, templates) in Self.templates {
            pools[category] = templates.filter { $0.difficulties.contains(request.difficulty) }.shuffled(using: &generator)
        }

        var plan: [QuestionCategory] = [.opener]
        let middle = Self.middlePlan(for: request.focus)
        while plan.count < count - (count >= 3 ? 1 : 0) {
            plan.append(middle[(plan.count - 1) % middle.count])
        }
        if count >= 3 { plan.append(.closing) }
        plan = Array(plan.prefix(count))

        var result: [InterviewQuestion] = []
        for category in plan {
            var chosenCategory = category
            if pools[category]?.isEmpty ?? true {
                // Fall back to whichever category has the most unused questions left.
                chosenCategory = pools.max { $0.value.count < $1.value.count }?.key ?? category
            }
            guard let template = pools[chosenCategory]?.popLast() else { continue }
            result.append(InterviewQuestion(text: fill(template.text, position: request.position), category: chosenCategory, intent: template.intent))
        }
        return result
    }

    /// Tops up an AI-generated list that came back short, avoiding duplicates.
    public func padding(_ existing: [InterviewQuestion], toMatch request: QuestionRequest) -> [InterviewQuestion] {
        guard existing.count < request.count else { return Array(existing.prefix(request.count)) }
        let existingTexts = Set(existing.map { $0.text.lowercased() })
        var extras = questions(for: QuestionRequest(position: request.position, count: 15, difficulty: request.difficulty, focus: request.focus))
            .filter { !existingTexts.contains($0.text.lowercased()) && $0.category != .opener }
        var result = existing
        while result.count < request.count, !extras.isEmpty {
            // Keep a closing question last if the AI provided one.
            if let last = result.last, last.category == .closing {
                result.insert(extras.removeFirst(), at: result.count - 1)
            } else {
                result.append(extras.removeFirst())
            }
        }
        return result
    }

    private func fill(_ text: String, position: String) -> String {
        text.replacingOccurrences(of: "{position}", with: position)
    }
}
