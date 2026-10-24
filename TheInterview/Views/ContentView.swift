import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.screen {
            case .home:
                HomeView()
            case .preparing:
                StatusView(
                    systemImage: "mic",
                    title: "Getting ready…",
                    message: "Checking microphone and speech recognition, then opening the office.",
                    showsProgress: true
                )
            case .interviewing:
                StatusView(
                    systemImage: "person.2.wave.2",
                    title: "Your interview is in progress",
                    message: "Head back into the office to continue, or leave without feedback.",
                    showsProgress: false
                ) {
                    Button("Leave interview", role: .destructive) { model.leaveInterview() }
                }
            case .analyzing:
                StatusView(
                    systemImage: "chart.bar.doc.horizontal",
                    title: "Analyzing your interview…",
                    message: model.activeAIDescription.map { "Your answers are being reviewed by \($0). This usually takes a few seconds." } ?? "Scoring your answers on device.",
                    showsProgress: true
                )
            case .report(let report):
                ReportView(report: report)
            }
        }
        .onAppear { model.mainWindowIsOpen = true }
        .onDisappear { model.mainWindowIsOpen = false }
        .alert("TheInterview", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alertMessage ?? "")
        }
    }
}

struct StatusView<Actions: View>: View {
    let systemImage: String
    let title: String
    let message: String
    let showsProgress: Bool
    @ViewBuilder var actions: () -> Actions

    init(systemImage: String, title: String, message: String, showsProgress: Bool, @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.showsProgress = showsProgress
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: systemImage)
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.largeTitle.weight(.semibold))
            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            if showsProgress {
                ProgressView()
                    .padding(.top, 8)
            }
            actions()
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
