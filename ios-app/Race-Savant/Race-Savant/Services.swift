import Foundation

// Networking helpers for third-party APIs and backend telemetry.

final class APIService {
    static let shared = APIService()
    private init() {}

    // Base URLs
    var backendBase = URL(string: "http://127.0.0.1:8000")!
    let openF1Base = URL(string: "https://api.openf1.org/v1")!
    let ergastDriver = URL(string: "https://api.jolpi.ca/ergast/f1/2025/driverstandings/")!
    let ergastConstructor = URL(string: "https://api.jolpi.ca/ergast/f1/2025/constructorstandings/")!

    // MARK: - Backend API

    struct YearItem: Decodable { let year: Int; let events: Int; let sessions: Int; let laps: Int }
    struct EventItem: Decodable, Identifiable { let id: Int; let year: Int; let round: Int?; let name: String?; let location: String?; let country: String?; let date: String?; let session_types: [String] }
    struct SessionItem: Decodable, Identifiable { let id: Int; let type: String?; let date: String? }
    struct DriverItem: Decodable, Identifiable { let id: Int; let code: String?; let number: Int?; let first_name: String?; let last_name: String?; let team_name: String?; let team_color: String? }
    struct LapItem: Decodable { let lap_number: Int; let lap_time_ms: Int?; let position: Int?; let compound: String?; let track_status: String? }
    struct LapTelemetry: Decodable { let session_id: Int; let driver_id: Int; let lap_number: Int; let time_s: [Double?]; let distance_m: [Double?]; let speed_kmh: [Double?]; let rpm: [Double?]; let gear: [Int?]; let throttle: [Double?]; let brake: [Bool?]; let drs: [Int?]; let meta: LapItem }

    struct ScheduleEventItem: Decodable {
        let RoundNumber: Int?
        let Country: String?
        let Location: String?
        let EventName: String?
        let EventDate: String?
        let Session1: String?
        let Session1DateUtc: String?
        let Session2: String?
        let Session2DateUtc: String?
        let Session3: String?
        let Session3DateUtc: String?
        let Session4: String?
        let Session4DateUtc: String?
        let Session5: String?
        let Session5DateUtc: String?
    }

    func getYears() async throws -> [YearItem] {
        let url = backendBase.appending(path: "/telemetry/years")
        return try await fetch(url)
    }

    func getEvents(year: Int?) async throws -> [EventItem] {
        var comps = URLComponents(url: backendBase.appending(path: "/telemetry/events"), resolvingAgainstBaseURL: false)!
        if let y = year { comps.queryItems = [URLQueryItem(name: "year", value: String(y))] }
        return try await fetch(comps.url!)
    }

    func getSessions(eventId: Int) async throws -> [SessionItem] {
        let url = backendBase.appending(path: "/telemetry/events/\(eventId)/sessions")
        return try await fetch(url)
    }

    func getDrivers(sessionId: Int) async throws -> [DriverItem] {
        let url = backendBase.appending(path: "/telemetry/sessions/\(sessionId)/drivers")
        return try await fetch(url)
    }

    func getLaps(sessionId: Int, driverId: Int) async throws -> [LapItem] {
        let url = backendBase.appending(path: "/telemetry/sessions/\(sessionId)/drivers/\(driverId)/laps")
        return try await fetch(url)
    }

    func getLapTelemetry(sessionId: Int, driverId: Int, lapNumber: Int) async throws -> LapTelemetry {
        let url = backendBase.appending(path: "/telemetry/sessions/\(sessionId)/drivers/\(driverId)/laps/\(lapNumber)")
        return try await fetch(url)
    }

    func getSchedule(year: Int) async throws -> [ScheduleEvent] {
        let url = backendBase.appending(path: "/schedule/\(year)")
        let items: [ScheduleEventItem] = try await fetch(url)
        let iso = ISO8601DateFormatter()
        return items.compactMap { it in
            guard let country = it.Country, let location = it.Location, let name = it.EventName else { return nil }
            let start = it.EventDate.flatMap { iso.date(from: $0) } ?? Date()
            let dates = [it.Session1DateUtc, it.Session2DateUtc, it.Session3DateUtc, it.Session4DateUtc, it.Session5DateUtc].map { $0.flatMap { iso.date(from: $0) } }
            let names = [it.Session1, it.Session2, it.Session3, it.Session4, it.Session5]
            return ScheduleEvent(roundNumber: it.RoundNumber ?? 0,
                                 country: country,
                                 location: location,
                                 eventName: name,
                                 eventDate: start,
                                 sessionDatesUTC: dates,
                                 sessionNames: names)
        }
    }

    // MARK: - Ergast Standings
    struct ErgastMRData<T: Decodable>: Decodable { let MRData: T }
    struct StandingsTable<T: Decodable>: Decodable { let StandingsTable: T }
    struct DriverStandingsLists: Decodable { let StandingsLists: [DriverStandingsList] }
    struct DriverStandingsList: Decodable { let DriverStandings: [DriverStanding] }
    struct DriverStanding: Decodable { let position: String; let points: String; let wins: String; let Driver: ErgastDriver }
    struct ErgastDriver: Decodable { let permanentNumber: String?; let givenName: String?; let familyName: String? }

    struct ConstructorStandingsLists: Decodable { let StandingsLists: [ConstructorStandingsList] }
    struct ConstructorStandingsList: Decodable { let ConstructorStandings: [ConstructorStanding] }
    struct ConstructorStanding: Decodable { let position: String; let points: String; let wins: String; let Constructor: ErgastConstructor }
    struct ErgastConstructor: Decodable { let name: String }

