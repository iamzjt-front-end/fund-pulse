import Foundation

protocol PortfolioRepository {
    var dataDirectory: URL { get }
    var dataFileURL: URL { get }

    func load() throws -> PortfolioSnapshot?
    func save(_ snapshot: PortfolioSnapshot) throws
}

struct JSONPortfolioRepository: PortfolioRepository {
    let dataDirectory: URL

    var dataFileURL: URL {
        dataDirectory.appending(path: "portfolio.json")
    }

    func load() throws -> PortfolioSnapshot? {
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: dataFileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: dataFileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PortfolioSnapshot.self, from: data)
    }

    func save(_ snapshot: PortfolioSnapshot) throws {
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: dataFileURL, options: .atomic)
    }
}

final class StagedPortfolioRepository: PortfolioRepository {
    let dataDirectory: URL
    var dataFileURL: URL {
        dataDirectory.appending(path: "portfolio.json")
    }
    private var snapshot: PortfolioSnapshot?

    init(dataDirectory: URL, snapshot: PortfolioSnapshot) {
        self.dataDirectory = dataDirectory
        self.snapshot = snapshot
    }

    func load() throws -> PortfolioSnapshot? {
        snapshot
    }

    func save(_ snapshot: PortfolioSnapshot) throws {
        self.snapshot = snapshot
    }
}
