import Foundation

enum LocalStore {
    private static func dir() throws -> URL {
        let url = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = url.appendingPathComponent("RaceSavantCache", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    private static func file(_ name: String) throws -> URL { try dir().appendingPathComponent(name).appendingPathExtension("json") }

    static func load<T: Decodable>(_ name: String, as: T.Type = T.self) -> T? {
        do {
            let url = try file(name)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let data = try Data(contentsOf: url)
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            return try dec.decode(T.self, from: data)
        } catch { return nil }
    }

    static func save<T: Encodable>(_ name: String, value: T) {
        do {
            let url = try file(name)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted]
            enc.dateEncodingStrategy = .iso8601
            let data = try enc.encode(value)
            try data.write(to: url, options: .atomic)
        } catch { /* ignore */ }
    }

    static func loadData(_ name: String) -> Data? {
        do { let url = try file(name); return try Data(contentsOf: url) } catch { return nil }
    }

    static func saveData(_ name: String, data: Data) { do { let url = try file(name); try data.write(to: url, options: .atomic) } catch { /* ignore */ } }

    // MARK: - Lightweight primitives
    static func loadInt(_ name: String) -> Int? {
        guard let data = loadData(name) else { return nil }
        return Int(String(decoding: data, as: UTF8.self))
    }

    static func saveInt(_ name: String, value: Int) {
        if let data = String(value).data(using: .utf8) { saveData(name, data: data) }
    }

    // Keys for session_key caching by slug
    static func sessionKeyCacheKey(slug: String) -> String { "session_key_\(slug)" }
    static func sessionKeySlug(year: Int, location: String, sessionName: String, countryFallback: String?) -> String {
        let basis: String
        if let cf = countryFallback, !cf.isEmpty {
            basis = "y=\(year)|ctry=\(cf)|name=\(sessionName)"
        } else {
            basis = "y=\(year)|loc=\(location)|name=\(sessionName)"
        }
        // sanitize: replace spaces
        return basis.replacingOccurrences(of: " ", with: "_")
    }

    // Convenience keys
    static func scheduleKey(year: Int) -> String { "schedule_\(year)" }
    static func driverStandingsKey(year: Int) -> String { "driver_standings_\(year)" }
    static func constructorStandingsKey(year: Int) -> String { "constructor_standings_\(year)" }
    static func sessionResultsKey(sessionKey: Int) -> String { "session_results_\(sessionKey)" }
}
