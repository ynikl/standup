import Foundation
import StandUpCore

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

@MainActor
protocol StandUpSyncing: AnyObject {
    var onReceive: ((StandUpDataState) -> Void)? { get set }
    var onError: ((Error) -> Void)? { get set }
    var onActivation: (() -> Void)? { get set }

    func activate()
    func retryActivation() async
    func publish(_ state: StandUpDataState) throws
}

@MainActor
final class WatchConnectivityStandUpBridge: NSObject, StandUpSyncing {
    var onReceive: ((StandUpDataState) -> Void)?
    var onError: ((Error) -> Void)?
    var onActivation: (() -> Void)?

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var activationWaiters: [CheckedContinuation<Void, Never>] = []

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
        let session = WCSession.default
        session.delegate = self
        if session.activationState == .activated {
            completeActivation(
                error: nil,
                receivedData: session.receivedApplicationContext["standupState"] as? Data
            )
        } else {
            session.activate()
        }
        #endif
    }

    func retryActivation() async {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else {
            return
        }
        await withCheckedContinuation { continuation in
            activationWaiters.append(continuation)
            activate()
        }
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

    func handleActivation(error: Error?) {
        if let error {
            onError?(error)
        } else {
            onActivation?()
        }
    }

    private func completeActivation(error: Error?, receivedData: Data? = nil) {
        handleActivation(error: error)
        if error == nil, let receivedData {
            receive(receivedData)
        }

        let waiters = activationWaiters
        activationWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

#if canImport(WatchConnectivity)
extension WatchConnectivityStandUpBridge: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let receivedData = session.receivedApplicationContext["standupState"] as? Data
        Task { @MainActor in
            if let error {
                self.completeActivation(error: error)
            } else if activationState == .activated {
                self.completeActivation(error: nil, receivedData: receivedData)
            } else {
                self.completeActivation(error: WatchConnectivityStandUpBridgeError.activationDidNotComplete)
            }
        }
    }

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

private enum WatchConnectivityStandUpBridgeError: LocalizedError {
    case activationDidNotComplete

    var errorDescription: String? {
        "Watch session activation did not complete."
    }
}
