import SwiftUI
import InterviewCore

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var showingSettings = false
    @State private var isStarting = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            HStack(alignment: .top, spacing: 32) {
                ScrollView {
                    introduction
                }
                .frame(maxWidth: .infinity)
                setupForm(settings: $model.settings)
                    .frame(width: 440)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environment(model)
            }
            .onChange(of: model.settings) {
                model.saveSettings()
            }
        }
    }

    // MARK: Introduction

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("TheInterview")
                    .font(.largeTitle.bold())
                Text("Practise job interviews in a realistic virtual office, then get detailed feedback.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(systemImage: "building.2", title: "Step into the office",
                           text: "Check in at reception, follow the receptionist down the corridor and meet your interviewer.")
                FeatureRow(systemImage: "sparkles", title: "Fresh questions every time",
                           text: "Questions are written for the exact role you name, and the interviewer follows up when an answer is vague.")
                FeatureRow(systemImage: "waveform", title: "Answer out loud",
                           text: "Speak naturally. Say “that's my answer” or tap Done when you've finished.")
                FeatureRow(systemImage: "eye", title: "Eye-contact feedback",
                           text: "Head tracking shows how well you kept your attention on the interviewer.")
                FeatureRow(systemImage: "chart.bar.doc.horizontal", title: "A detailed report",
                           text: "Scores, strengths and specific tips for every answer.")
            }

            Button(action: start) {
                Label(isStarting ? "Opening the office…" : "Enter the office", systemImage: "door.left.hand.open")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            .disabled(isStarting)

            aiStatus

            if !model.history.isEmpty {
                recentSessions
            }
        }
        .padding(.vertical, 24)
    }

    private var aiStatus: some View {
        Group {
            if let ai = model.activeAIDescription {
                Label("Tailored questions and AI feedback from \(ai).", systemImage: "checkmark.seal")
            } else {
                Label("Built-in questions and on-device scoring. Add an OpenAI API key in Settings, or use Apple Intelligence on visionOS 26, for questions written for your role and AI feedback.", systemImage: "info.circle")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private var recentSessions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent sessions")
                .font(.title3.weight(.semibold))
            ForEach(model.history.prefix(5)) { report in
                Button {
                    model.showReport(report)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(report.position)
                                .font(.headline)
                            Text(report.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(report.overallScore)")
                            .font(.title3.weight(.semibold))
                        Text("/100")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                .contextMenu {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        model.deleteReport(report)
                    }
                }
            }
        }
    }

    // MARK: Setup

    private func setupForm(settings: Binding<AppSettings>) -> some View {
        Form {
            Section("About you") {
                TextField("Your name", text: settings.candidateName)
                    .textContentType(.name)
                Picker("Address me as", selection: settings.formOfAddress) {
                    ForEach(FormOfAddress.allCases) { form in
                        Text(form.displayName).tag(form)
                    }
                }
            }

            Section {
                TextField("Position (optional)", text: settings.presetPosition)
            } header: {
                Text("The role")
            } footer: {
                Text("You'll tell the receptionist which job you're applying for. This is only used if she can't hear you.")
            }

            Section("Interview") {
                Stepper("Questions: \(settings.questionCount.wrappedValue)", value: settings.questionCount, in: InterviewConfiguration.questionCountRange)
                Picker("Level", selection: settings.difficulty) {
                    ForEach(Difficulty.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                Picker("Question focus", selection: settings.focus) {
                    ForEach(InterviewFocus.allCases) { focus in
                        Text(focus.displayName).tag(focus)
                    }
                }
            }

            Section {
                Toggle("Comfort mode", isOn: settings.comfortMode)
                Toggle("Live eye-contact indicator", isOn: settings.showsLiveEyeContact)
            } header: {
                Text("Experience")
            } footer: {
                Text("Comfort mode fades between rooms instead of walking, for anyone sensitive to motion in VR.")
            }
        }
    }

    private func start() {
        guard !isStarting else { return }
        isStarting = true
        Task {
            await model.prepareInterview()
            switch await openImmersiveSpace(id: AppModel.officeSpaceID) {
            case .opened:
                dismissWindow(id: AppModel.mainWindowID)
            default:
                model.immersiveSpaceFailedToOpen()
            }
            isStarting = false
        }
    }
}

private struct FeatureRow: View {
    let systemImage: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 36)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
