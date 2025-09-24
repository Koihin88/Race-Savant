import SwiftUI
import Charts

struct TelemetryView: View {
    @State private var years: [APIService.YearItem] = []
    @State private var selectedYear: Int?

    @State private var events: [APIService.EventItem] = []
    @State private var selectedEvent: APIService.EventItem?

    @State private var sessions: [APIService.SessionItem] = []
    @State private var selectedSession: APIService.SessionItem?

    @State private var drivers: [APIService.DriverItem] = []
    @State private var selectedDriver: APIService.DriverItem?

    @State private var laps: [APIService.LapItem] = []
    @State private var selectedLap: APIService.LapItem?

    @State private var lapData: APIService.LapTelemetry?
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Select") {
                    Picker("Year", selection: Binding(
                        get: { selectedYear ?? years.last?.year },
                        set: { new in selectedYear = new; Task { await onYearChanged() } }
                    )) {
                        ForEach(years.map { $0.year }, id: \.self) { y in
                            Text("\(y)").tag(Optional(y))
                        }
                    }
                    .disabled(years.isEmpty)

                    Picker("Event", selection: Binding(
                        get: { selectedEvent?.id },
                        set: { id in
                            if let id, let ev = events.first(where: { $0.id == id }) { selectedEvent = ev }
                            else { selectedEvent = nil }
                            Task { await onEventChanged() }
                        }
                    )) {
                        ForEach(events) { ev in
                            Text(ev.name ?? ev.location ?? "Event \(ev.id)").tag(Optional(ev.id))
                        }
                    }
                    .disabled(selectedYear == nil || events.isEmpty)

                    Picker("Session", selection: Binding(
                        get: { selectedSession?.id },
                        set: { id in
                            if let id, let s = sessions.first(where: { $0.id == id }) { selectedSession = s }
                            else { selectedSession = nil }
                            Task { await onSessionChanged() }
                        }
                    )) {
                        ForEach(sessions) { s in
                            Text(s.type ?? "Session").tag(Optional(s.id))
                        }
                    }
                    .disabled(selectedEvent == nil || sessions.isEmpty)

                    Picker("Driver", selection: Binding(
                        get: { selectedDriver?.id },
                        set: { id in
                            if let id, let d = drivers.first(where: { $0.id == id }) { selectedDriver = d }
                            else { selectedDriver = nil }
                            Task { await onDriverChanged() }
                        }
                    )) {
                        ForEach(drivers) { d in
                            Text("\(d.number.map(String.init) ?? "?") \(d.code ?? "")").tag(Optional(d.id))
                        }
                    }
                    .disabled(selectedSession == nil || drivers.isEmpty)

