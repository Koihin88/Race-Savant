import Foundation

enum HardcodedSchedule2025 {
    private static let iso = ISO8601DateFormatter()

    private static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        // Expecting UTC like "2025-03-14T15:30:00Z" or date-only "2025-03-14"
        if let dt = iso.date(from: s) { return dt }
        // Normalize space-delimited UTC ("YYYY-MM-DD HH:MM:SS") → ISO8601 Zulu
        if s.count == 19 && s.contains(" ") {
            let norm = s.replacingOccurrences(of: " ", with: "T") + "Z"
            if let dt = iso.date(from: norm) { return dt }
        }
        if s.count == 10 { // YYYY-MM-DD → midnight UTC
            return iso.date(from: s + "T00:00:00Z")
        }
        return nil
    }

    private static func make(
        round: Int,
        country: String,
        location: String,
        eventName: String,
        eventDateUTC: String,
        sessionNames: [String?],
        sessionDatesUTC: [String?]
    ) -> ScheduleEvent {
        let sessions = sessionDatesUTC.map { date($0) }
        return ScheduleEvent(
            roundNumber: round,
            country: country,
            location: location,
            eventName: eventName,
            eventDate: date(eventDateUTC) ?? Date(),
            sessionDatesUTC: Array(sessions.prefix(5)),
            sessionNames: Array(sessionNames.prefix(5))
        )
    }

    // TODO: Paste rows from 2025schedule.csv below.
    // Each make(...) corresponds to one Grand Prix weekend.
    // sessionNames should align to the CSV (e.g., "Practice 1", "Practice 2", "Practice 3", "Qualifying"/"Sprint Qualifying", "Race"/"Sprint").
    // sessionDatesUTC are UTC timestamps; UI converts to user's timezone at display.

    static let events: [ScheduleEvent] = [
    make(
        round: 1,
        country: "Australia",
        location: "Melbourne",
        eventName: "Australian Grand Prix",
        eventDateUTC: "2025-03-16",
        sessionNames: ["Practice 1", "Practice 2", "Practice 3", "Qualifying", "Race"],
        sessionDatesUTC: ["2025-03-14 01:30:00", "2025-03-14 05:00:00", "2025-03-15 01:30:00", "2025-03-15 05:00:00", "2025-03-16 04:00:00"]
    ),
    make(
        round: 2,
        country: "China",
        location: "Shanghai",
        eventName: "Chinese Grand Prix",
        eventDateUTC: "2025-03-23",
        sessionNames: ["Practice 1", "Sprint Qualifying", "Sprint", "Qualifying", "Race"],
        sessionDatesUTC: ["2025-03-21 03:30:00", "2025-03-21 07:30:00", "2025-03-22 03:00:00", "2025-03-22 07:00:00", "2025-03-23 07:00:00"]
    ),
    make(
        round: 3,
        country: "Japan",
        location: "Suzuka",
        eventName: "Japanese Grand Prix",
        eventDateUTC: "2025-04-06",
        sessionNames: ["Practice 1", "Practice 2", "Practice 3", "Qualifying", "Race"],
        sessionDatesUTC: ["2025-04-04 02:30:00", "2025-04-04 06:00:00", "2025-04-05 02:30:00", "2025-04-05 06:00:00", "2025-04-06 05:00:00"]
    ),
    make(
        round: 4,
        country: "Bahrain",
        location: "Sakhir",
        eventName: "Bahrain Grand Prix",
        eventDateUTC: "2025-04-13",
        sessionNames: ["Practice 1", "Practice 2", "Practice 3", "Qualifying", "Race"],
        sessionDatesUTC: ["2025-04-11 11:30:00", "2025-04-11 15:00:00", "2025-04-12 12:30:00", "2025-04-12 16:00:00", "2025-04-13 15:00:00"]
    ),
    make(
        round: 5,
        country: "Saudi Arabia",
        location: "Jeddah",
        eventName: "Saudi Arabian Grand Prix",
        eventDateUTC: "2025-04-20",
        sessionNames: ["Practice 1", "Practice 2", "Practice 3", "Qualifying", "Race"],
        sessionDatesUTC: ["2025-04-18 13:30:00", "2025-04-18 17:00:00", "2025-04-19 13:30:00", "2025-04-19 17:00:00", "2025-04-20 17:00:00"]
    ),
    make(
        round: 6,
        country: "United States",
        location: "Miami",
        eventName: "Miami Grand Prix",
        eventDateUTC: "2025-05-04",
        sessionNames: ["Practice 1", "Sprint Qualifying", "Sprint", "Qualifying", "Race"],
        sessionDatesUTC: ["2025-05-02 16:30:00", "2025-05-02 20:30:00", "2025-05-03 16:00:00", "2025-05-03 20:00:00", "2025-05-04 20:00:00"]
    ),
    make(
        round: 7,
        country: "Italy",
        location: "Imola",
        eventName: "Emilia Romagna Grand Prix",
        eventDateUTC: "2025-05-18",
        sessionNames: ["Practice 1", "Practice 2", "Practice 3", "Qualifying", "Race"],
        sessionDatesUTC: ["2025-05-16 11:30:00", "2025-05-16 15:00:00", "2025-05-17 10:30:00", "2025-05-17 14:00:00", "2025-05-18 13:00:00"]
    ),
    make(
        round: 8,
        country: "Monaco",
        location: "Monaco",
        eventName: "Monaco Grand Prix",
        eventDateUTC: "2025-05-25",
        sessionNames: ["Practice 1", "Practice 2", "Practice 3", "Qualifying", "Race"],
        sessionDatesUTC: ["2025-05-23 11:30:00", "2025-05-23 15:00:00", "2025-05-24 10:30:00", "2025-05-24 14:00:00", "2025-05-25 13:00:00"]
    ),
    make(
        round: 9,
        country: "Spain",
        location: "Barcelona",
        eventName: "Spanish Grand Prix",
        eventDateUTC: "2025-06-01",
        sessionNames: ["Practice 1", "Practice 2", "Practice 3", "Qualifying", "Race"],
        sessionDatesUTC: ["2025-05-30 11:30:00", "2025-05-30 15:00:00", "2025-05-31 10:30:00", "2025-05-31 14:00:00", "2025-06-01 13:00:00"]
    ),
    make(
        round: 10,
        country: "Canada",
        location: "Montréal",
        eventName: "Canadian Grand Prix",
        eventDateUTC: "2025-06-15",
        sessionNames: ["Practice 1", "Practice 2", "Practice 3", "Qualifying", "Race"],
        sessionDatesUTC: ["2025-06-13 17:30:00", "2025-06-13 21:00:00", "2025-06-14 16:30:00", "2025-06-14 20:00:00", "2025-06-15 18:00:00"]
    ),
    make(
        round: 11,
        country: "Austria",
        location: "Spielberg",
        eventName: "Austrian Grand Prix",
        eventDateUTC: "2025-06-29",
        sessionNames: ["Practice 1", "Practice 2", "Practice 3", "Qualifying", "Race"],
        sessionDatesUTC: ["2025-06-27 11:30:00", "2025-06-27 15:00:00", "2025-06-28 10:30:00", "2025-06-28 14:00:00", "2025-06-29 13:00:00"]
    ),
    make(
        round: 12,
        country: "United Kingdom",
        location: "Silverstone",
        eventName: "British Grand Prix",
        eventDateUTC: "2025-07-06",
        sessionNames: ["Practice 1", "Practice 2", "Practice 3", "Qualifying", "Race"],
        sessionDatesUTC: ["2025-07-04 11:30:00", "2025-07-04 15:00:00", "2025-07-05 10:30:00", "2025-07-05 14:00:00", "2025-07-06 14:00:00"]
    ),
    make(
        round: 13,
        country: "Belgium",
        location: "Spa-Francorchamps",
        eventName: "Belgian Grand Prix",
        eventDateUTC: "2025-07-27",
        sessionNames: ["Practice 1", "Sprint Qualifying", "Sprint", "Qualifying", "Race"],
        sessionDatesUTC: ["2025-07-25 10:30:00", "2025-07-25 14:30:00", "2025-07-26 10:00:00", "2025-07-26 14:00:00", "2025-07-27 13:00:00"]
    ),
    make(
        round: 14,
        country: "Hungary",
        location: "Budapest",
        eventName: "Hungarian Grand Prix",
        eventDateUTC: "2025-08-03",
        sessionNames: ["Practice 1", "Practice 2", "Practice 3", "Qualifying", "Race"],
        sessionDatesUTC: ["2025-08-01 11:30:00", "2025-08-01 15:00:00", "2025-08-02 10:30:00", "2025-08-02 14:00:00", "2025-08-03 13:00:00"]
    ),
    make(
        round: 15,
        country: "Netherlands",
        location: "Zandvoort",
        eventName: "Dutch Grand Prix",
        eventDateUTC: "2025-08-31",
        sessionNames: ["Practice 1", "Practice 2", "Practice 3", "Qualifying", "Race"],
        sessionDatesUTC: ["2025-08-29 10:30:00", "2025-08-29 14:00:00", "2025-08-30 09:30:00", "2025-08-30 13:00:00", "2025-08-31 13:00:00"]
    ),
    make(
        round: 16,
        country: "Italy",
        location: "Monza",
        eventName: "Italian Grand Prix",
        eventDateUTC: "2025-09-07",
        sessionNames: ["Practice 1", "Practice 2", "Practice 3", "Qualifying", "Race"],
        sessionDatesUTC: ["2025-09-05 11:30:00", "2025-09-05 15:00:00", "2025-09-06 10:30:00", "2025-09-06 14:00:00", "2025-09-07 13:00:00"]
    ),
    make(
        round: 17,
        country: "Azerbaijan",
        location: "Baku",
        eventName: "Azerbaijan Grand Prix",
        eventDateUTC: "2025-09-21",
        sessionNames: ["Practice 1", "Practice 2", "Practice 3", "Qualifying", "Race"],
        sessionDatesUTC: ["2025-09-19 08:30:00", "2025-09-19 12:00:00", "2025-09-20 08:30:00", "2025-09-20 12:00:00", "2025-09-21 11:00:00"]
    ),
    make(
        round: 18,
        country: "Singapore",
        location: "Marina Bay",
        eventName: "Singapore Grand Prix",
        eventDateUTC: "2025-10-05",
        sessionNames: ["Practice 1", "Practice 2", "Practice 3", "Qualifying", "Race"],
        sessionDatesUTC: ["2025-10-03 09:30:00", "2025-10-03 13:00:00", "2025-10-04 09:30:00", "2025-10-04 13:00:00", "2025-10-05 12:00:00"]
    ),
    make(
        round: 19,
        country: "United States",
        location: "Austin",
        eventName: "United States Grand Prix",
        eventDateUTC: "2025-10-19",
        sessionNames: ["Practice 1", "Sprint Qualifying", "Sprint", "Qualifying", "Race"],
        sessionDatesUTC: ["2025-10-17 17:30:00", "2025-10-17 21:30:00", "2025-10-18 17:00:00", "2025-10-18 21:00:00", "2025-10-19 19:00:00"]
    ),
    make(
        round: 20,
        country: "Mexico",
        location: "Mexico City",
        eventName: "Mexico City Grand Prix",
        eventDateUTC: "2025-10-26",
        sessionNames: ["Practice 1", "Practice 2", "Practice 3", "Qualifying", "Race"],
        sessionDatesUTC: ["2025-10-24 18:30:00", "2025-10-24 22:00:00", "2025-10-25 17:30:00", "2025-10-25 21:00:00", "2025-10-26 20:00:00"]
    ),
    make(
        round: 21,
        country: "Brazil",
        location: "São Paulo",
        eventName: "São Paulo Grand Prix",
        eventDateUTC: "2025-11-09",
        sessionNames: ["Practice 1", "Sprint Qualifying", "Sprint", "Qualifying", "Race"],
        sessionDatesUTC: ["2025-11-07 14:30:00", "2025-11-07 18:30:00", "2025-11-08 14:00:00", "2025-11-08 18:00:00", "2025-11-09 17:00:00"]
    ),
    make(
        round: 22,
        country: "United States",
        location: "Las Vegas",
        eventName: "Las Vegas Grand Prix",
        eventDateUTC: "2025-11-22",
        sessionNames: ["Practice 1", "Practice 2", "Practice 3", "Qualifying", "Race"],
        sessionDatesUTC: ["2025-11-21 00:30:00", "2025-11-21 04:00:00", "2025-11-22 00:30:00", "2025-11-22 04:00:00", "2025-11-23 04:00:00"]
    ),
    make(
        round: 23,
        country: "Qatar",
        location: "Lusail",
        eventName: "Qatar Grand Prix",
        eventDateUTC: "2025-11-30",
        sessionNames: ["Practice 1", "Sprint Qualifying", "Sprint", "Qualifying", "Race"],
        sessionDatesUTC: ["2025-11-28 13:30:00", "2025-11-28 17:30:00", "2025-11-29 14:00:00", "2025-11-29 18:00:00", "2025-11-30 16:00:00"]
    ),
    make(
        round: 24,
        country: "United Arab Emirates",
        location: "Yas Island",
        eventName: "Abu Dhabi Grand Prix",
        eventDateUTC: "2025-12-07",
        sessionNames: ["Practice 1", "Practice 2", "Practice 3", "Qualifying", "Race"],
        sessionDatesUTC: ["2025-12-05 09:30:00", "2025-12-05 13:00:00", "2025-12-06 10:30:00", "2025-12-06 14:00:00", "2025-12-07 13:00:00"]
    ),
    ]
}
