import SwiftUI
import InterviewCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var apiKeyDraft = ""
    @State private var connection: ConnectionState = .idle

    private enum ConnectionState: Equatable {
        case idle
        case testing
        case succeeded
        case failed(String)
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    SecureField(model.hasAPIKey ? "Replace the saved API key" : "OpenAI API key", text: $apiKeyDraft)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    HStack {
                        Button("Save key") {
                            if model.updateAPIKey(apiKeyDraft) {
                                apiKeyDraft = ""
                                connection = .idle
                            } else {
                                connection = .failed("The key couldn't be saved to the Keychain.")
                            }
                        }
                        .disabled(apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                        if model.hasAPIKey {
                            Spacer()
                            Button("Remove key", role: .destructive) {
                                _ = model.updateAPIKey("")
                                connection = .idle
                            }
                        }
                    }
                    TextField("Model", text: $model.settings.openAIModel)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button {
                        Task {
                            connection = .testing
                            if let error = await model.testOpenAIConnection() {
                                connection = .failed(error)
                            } else {
                                connection = .succeeded
                            }
                        }
                    } label: {
                        connectionLabel
                    }
                    .disabled(!model.hasAPIKey || connection == .testing)
                    Toggle("AI-written interviewer reactions", isOn: $model.settings.usesAIReactions)
                    Link("Get an API key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                } header: {
                    Text("OpenAI")
                } footer: {
                    Text("Your key is stored in this device's Keychain. With a key, questions are written for the role you name and your answers are evaluated by OpenAI. Without one, TheInterview uses its built-in questions and on-device scoring.")
                }

                Section("Voices and timing") {
                    VStack(alignment: .leading) {
                        Text("Speaking speed")
                        Slider(value: $model.settings.speechRate, in: 0.38...0.58) {
                            Text("Speaking speed")
                        } minimumValueLabel: {
                            Image(systemName: "tortoise")
                        } maximumValueLabel: {
                            Image(systemName: "hare")
                        }
                    }
                    Stepper(
                        "End an answer after \(Int(model.settings.answerSilenceTimeout)) s of silence",
                        value: $model.settings.answerSilenceTimeout,
                        in: 3...12,
                        step: 1
                    )
                }

                Section("Office") {
                    TextField("Company name", text: $model.settings.companyName)
                }

                Section("Privacy") {
                    Text("Eye contact is estimated from the direction your head faces. visionOS doesn't share where your eyes look with apps.")
                    Text("Speech is recognised on device when supported. Transcripts are sent to OpenAI only when an API key is saved. Reports are stored on this device.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.saveSettings()
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 620, minHeight: 680)
    }

    @ViewBuilder
    private var connectionLabel: some View {
        switch connection {
        case .idle:
            Label("Test connection", systemImage: "bolt.horizontal")
        case .testing:
            HStack {
                ProgressView()
                Text("Testing…")
            }
        case .succeeded:
            Label("Connected", systemImage: "checkmark.circle")
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .lineLimit(3)
        }
    }
}
