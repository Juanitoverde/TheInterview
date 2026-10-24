import SwiftUI

@main
struct TheInterviewApp: App {
    @State private var model = AppModel()

    init() {
        CharacterAnimationComponent.registerComponent()
        CharacterAnimationSystem.registerSystem()
    }

    var body: some Scene {
        WindowGroup(id: AppModel.mainWindowID) {
            ContentView()
                .environment(model)
        }
        .defaultSize(width: 1000, height: 760)

        ImmersiveSpace(id: AppModel.officeSpaceID) {
            ImmersiveOfficeView()
                .environment(model)
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }
}
