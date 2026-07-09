import Foundation
import StandUpCore

#if canImport(CoreMotion)
import CoreMotion
#endif

protocol MotionActivityProviding {
    func start(_ handler: @escaping @MainActor (ActivitySignal) -> Void)
    func stop()
}

final class CoreMotionActivityService: MotionActivityProviding {
    #if canImport(CoreMotion)
    private let manager = CMMotionActivityManager()
    #endif

    func start(_ handler: @escaping @MainActor (ActivitySignal) -> Void) {
        #if canImport(CoreMotion)
        guard CMMotionActivityManager.isActivityAvailable() else {
            Task { @MainActor in handler(.unavailable) }
            return
        }

        manager.startActivityUpdates(to: .main) { activity in
            guard let activity else {
                Task { @MainActor in handler(.unavailable) }
                return
            }

            let signal: ActivitySignal
            if activity.walking || activity.running || activity.cycling {
                signal = .active
            } else if activity.stationary {
                signal = .sedentary
            } else {
                signal = .unavailable
            }

            Task { @MainActor in handler(signal) }
        }
        #else
        Task { @MainActor in handler(.unavailable) }
        #endif
    }

    func stop() {
        #if canImport(CoreMotion)
        manager.stopActivityUpdates()
        #endif
    }
}
