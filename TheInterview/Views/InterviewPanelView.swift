import SwiftUI
import InterviewCore

/// The floating panel in the office: captions, what the app heard, and the interview controls.
struct InterviewPanelView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @State private var showsKeyboard = false

    var body: some View {
        let state = model.interview
        VStack(alignment: .leading, spacing: 18) {
            header(state)
            caption(state)
            if state.isListening {
                listening(state)
                if showsKeyboard || !model.isVoiceInputAvailable {
                    typingField
                }
            }
            controls(state)
        }
        .padding(28)
        .frame(width: 720, alignment: .leading)
        .glassBackgroundEffect()
        .animation(.easeInOut(duration: 0.2), value: state.isListening)
        .onChange(of: state.isListening) { _, listening in
            if !listening { draft = "" }
        }
    }

    // MARK: Sections

    private func header(_ state: InterviewState) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.phase.title)
                    .font(.headline)
                if state.phase.isInQuestions, let number = state.questionNumber, state.questionCount > 0 {
                    Text(state.isFollowUp ? "Follow-up on question \(number) of \(state.questionCount)" : "Question \(number) of \(state.questionCount)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.settings.showsLiveEyeContact, let engaged = model.liveEngagement {
                Label(engaged ? "Eye contact" : "Look at the interviewer", systemImage: engaged ? "eye" : "eye.slash")
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: .capsule)
            }
            Button(role: .destructive) {
                model.leaveInterview()
            } label: {
                Label("Leave", systemImage: "xmark")
            }
            .help("Leave the office without feedback")
        }
    }

    @ViewBuilder
    private func caption(_ state: InterviewState) -> some View {
        if !state.caption.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(speakerTitle(state.captionSpeaker))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(state.caption)
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func listening(_ state: InterviewState) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if model.isVoiceInputAvailable {
                MicLevelView(level: model.micLevel)
            } else {
                Image(systemName: "keyboard")
                    .font(.title2)
                    .frame(width: 42, height: 36)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(state.isFollowUp && state.listeningPurpose == .answer ? "Answer the follow-up. Say “that's my answer” or tap Done when finished" : prompt(for: state.listeningPurpose))
                    .font(.headline)
                Text(state.liveTranscript.isEmpty ? (model.isVoiceInputAvailable ? "Listening…" : "Type your reply below.") : state.liveTranscript)
                    .foregroundStyle(state.liveTranscript.isEmpty ? .secondary : .primary)
                    .lineLimit(4)
                    .truncationMode(.head)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 18))
    }

    private var typingField: some View {
        HStack(spacing: 12) {
            TextField("Type your reply", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .onSubmit(send)
            Button("Send", action: send)
                .buttonStyle(.borderedProminent)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func controls(_ state: InterviewState) -> some View {
        HStack(spacing: 12) {
            if state.canFinishAnswer {
                Button {
                    model.finishAnswer()
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
            }
            if state.phase == .answering {
                Button {
                    model.repeatQuestion()
                } label: {
                    Label("Repeat question", systemImage: "arrow.counterclockwise")
                }
            }
            if state.isListening, model.isVoiceInputAvailable {
                Button {
                    showsKeyboard.toggle()
                } label: {
                    Label(showsKeyboard ? "Hide keyboard" : "Type instead", systemImage: "keyboard")
                }
            }
            Spacer()
            if state.phase.isInQuestions {
                Button {
                    model.endInterviewEarly()
                } label: {
                    Label("Finish & get feedback", systemImage: "flag.checkered")
                }
            }
        }
    }

    // MARK: Helpers

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        model.submitTypedReply(text)
        draft = ""
    }

    private func speakerTitle(_ speaker: Speaker?) -> String {
        let configuration = model.settings.interviewConfiguration
        switch speaker {
        case .receptionist: return "\(configuration.receptionistName) · Receptionist"
        case .interviewer: return "\(configuration.interviewerName) · Interviewer"
        case .candidate: return "You"
        case nil: return ""
        }
    }

    private func prompt(for purpose: ListenPurpose?) -> String {
        switch purpose {
        case .position: "Tell the receptionist which job you're applying for"
        case .readiness: "Answer the interviewer"
        case .answer: "Your answer. Say “that's my answer” or tap Done when finished"
        case nil: "Listening"
        }
    }
}
