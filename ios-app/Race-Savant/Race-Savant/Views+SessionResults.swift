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
            ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                row(for: result)
            }
        }
        .listStyle(.plain)
        .navigationTitle(displayTitle)
        .task { await load() }
        .refreshable { await load(force: true) }
    }

    @ViewBuilder
    private func row(for result: APIService.OpenF1Result) -> some View {
        switch sessionCategory {
        case .practice:
            PracticeSessionResultRow(result: result)
        case .qualifying:
            QualifyingSessionResultRow(result: result)
        case .race:
            RaceSessionResultRow(result: result)
        }
    }

    private var label: String { event.sessionNames[sessionIndex] ?? "Session" }
    private var lowercasedLabel: String { label.lowercased() }

    private enum SessionCategory { case practice, qualifying, race }

    private var sessionCategory: SessionCategory {
        if lowercasedLabel.contains("practice") { return .practice }
        if lowercasedLabel.contains("qualifying") { return .qualifying }
        return .race
    }

    private var displayTitle: String {
        if lowercasedLabel.contains("sprint qualifying") { return "Sprint Qualifying" }
        if lowercasedLabel == "sprint" { return "Sprint" }
        return label
    }

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
                if let resolved = key {
                    LocalStore.saveInt(LocalStore.sessionKeyCacheKey(slug: slug), value: resolved)
                }
            }
            guard let key else { throw URLError(.badURL) }
            // Cache results locally
            if !force, let cached = LocalStore.loadData(LocalStore.sessionResultsKey(sessionKey: key)) {
                let decoded = try JSONDecoder().decode([APIService.OpenF1Result].self, from: cached)
                await MainActor.run {
                    sessionKey = key
                    results = decoded
                }
                return
            }
            // 3) If network available, fetch and persist; otherwise surface cached/empty gracefully
            if let data = try? await APIService.shared.getSessionResultsRaw(sessionKey: key) {
                let decoded = try JSONDecoder().decode([APIService.OpenF1Result].self, from: data)
                await MainActor.run {
                    sessionKey = key
                    results = decoded
                }
                LocalStore.saveData(LocalStore.sessionResultsKey(sessionKey: key), data: data)
                return
            }
            // 4) No network and no cache: show empty state (no hard failure)
            await MainActor.run {
                sessionKey = key
                results = []
            }
        } catch {
            // Be lenient offline: try to render whatever we have, don't block navigation
            await MainActor.run { errorText = error.localizedDescription }
        }
    }

}

extension Array {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
