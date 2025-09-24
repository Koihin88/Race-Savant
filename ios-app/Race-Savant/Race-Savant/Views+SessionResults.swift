import SwiftUI

struct SessionResultsView: View {
    let year: Int
    let event: ScheduleEvent
    let sessionIndex: Int // 0..4 in event arrays

    @State private var sessionKey: Int?
    @State private var results: [APIService.OpenF1Result] = []
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        List {
            if isLoading { ProgressView() }
            if let err = errorText { Text(err).foregroundStyle(.red) }
            ForEach(Array(results.enumerated()), id: \.offset) { idx, r in
                resultRow(r)
            }
        }
        .navigationTitle(event.sessionNames[sessionIndex] ?? "Session")
        .task { await load() }
        .refreshable { await load(force: true) }
    }

    @ViewBuilder
    private func resultRow(_ r: APIService.OpenF1Result) -> some View {
        HStack(alignment: .top) {
            Text("\(r.position ?? 0)")
                .frame(width: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(nameFromNumber(r.driver_number))
                if let dur = r.duration {
                    switch dur {
                    case .str(let s):
                        if isPractice { Text(formatDuration(s)).font(.caption).foregroundStyle(.secondary) }
                    case .arr(let arr):
                        if isQuali {
                            HStack(spacing: 12) {
                                if arr.count > 0, let q1 = arr[0] { Text("Q1 \(formatDuration(q1))").font(.caption) }
                                if arr.count > 1, let q2 = arr[1] { Text("Q2 \(formatDuration(q2))").font(.caption) }
                                if arr.count > 2, let q3 = arr[2] { Text("Q3 \(formatDuration(q3))").font(.caption) }
                            }.foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer()
            if isRace, let pts = r.points { Text("\(pts)") }
            if (r.dnf ?? false) || (r.dns ?? false) || (r.dsq ?? false) {
                Text(statusLabel(r)).font(.caption2).padding(4).background(Color.gray.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private var isPractice: Bool { label.lowercased().contains("practice") }
    private var isQuali: Bool { label.lowercased().contains("qualifying") }
    private var isRace: Bool { label.lowercased().contains("race") || label.lowercased() == "sprint" }
    private var label: String { event.sessionNames[sessionIndex] ?? "Session" }

    private func load(force: Bool = false) async {
        guard !isLoading else { return }
        await MainActor.run { isLoading = true; errorText = nil }
        defer { Task { await MainActor.run { isLoading = false } } }
        do {
            let sessionName = event.sessionNames[sessionIndex] ?? ""
            let countryFallback = ["Montréal": "Canada", "São Paulo": "Brazil"][event.location]
            // 1) Attempt to load session_key from local cache
            let slug = LocalStore.sessionKeySlug(year: year, location: event.location, sessionName: sessionName, countryFallback: countryFallback)
            var key: Int? = LocalStore.loadInt(LocalStore.sessionKeyCacheKey(slug: slug))
            // 2) If not present, resolve via network
            if key == nil {
                key = try? await APIService.shared.resolveSessionKey(year: year, location: event.location, sessionName: sessionName, countryFallback: countryFallback)
                if let kk = key { LocalStore.saveInt(LocalStore.sessionKeyCacheKey(slug: slug), value: kk) }
            }
            guard let key else { throw URLError(.badURL) }
            // Cache results locally
            if !force, let cached = LocalStore.loadData(LocalStore.sessionResultsKey(sessionKey: key)) {
                let res = try JSONDecoder().decode([APIService.OpenF1Result].self, from: cached)
                await MainActor.run { sessionKey = key; results = res }
                return
            }
            // 3) If network available, fetch and persist; otherwise surface cached/empty gracefully
            if let data = try? await APIService.shared.getSessionResultsRaw(sessionKey: key) {
                let res = try JSONDecoder().decode([APIService.OpenF1Result].self, from: data)
                await MainActor.run { sessionKey = key; results = res }
                LocalStore.saveData(LocalStore.sessionResultsKey(sessionKey: key), data: data)
                return
            }
            // 4) No network and no cache: show empty state (no hard failure)
            await MainActor.run { sessionKey = key; results = [] }
        } catch {
            // Be lenient offline: try to render whatever we have, don't block navigation
            await MainActor.run { errorText = error.localizedDescription }
        }
    }

    private func nameFromNumber(_ number: Int?) -> String {
        guard let number else { return "#?" }
        if let m = DriverRoster.map[number] { return m.fullName }
        return "#\(number)"
    }

    private func formatDuration(_ s: String) -> String { s }

    private func statusLabel(_ r: APIService.OpenF1Result) -> String {
        if r.dsq == true { return "DSQ" }
        if r.dnf == true { return "DNF" }
        if r.dns == true { return "DNS" }
        return ""
    }
}

extension Array {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