    func getDriverStandings() async throws -> [DriverStandingItem] {
        let data: ErgastMRData<StandingsTable<DriverStandingsLists>> = try await fetch(ergastDriver)
        guard let list = data.MRData.StandingsTable.StandingsLists.first else { return [] }
        return list.DriverStandings.map { item in
            DriverStandingItem(position: Int(item.position) ?? 0,
                               points: item.points,
                               wins: item.wins,
                               driverNumber: item.Driver.permanentNumber ?? "")
        }
    }

    func getConstructorStandings() async throws -> [ConstructorStandingItem] {
        let data: ErgastMRData<StandingsTable<ConstructorStandingsLists>> = try await fetch(ergastConstructor)
        guard let list = data.MRData.StandingsTable.StandingsLists.first else { return [] }
        return list.ConstructorStandings.map { item in
            ConstructorStandingItem(position: item.position,
                                    points: item.points,
                                    wins: item.wins,
                                    name: item.Constructor.name)
        }
    }

    // MARK: - Generic fetch
    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }

    private func fetchData(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

// MARK: - OpenF1 Sessions & Results

extension APIService {
    struct OpenF1Session: Decodable {
        let session_key: Int
        let session_name: String
        let location: String?
        let country_name: String?
        let year: Int?
        let date_start: String?
    }

    struct OpenF1Result: Decodable {
        let position: Int?
        let driver_number: Int?
        let points: Int?
        let dnf: Bool?
        let dns: Bool?
        let dsq: Bool?
        let duration: DurationValue?

        enum DurationValue: Decodable {
            case str(String)
            case arr([String?])
            case dbl(Double)
            case arrD([Double?])

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let stringValue = try? container.decode(String.self) {
                    self = .str(stringValue)
                    return
                }
                if let doubleValue = try? container.decode(Double.self) {
                    self = .dbl(doubleValue)
                    return
                }
                if let stringArray = try? container.decode([String?].self) {
                    self = .arr(stringArray)
                    return
                }
                if let doubleArray = try? container.decode([Double?].self) {
                    self = .arrD(doubleArray)
                    return
                }
                self = .str("")
            }
        }
    }

    func getOpenF1Sessions(year: Int) async throws -> [OpenF1Session] {
        var comps = URLComponents(url: openF1Base.appending(path: "/sessions"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "year", value: String(year))]
        return try await fetch(comps.url!)
    }

    func buildSchedule(year: Int) async throws -> [ScheduleEvent] {
        let sessions = try await getOpenF1Sessions(year: year)
        // Group by (country, location)
        var groups: [String: [OpenF1Session]] = [:]
        for s in sessions {
            let key = "\(s.country_name ?? "")|\(s.location ?? "")"
            groups[key, default: []].append(s)
        }
        var events: [ScheduleEvent] = []
        for (_, arr) in groups {
            guard let any = arr.first else { continue }
            let dates: [Date?] = arr.sorted { ($0.date_start ?? "") < ($1.date_start ?? "") }.map { s in
                if let ds = s.date_start { return ISO8601DateFormatter().date(from: ds) }
                return nil
            }
            let startDate = dates.compactMap { $0 }.first ?? Date()
            let names = arr.sorted { ($0.date_start ?? "") < ($1.date_start ?? "") }.map { Optional($0.session_name) }
            let ev = ScheduleEvent(
                roundNumber: 0, // unknown via OpenF1; display order suffices
                country: any.country_name ?? "",
                location: any.location ?? "",
                eventName: (any.location ?? "") + " Grand Prix",
                eventDate: startDate,
                sessionDatesUTC: Array(dates.prefix(5)),
                sessionNames: Array(names.prefix(5))
            )
            events.append(ev)
        }
        // Sort by start date
        events.sort { $0.eventDate < $1.eventDate }
        return events
    }

    func resolveSessionKey(year: Int, location: String, sessionName: String, countryFallback: String?) async throws -> Int? {
        // Encode session name with spaces preserved via query item
        var comps = URLComponents(url: openF1Base.appending(path: "/sessions"), resolvingAgainstBaseURL: false)!
        var q: [URLQueryItem] = [
            URLQueryItem(name: "session_name", value: sessionName),
            URLQueryItem(name: "year", value: String(year)),
        ]
        // Edge cases: non-ASCII locations Montréal / São Paulo => use country
        let nonAscii = location.unicodeScalars.contains { !$0.isASCII }
        if nonAscii || ["Montréal", "São Paulo"].contains(location) || countryFallback != nil {
            if let country = countryFallback { q.append(URLQueryItem(name: "country_name", value: country)) }
        } else {
            q.append(URLQueryItem(name: "location", value: location))
        }
        comps.queryItems = q
        let res: [OpenF1Session] = try await fetch(comps.url!)
        return res.first?.session_key
    }

    func getSessionResults(sessionKey: Int) async throws -> [OpenF1Result] {
        var comps = URLComponents(url: openF1Base.appending(path: "/session_result"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "session_key", value: String(sessionKey))]
        return try await fetch(comps.url!)
    }

    func getSessionResultsRaw(sessionKey: Int) async throws -> Data {
        var comps = URLComponents(url: openF1Base.appending(path: "/session_result"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "session_key", value: String(sessionKey))]
        return try await fetchData(comps.url!)
    }
}
