import Foundation
import StandUpCore

protocol StandUpStorage {
    func load() throws -> StandUpLocalState
    func save(_ state: StandUpLocalState) throws
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

    func load() throws -> StandUpLocalState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return StandUpLocalState(
                synchronized: StandUpDataState(
                    settings: .default,
                    settingsUpdatedAt: Date(timeIntervalSince1970: 0),
                    records: []
                )
            )
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.standUp.decode(StandUpLocalState.self, from: data)
    }

    func save(_ state: StandUpLocalState) throws {
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
