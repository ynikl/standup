import SwiftUI

@main
struct StandUpWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = StandUpAppModel()
    private let motion = CoreMotionActivityService()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(model)
                .task {
                    startMotionMonitoring()
                    await model.requestPermissions()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        startMotionMonitoring()
                    } else {
                        motion.stop()
                    }
                }
        }
    }

    private func startMotionMonitoring(now: Date = Date()) {
        model.refresh(now: now)
        motion.start(since: model.motionRecoveryStart(now: now)) { observation in
            model.ingest(activity: observation.signal, now: observation.startedAt)
            model.refresh()
        }
    }
}
