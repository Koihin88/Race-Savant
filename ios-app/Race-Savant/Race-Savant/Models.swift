import Foundation

// Minimal local models and caches for Home/Standings per requirements.

struct ScheduleEvent: Identifiable, Codable, Equatable, Hashable {
    let id: UUID = UUID()
    let roundNumber: Int
    let country: String
    let location: String
    let eventName: String
    let eventDate: Date
    let sessionDatesUTC: [Date?] // up to 5
    let sessionNames: [String?]  // matching ordering, e.g., "Practice 1", "Qualifying", "Race"
}

struct DriverStandingItem: Identifiable, Codable, Equatable {
    let id: UUID = UUID()
    let position: Int
    let points: String
    let wins: String
    let driverNumber: String
}

struct ConstructorStandingItem: Identifiable, Codable, Equatable {
    let id: UUID = UUID()
    let position: String
    let points: String
    let wins: String
    let name: String
}

struct DriverMapEntry: Codable {
    let number: Int
    let code: String
    let fullName: String
    let team: String
    let colorHex: String
}

enum Segment: String, CaseIterable { case past = "Past", upcoming = "Upcoming" }

enum CountryFlags {
    static func emoji(for country: String) -> String {
        switch country {
        case "Australia": return "🇦🇺"
        case "China": return "🇨🇳"
        case "Japan": return "🇯🇵"
        case "Bahrain": return "🇧🇭"
        case "Saudi Arabia": return "🇸🇦"
        case "United States": return "🇺🇸"
        case "Italy": return "🇮🇹"
        case "Monaco": return "🇲🇨"
        case "Spain": return "🇪🇸"
        case "Canada": return "🇨🇦"
        case "Austria": return "🇦🇹"
        case "United Kingdom": return "🇬🇧"
        case "Belgium": return "🇧🇪"
        case "Hungary": return "🇭🇺"
        case "Netherlands": return "🇳🇱"
        case "Azerbaijan": return "🇦🇿"
        case "Singapore": return "🇸🇬"
        case "Mexico": return "🇲🇽"
        case "Brazil": return "🇧🇷"
        case "Qatar": return "🇶🇦"
        case "United Arab Emirates": return "🇦🇪"
        default: return "🏁"
        }
    }
}

enum DriverRoster {
    static let map: [Int: DriverMapEntry] = [
        4:  .init(number: 4,  code: "NOR", fullName: "Lando Norris",        team: "McLaren",         colorHex: "#FF8000"),
        81: .init(number: 81, code: "PIA", fullName: "Oscar Piastri",       team: "McLaren",         colorHex: "#FF8000"),
        1:  .init(number: 1,  code: "VER", fullName: "Max Verstappen",      team: "Red Bull Racing", colorHex: "#3671C6"),
        33:  .init(number: 1,  code: "VER", fullName: "Max Verstappen",      team: "Red Bull Racing", colorHex: "#3671C6"),
        63: .init(number: 63, code: "RUS", fullName: "George Russell",      team: "Mercedes",        colorHex: "#27F4D2"),
        22: .init(number: 22, code: "TSU", fullName: "Yuki Tsunoda",       team: "Racing Bulls",    colorHex: "#6692FF"),
        23: .init(number: 23, code: "ALB", fullName: "Alexander Albon",    team: "Williams",        colorHex: "#64C4FF"),
        16: .init(number: 16, code: "LEC", fullName: "Charles Leclerc",     team: "Ferrari",         colorHex: "#E80020"),
        44: .init(number: 44, code: "HAM", fullName: "Lewis Hamilton",      team: "Ferrari",         colorHex: "#E80020"),
        10: .init(number: 10, code: "GAS", fullName: "Pierre Gasly",        team: "Alpine",          colorHex: "#0093CC"),
        55: .init(number: 55, code: "SAI", fullName: "Carlos Sainz",        team: "Williams",        colorHex: "#64C4FF"),
        6:  .init(number: 6,  code: "HAD", fullName: "Isack Hadjar",        team: "Racing Bulls",    colorHex: "#6692FF"),
        14: .init(number: 14, code: "ALO", fullName: "Fernando Alonso",     team: "Aston Martin",    colorHex: "#229971"),
        18: .init(number: 18, code: "STR", fullName: "Lance Stroll",        team: "Aston Martin",    colorHex: "#229971"),
        7:  .init(number: 7,  code: "DOO", fullName: "Jack Doohan",         team: "Alpine",          colorHex: "#0093CC"),
        43:  .init(number: 43,  code: "COL", fullName: "Franco Colapinto",    team: "Alpine",          colorHex: "#0093CC"),
        5:  .init(number: 5,  code: "BOR", fullName: "Gabriel Bortoleto",   team: "Kick Sauber",     colorHex: "#52E252"),
        12: .init(number: 12, code: "ANT", fullName: "Andrea Kimi Antonelli", team: "Mercedes",      colorHex: "#27F4D2"),
        27: .init(number: 27, code: "HUL", fullName: "Nico Hulkenberg",     team: "Kick Sauber",     colorHex: "#52E252"),
        30: .init(number: 30, code: "LAW", fullName: "Liam Lawson",         team: "Red Bull Racing", colorHex: "#3671C6"),
        31: .init(number: 31, code: "OCO", fullName: "Esteban Ocon",        team: "Haas F1 Team",    colorHex: "#B6BABD"),
        87: .init(number: 87, code: "BEA", fullName: "Oliver Bearman",      team: "Haas F1 Team",    colorHex: "#B6BABD"),
    ]
}

// Navigation value for session selection to avoid tuple Hashable inference issues
struct EventSessionNavigation: Hashable {
    let event: ScheduleEvent
    let index: Int
}
