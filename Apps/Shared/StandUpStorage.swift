import Foundation
import StandUpCore

struct StandUpPersistedState: Codable, Equatable {
    var settings: StandUpSettings
    var records: [SedentaryRecord]

    static let empty = StandUpPersistedState(settings: .default, records: [])
}

protocol StandUpStorage {
    func load() throws -> StandUpPersistedState
    func save(_ state: StandUpPersistedState) throws
}

struct LocalJSONStandUpStorage: StandUpStorage {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
            return
        }

        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.fileURL = directory.appendingPathComponent("standup-state.json")
    }

    func load() throws -> StandUpPersistedState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .empty
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.standUp.decode(StandUpPersistedState.self, from: data)
    }

    func save(_ state: StandUpPersistedState) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.standUp.encode(state)
        try data.write(to: fileURL, options: [.atomic])
    }
}

private extension JSONEncoder {
    static var standUp: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var standUp: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
