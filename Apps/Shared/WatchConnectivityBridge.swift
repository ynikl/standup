import Foundation
import StandUpCore

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

@MainActor
protocol StandUpSyncing: AnyObject {
    var onReceive: ((StandUpDataState) -> Void)? { get set }
    var onError: ((Error) -> Void)? { get set }

    func activate()
    func publish(_ state: StandUpDataState) throws
}

@MainActor
final class WatchConnectivityStandUpBridge: NSObject, StandUpSyncing {
    var onReceive: ((StandUpDataState) -> Void)?
    var onError: ((Error) -> Void)?

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

    func publish(_ state: StandUpDataState) throws {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else {
            return
        }

        let data = try encoder.encode(state)
        try WCSession.default.updateApplicationContext(["standupState": data])
        #endif
    }

    func receive(_ data: Data) {
        do {
            let state = try decoder.decode(StandUpDataState.self, from: data)
            onReceive?(state)
        } catch {
            onError?(error)
        }
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
