import Foundation
import StandUpCore

#if canImport(CoreMotion)
import CoreMotion
#endif

@MainActor
protocol MotionActivityProviding {
    func start(
        since: Date,
        _ handler: @escaping @MainActor (MotionActivityObservation) -> Void
    )
    func stop()
}

@MainActor
final class CoreMotionActivityService: MotionActivityProviding {
    #if canImport(CoreMotion)
    private let manager = CMMotionActivityManager()
    private var generation = 0
    #endif

    func start(
        since recoveryStart: Date,
        _ handler: @escaping @MainActor (MotionActivityObservation) -> Void
    ) {
        #if canImport(CoreMotion)
        generation += 1
        let currentGeneration = generation
        manager.stopActivityUpdates()

        guard CMMotionActivityManager.isActivityAvailable() else {
            handler(MotionActivityObservation(signal: .unavailable, startedAt: Date()))
            return
        }

        switch CMMotionActivityManager.authorizationStatus() {
        case .denied, .restricted:
            handler(MotionActivityObservation(signal: .unavailable, startedAt: Date()))
            return
        case .notDetermined, .authorized:
            break
        @unknown default:
            handler(MotionActivityObservation(signal: .unavailable, startedAt: Date()))
            return
        }

        let historyEnd = Date()
        guard recoveryStart < historyEnd else {
            startLiveUpdates(generation: currentGeneration, handler)
            return
        }

        manager.queryActivityStarting(
            from: recoveryStart,
            to: historyEnd,
            to: .main
        ) { [weak self] activities, _ in
            let samples = (activities ?? []).map(MotionActivitySample.init)
            let authorizationDenied: Bool
            switch CMMotionActivityManager.authorizationStatus() {
            case .denied, .restricted:
                authorizationDenied = true
            case .notDetermined, .authorized:
                authorizationDenied = false
            @unknown default:
                authorizationDenied = true
            }

            Task { @MainActor [weak self] in
                guard let self, generation == currentGeneration else {
                    return
                }

                if authorizationDenied {
                    handler(MotionActivityObservation(signal: .unavailable, startedAt: Date()))
                    return
                }

                let observations = MotionActivityClassifier.normalizedObservations(
                    from: samples,
                    since: recoveryStart
                )
                observations.forEach(handler)
                startLiveUpdates(generation: currentGeneration, handler)
            }
        }
        #else
        handler(MotionActivityObservation(signal: .unavailable, startedAt: Date()))
        #endif
    }

    func stop() {
        #if canImport(CoreMotion)
        generation += 1
        manager.stopActivityUpdates()
        #endif
    }

    #if canImport(CoreMotion)
    private func startLiveUpdates(
        generation expectedGeneration: Int,
        _ handler: @escaping @MainActor (MotionActivityObservation) -> Void
    ) {
        manager.startActivityUpdates(to: .main) { [weak self] activity in
            let sample = activity.map(MotionActivitySample.init)
            let authorizationDenied: Bool
            switch CMMotionActivityManager.authorizationStatus() {
            case .denied, .restricted:
                authorizationDenied = true
            case .notDetermined, .authorized:
                authorizationDenied = false
            @unknown default:
                authorizationDenied = true
            }

            Task { @MainActor [weak self] in
                guard let self, generation == expectedGeneration else {
                    return
                }

                if authorizationDenied {
                    handler(MotionActivityObservation(signal: .unavailable, startedAt: Date()))
                    return
                }

                guard let sample, let signal = MotionActivityClassifier.signal(for: sample) else {
                    return
                }

                handler(MotionActivityObservation(signal: signal, startedAt: sample.startedAt))
            }
        }
    }
    #endif
}

#if canImport(CoreMotion)
private extension MotionActivitySample {
    init(_ activity: CMMotionActivity) {
        self.init(
            startedAt: activity.startDate,
            stationary: activity.stationary,
            walking: activity.walking,
            running: activity.running,
            cycling: activity.cycling,
            automotive: activity.automotive,
            unknown: activity.unknown
        )
    }
}
#endif
