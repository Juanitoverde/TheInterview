import SwiftUI
import RealityKit

struct ImmersiveOfficeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    private static let panelID = "interview-panel"

    var body: some View {
        RealityView { content, attachments in
            // Downloaded models (if any) replace the built-in office and people.
            let assets = await OfficeAssets.load()
            let stage = OfficeStage(configuration: model.settings.interviewConfiguration, comfortMode: model.settings.comfortMode, assets: assets)
            content.add(stage.root)
            if let panel = attachments.entity(for: Self.panelID) {
                stage.attachHUD(panel)
            }
            model.officeDidLoad(stage)
        } attachments: {
            Attachment(id: Self.panelID) {
                InterviewPanelView()
                    .environment(model)
            }
        }
        .task {
            await model.attentionTracker.startSession()
        }
        .onChange(of: model.exitImmersiveRequested) { _, shouldExit in
            guard shouldExit else { return }
            Task {
                model.reopenMainWindow(openWindow)
                await dismissImmersiveSpace()
            }
        }
        .onDisappear {
            model.reopenMainWindow(openWindow)
            model.immersiveSpaceDidClose()
        }
    }
}
