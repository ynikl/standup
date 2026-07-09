import Foundation
import StandUpCore

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

@MainActor
protocol StandUpSyncing: AnyObject {
    var onReceive: ((StandUpPersistedState) -> Void)? { get set }

    func activate()
    func publish(settings: StandUpSettings, records: [SedentaryRecord])
}

@MainActor
final class WatchConnectivityStandUpBridge: NSObject, StandUpSyncing {
    var onReceive: ((StandUpPersistedState) -> Void)?

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    override init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        super.init()
    }

    func activate() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else {
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
        #endif
    }

    func publish(settings: StandUpSettings, records: [SedentaryRecord]) {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else {
            return
        }

        let state = StandUpPersistedState(settings: settings, records: records)
        guard let data = try? encoder.encode(state) else {
            return
        }

        try? WCSession.default.updateApplicationContext(["standupState": data])
        #endif
    }

    private func receive(_ data: Data) {
        guard let state = try? decoder.decode(StandUpPersistedState.self, from: data) else {
            return
        }
        onReceive?(state)
    }
}

#if canImport(WatchConnectivity)
extension WatchConnectivityStandUpBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["standupState"] as? Data else {
            return
        }

        Task { @MainActor in
            self.receive(data)
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
#endif
