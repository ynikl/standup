import SwiftUI

@main
struct StandUpiOSApp: App {
    @StateObject private var model = StandUpAppModel(managesReminders: false)

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(model)
                .task {
                    await LocalStandUpNotificationScheduler().cancelSedentaryReminders()
                }
        }
    }
}
