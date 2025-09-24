import SwiftUI

struct HomeView: View {
    @State private var selectedSegment: Segment = .upcoming
    @State private var year: Int = Calendar.current.component(.year, from: Date())
    @State private var events: [ScheduleEvent] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @StateObject private var net = NetworkMonitor.shared

    var body: some View {
        NavigationStack {
            VStack {
                Picker("Segment", selection: $selectedSegment) {
                    Text(Segment.upcoming.rawValue).tag(Segment.upcoming)
                    Text(Segment.past.rawValue).tag(Segment.past)
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])

                if isLoading {
                    ProgressView().padding()
                }
                if let err = errorText { Text(err).foregroundStyle(.red).padding(.horizontal) }

                List(filteredEvents) { ev in
                    NavigationLink(value: ev) {
                        EventCard(event: ev)
                    }
                }
                .listStyle(.plain)
            }
            .navigationDestination(for: ScheduleEvent.self) { ev in
                EventDetailView(event: ev)
            }
            .navigationDestination(for: EventSessionNav.self) { nav in
                SessionResultsView(year: Calendar.current.component(.year, from: Date()), event: nav.event, sessionIndex: nav.index)
            }
            .navigationTitle("Home")
            .task { await loadSchedule() }
            .refreshable { await loadSchedule(force: true) }
        }
    }

    private var filteredEvents: [ScheduleEvent] {
        let now = Date()
        var list = events.filter { ev in
            if selectedSegment == .past { return ev.eventDate < now }
            return ev.eventDate >= now
        }
        if selectedSegment == .past {
            list.sort { $0.eventDate > $1.eventDate }
        } else {
            list.sort { $0.eventDate < $1.eventDate }
        }
        return list
    }

    private func loadSchedule(force: Bool = false) async {
        guard !isLoading else { return }
        await MainActor.run { isLoading = true; errorText = nil }
        defer { Task { await MainActor.run { isLoading = false } } }
        // Try cache first
        if !force, let cached: [ScheduleEvent] = LocalStore.load(LocalStore.scheduleKey(year: year)) {
            await MainActor.run { events = cached }
            return
        }
        // 2025 is hardcoded
        if year == 2025 {
            let evs = HardcodedSchedule2025.events
            await MainActor.run { events = evs }
            LocalStore.save(LocalStore.scheduleKey(year: year), value: evs)
            return
        }
        // Fallback for other years (dev/testing): fetch from backend Fast‑F1 schedule passthrough
        do {
            let evs = try await APIService.shared.getSchedule(year: year)
            await MainActor.run { events = evs }
            LocalStore.save(LocalStore.scheduleKey(year: year), value: evs)
        } catch {
            await MainActor.run { errorText = error.localizedDescription }
        }
    }
}

private struct EventCard: View {
    let event: ScheduleEvent

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(CountryFlags.emoji(for: event.country))
                    Text("Round \(event.roundNumber) · \(event.country)")
                }
                .font(.headline)
                Text(event.eventName).font(.subheadline)
                Text(dateRangeString(event.eventDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private func dateRangeString(_ start: Date) -> String {
        let cal = Calendar.current
        if let end = cal.date(byAdding: .day, value: 2, to: start) {
            let f = DateFormatter()
            f.dateFormat = "MM-dd"
            return "\(f.string(from: start)) to \(f.string(from: end))"
        }
        return ""
    }
}

private struct EventDetailView: View {
    let event: ScheduleEvent

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Round \(event.roundNumber)")
                        .font(.headline)
                    Text("\(event.eventName) · \(event.location)")
                        .font(.subheadline)
                }
                .padding(.vertical, 4)
            }
            Section("Sessions") {
                ForEach(Array(sessionRows.enumerated()), id: \.offset) { idx, row in
                    let isFuture = row.date > Date()
                    NavigationLink(value: EventSessionNav(event: event, index: idx)) {
                        HStack {
                            Text(row.label)
                            Spacer()
                            Text(localTimeString(row.date))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(isFuture)
                    .opacity(isFuture ? 0.5 : 1.0)
                }
            }
        }
        .navigationTitle(event.eventName)
    }

    private var sessionRows: [(label: String, date: Date)] {
        var out: [(String, Date)] = []
        for i in 0..<min(event.sessionDatesUTC.count, event.sessionNames.count) {
            if let d = event.sessionDatesUTC[i], let name = event.sessionNames[i] { out.append((name, d)) }
        }
        return out
    }

    private func localTimeString(_ utc: Date) -> String {
        let fmt = DateFormatter()
        fmt.timeZone = .current
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        return fmt.string(from: utc)
    }
}

// MARK: - Interactivity and offline/time sanity handling

extension HomeView {
    // Sessions are clickable only if event has at least one past session based on current time
    // We also grey out if offline and no cached results for that event exist (best-effort heuristic)
    func isEventInteractable(_ ev: ScheduleEvent) -> Bool {
        // If upcoming segment is selected, disable
        if selectedSegment == .upcoming { return false }
        // If device time seems off (far from UTC), rely on cache presence
        if deviceTimeSuspicious() || !net.isOnline {
            return hasAnyCachedResult(for: ev)
        }
        // Otherwise enable if any session date is in the past
        let now = Date()
        return ev.sessionDatesUTC.contains { d in
            if let d { return d <= now } else { return false }
        }
    }

    private func deviceTimeSuspicious() -> Bool {
        // Heuristic: compare device time to a reference derived from known UTC event dates.
        // If median delta exceeds 6 hours, consider clock suspicious.
        let sample = HardcodedSchedule2025.events.prefix(3).compactMap { $0.sessionDatesUTC.first ?? nil }
        guard !sample.isEmpty else { return false }
        let now = Date()
        let deltas = sample.map { abs(now.timeIntervalSince($0)) }
        let sorted = deltas.sorted()
        let median = sorted[sorted.count/2]
        return median > 6 * 3600
    }

    private func hasAnyCachedResult(for ev: ScheduleEvent) -> Bool {
        // Check if any of the session results for this event was cached previously
        for i in 0..<min(ev.sessionNames.count, ev.sessionDatesUTC.count) {
            guard let name = ev.sessionNames[i] else { continue }
            // Attempt session key resolution rules quickly
            let countryFallback = ["Montréal": "Canada", "São Paulo": "Brazil"][ev.location]
            // We cannot resolve key synchronously here; just check any local files that match pattern
            // This is a heuristic fallback; the SessionResults view resolves and caches per selection.
            // If any cached file exists, consider event interactable while offline.
            // session_key unknown → we cannot know exact filename, so return false by default.
            _ = (name, countryFallback) // keep vars used; actual cache check requires key
        }
        return false
    }
}
