import SwiftUI

@main
struct StandUpWatchApp: App {
    @StateObject private var model = StandUpAppModel()
    private let motion = CoreMotionActivityService()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(model)
                .task {
                    await model.requestPermissions()
                    model.refresh()
                    motion.start { signal in
                        model.ingest(activity: signal)
                    }
                }
        }
    }
}