                    Picker("Lap", selection: Binding(
                        get: { selectedLap?.lap_number },
                        set: { num in
                            if let num, let l = laps.first(where: { $0.lap_number == num }) { selectedLap = l }
                            else { selectedLap = nil }
                            Task { await onLapChanged() }
                        }
                    )) {
                        ForEach(laps, id: \.lap_number) { l in
                            Text("\(l.lap_number)").tag(Optional(l.lap_number))
                        }
                    }
                    .disabled(selectedDriver == nil || laps.isEmpty)
                }

                if let ld = lapData {
                    Section("Summary") {
                        HStack { Text("Lap"); Spacer(); Text("\(ld.meta.lap_number)") }
                        HStack { Text("Lap Time (ms)"); Spacer(); Text("\(ld.meta.lap_time_ms ?? 0)") }
                        if let pos = ld.meta.position { HStack { Text("Pos"); Spacer(); Text("\(pos)") } }
                        if let comp = ld.meta.compound { HStack { Text("Tyre"); Spacer(); Text(comp) } }
                    }
                    if #available(iOS 16.0, *) {
                        TelemetryChartsView(data: ld)
                            .frame(minHeight: 300)
                    } else {
                        Text("Charts require iOS 16+")
                    }
                }

                if let err = errorText { Text(err).foregroundStyle(.red) }
            }
            .navigationTitle("Telemetry")
            .task { await bootstrap() }
        }
    }

    // MARK: - Data loading chain
    private func bootstrap() async {
        guard !isLoading else { return }
        await MainActor.run { isLoading = true; errorText = nil }
        defer { Task { await MainActor.run { isLoading = false } } }
        do {
            let ys = try await APIService.shared.getYears()
            await MainActor.run { years = ys; selectedYear = ys.last?.year }
            await onYearChanged()
        } catch { await MainActor.run { errorText = error.localizedDescription } }
    }

    private func onYearChanged() async {
        reset(from: .year)
        guard let y = selectedYear else { return }
        do {
            let evs = try await APIService.shared.getEvents(year: y)
            await MainActor.run {
                events = evs
                selectedEvent = evs.first
            }
            await onEventChanged()
        } catch {
            await MainActor.run { errorText = error.localizedDescription }
        }
    }

    private func onEventChanged() async {
        reset(from: .event)
        guard let ev = selectedEvent else { return }
        do {
            let ss = try await APIService.shared.getSessions(eventId: ev.id)
            await MainActor.run { sessions = ss; selectedSession = ss.first }
            await onSessionChanged()
        } catch { await MainActor.run { errorText = error.localizedDescription } }
    }

    private func onSessionChanged() async {
        reset(from: .session)
        guard let s = selectedSession else { return }
        do {
            let ds = try await APIService.shared.getDrivers(sessionId: s.id)
            await MainActor.run { drivers = ds; selectedDriver = ds.first }
            await onDriverChanged()
        } catch { await MainActor.run { errorText = error.localizedDescription } }
    }

    private func onDriverChanged() async {
        reset(from: .driver)
        guard let s = selectedSession, let d = selectedDriver else { return }
        do {
            let ls = try await APIService.shared.getLaps(sessionId: s.id, driverId: d.id)
            await MainActor.run { laps = ls; selectedLap = ls.first }
            await onLapChanged()
        } catch { await MainActor.run { errorText = error.localizedDescription } }
    }

    private func onLapChanged() async {
        guard let s = selectedSession, let d = selectedDriver, let l = selectedLap else { lapData = nil; return }
        do {
            let ld = try await APIService.shared.getLapTelemetry(sessionId: s.id, driverId: d.id, lapNumber: l.lap_number)
            await MainActor.run { lapData = ld }
        } catch { await MainActor.run { errorText = error.localizedDescription } }
    }

    private enum Level { case year, event, session, driver }
    private func reset(from level: Level) {
        switch level {
        case .year:
            selectedEvent = nil; events = []
            fallthrough
        case .event:
            selectedSession = nil; sessions = []
            fallthrough
        case .session:
            selectedDriver = nil; drivers = []
            fallthrough
        case .driver:
            selectedLap = nil; laps = []; lapData = nil
        }
    }
}

@available(iOS 16.0, *)
private struct TelemetryChartsView: View {
    let data: APIService.LapTelemetry

    private var time: [Double] { data.time_s.compactMap { $0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Speed (km/h)") {
                Chart(Array(time.enumerated()), id: \.0) { idx, t in
                    if let y = data.speed_kmh[safe: idx] ?? nil { LineMark(x: .value("t", t), y: .value("speed", y ?? 0)) }
                }.chartXAxisLabel("Time (s)")
            }
            GroupBox("Throttle (%)") {
                Chart(Array(time.enumerated()), id: \.0) { idx, t in
                    if let y = data.throttle[safe: idx] ?? nil { LineMark(x: .value("t", t), y: .value("throttle", y ?? 0)) }
                }.chartXAxisLabel("Time (s)")
            }
            GroupBox("Brake") {
                Chart(Array(time.enumerated()), id: \.0) { idx, t in
                    let y = (data.brake[safe: idx] ?? nil) ?? false
                    LineMark(x: .value("t", t), y: .value("brake", y ? 1 : 0))
                }.chartXAxisLabel("Time (s)")
            }
            GroupBox("DRS (ON = 10/12/14)") {
                Chart(Array(time.enumerated()), id: \.0) { idx, t in
                    let raw = (data.drs[safe: idx] ?? nil) ?? 0
                    let on = (raw == 10 || raw == 12 || raw == 14) ? 1 : 0
                    LineMark(x: .value("t", t), y: .value("drs", on))
                }.chartXAxisLabel("Time (s)")
            }
        }
    }
}
