import Foundation
import StandUpCore

struct MotionActivitySample: Equatable, Sendable {
    var startedAt: Date
    var stationary: Bool
    var walking: Bool
    var running: Bool
    var cycling: Bool
    var automotive: Bool
    var unknown: Bool

    init(
        startedAt: Date,
        stationary: Bool = false,
        walking: Bool = false,
        running: Bool = false,
        cycling: Bool = false,
        automotive: Bool = false,
        unknown: Bool = false
    ) {
        self.startedAt = startedAt
        self.stationary = stationary
        self.walking = walking
        self.running = running
        self.cycling = cycling
        self.automotive = automotive
        self.unknown = unknown
    }
}

struct MotionActivityObservation: Equatable, Sendable {
    var signal: ActivitySignal
    var startedAt: Date
}

enum MotionActivityClassifier {
    static func signal(for sample: MotionActivitySample) -> ActivitySignal? {
        if sample.walking || sample.running || sample.cycling {
            return .active
        }

        if sample.stationary {
            return .sedentary
        }

        return nil
    }

    static func normalizedObservations(
        from samples: [MotionActivitySample],
        since lowerBound: Date
    ) -> [MotionActivityObservation] {
        var observations: [MotionActivityObservation] = []
        var previousSignal: ActivitySignal?

        for sample in samples.sorted(by: { $0.startedAt < $1.startedAt }) {
            guard let signal = signal(for: sample), signal != previousSignal else {
                continue
            }

            observations.append(
                MotionActivityObservation(
                    signal: signal,
                    startedAt: max(sample.startedAt, lowerBound)
                )
            )
            previousSignal = signal
        }

        return observations
    }
}
