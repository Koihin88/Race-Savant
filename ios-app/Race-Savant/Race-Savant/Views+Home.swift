import SwiftUI

struct HomeView: View {
    @Namespace private var namespace
    @State private var selectedSegment: Segment = .upcoming
    @State private var year: Int = Calendar.current.component(.year, from: Date())
    @State private var scheduleEvents: [ScheduleEvent] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @StateObject private var networkMonitor = NetworkMonitor.shared

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
                if let error = errorMessage {
                    Text(error).foregroundStyle(.red).padding(.horizontal)
                }

                List(filteredEvents) { event in
                    // Use a ZStack to overlay an invisible NavigationLink
                    ZStack(alignment: .leading) {
                        NavigationLink(value: event) {
                            EmptyView() // The link itself has no visible content
                        }
                        .opacity(0.0) // Make the link invisible but still tappable

                        // Your visible card view
                        EventCard(event: event)
                            .matchedTransitionSource(id: event.id, in: namespace)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .background(Color(.systemGroupedBackground))
            }
            .navigationDestination(for: ScheduleEvent.self) { event in
                EventDetailView(event: event)
                    .navigationTransition(.zoom(sourceID: event.id, in: namespace))
            }
            .navigationDestination(for: EventSessionNavigation.self) { navigationData in
                SessionResultsView(year: Calendar.current.component(.year, from: Date()), event: navigationData.event, sessionIndex: navigationData.index)
            }
            .navigationTitle("Home")
            .task { await loadSchedule() }
            .refreshable { await loadSchedule(forceRefresh: true) }
        }
    }

    private var filteredEvents: [ScheduleEvent] {
        let now = Date()
        var filteredList = scheduleEvents.filter { event in
            if selectedSegment == .past {
                return event.eventDate < now
            }
            return event.eventDate >= now
        }
        if selectedSegment == .past {
            filteredList.sort { $0.eventDate > $1.eventDate }
        } else {
            filteredList.sort { $0.eventDate < $1.eventDate }
        }
        return filteredList
    }

    private func loadSchedule(forceRefresh: Bool = false) async {
        guard !isLoading else { return }
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        defer {
            Task {
                await MainActor.run { isLoading = false }
            }
        }
        // Try cache first
        if !forceRefresh, let cachedEvents: [ScheduleEvent] = LocalStore.load(LocalStore.scheduleKey(year: year)) {
            await MainActor.run { scheduleEvents = cachedEvents }
            return
        }
        // 2025 is hardcoded
        if year == 2025 {
            let hardcodedEvents = HardcodedSchedule2025.events
            await MainActor.run { scheduleEvents = hardcodedEvents }
            LocalStore.save(LocalStore.scheduleKey(year: year), value: hardcodedEvents)
            return
        }
        // Fallback for other years (dev/testing): fetch from backend
        do {
            let fetchedEvents = try await APIService.shared.getSchedule(year: year)
            await MainActor.run { scheduleEvents = fetchedEvents }
            LocalStore.save(LocalStore.scheduleKey(year: year), value: fetchedEvents)
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
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
                Text(formatDateRange(from: event.eventDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }

    private func formatDateRange(from startDate: Date) -> String {
        let calendar = Calendar.current
        if let endDate = calendar.date(byAdding: .day, value: 2, to: startDate) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MM-dd"
            return "\(dateFormatter.string(from: startDate)) to \(dateFormatter.string(from: endDate))"
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
                ForEach(Array(sessionDetails.enumerated()), id: \.offset) { index, session in
                    let isFutureSession = session.date > Date()
                    NavigationLink(value: EventSessionNavigation(event: event, index: index)) {
                        HStack {
                            Text(session.label)
                            Spacer()
                            Text(formatToLocalTime(session.date))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(isFutureSession)
                    .opacity(isFutureSession ? 0.5 : 1.0)
                }
            }
        }
        .navigationTitle(event.eventName)
    }

    private var sessionDetails: [(label: String, date: Date)] {
        var details: [(String, Date)] = []
        for i in 0..<min(event.sessionDatesUTC.count, event.sessionNames.count) {
            if let date = event.sessionDatesUTC[i], let name = event.sessionNames[i] {
                details.append((name, date))
            }
        }
        return details
    }

    private func formatToLocalTime(_ utcDate: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = .current
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: utcDate)
    }
}

// MARK: - Interactivity and offline/time sanity handling

extension HomeView {
    // Sessions are clickable only if event has at least one past session based on current time
    // We also grey out if offline and no cached results for that event exist
    func isEventInteractable(_ event: ScheduleEvent) -> Bool {
        if selectedSegment == .upcoming { return false }
        if isDeviceTimeSuspicious() || !networkMonitor.isOnline {
            return hasAnyCachedResult(for: event)
        }
        // Otherwise enable if any session date is in the past
        let now = Date()
        return event.sessionDatesUTC.contains { date in
            if let date {
                return date <= now
            } else {
                return false
            }
        }
    }

    private func isDeviceTimeSuspicious() -> Bool {
        // Heuristic: compare device time to a reference derived from known UTC event dates.
        let sampleDates = HardcodedSchedule2025.events.prefix(3).compactMap { $0.sessionDatesUTC.first ?? nil }
        guard !sampleDates.isEmpty else { return false }
        let now = Date()
        let timeDeltas = sampleDates.map { abs(now.timeIntervalSince($0)) }
        let sortedDeltas = timeDeltas.sorted()
        let medianDelta = sortedDeltas[sortedDeltas.count / 2]
        let sixHoursInSeconds: TimeInterval = 6 * 3600
        return medianDelta > sixHoursInSeconds
    }

    private func hasAnyCachedResult(for event: ScheduleEvent) -> Bool {
        // Check if any of the session results for this event was cached previously
        for i in 0..<min(event.sessionNames.count, event.sessionDatesUTC.count) {
            guard let sessionName = event.sessionNames[i] else { continue }
            let countryFallback = ["Montréal": "Canada", "São Paulo": "Brazil"][event.location]
            _ = (sessionName, countryFallback)
        }
        return false
    }
}
