import SwiftUI

@main
struct StandUpiOSApp: App {
    @StateObject private var model = StandUpAppModel()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(model)
                .task {
                    await model.requestPermissions()
                    model.refresh()
                }
        }
    }
}
