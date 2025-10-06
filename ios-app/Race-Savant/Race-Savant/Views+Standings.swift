import SwiftUI

struct StandingsView: View {
    enum StandingsSegment: String, CaseIterable { case drivers = "Drivers"; case constructors = "Constructors" }
    @State private var segment: StandingsSegment = .drivers
    @State private var drivers: [DriverStandingItem] = []
    @State private var constructors: [ConstructorStandingItem] = []
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack {
                Picker("Standings", selection: $segment) {
                    ForEach(StandingsSegment.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])

                if isLoading { ProgressView().padding() }
                if let err = errorText { Text(err).foregroundStyle(.red) }

                List {
                    if segment == .drivers {
                        DriverStandingsList(drivers: drivers)
                    } else {
                        ConstructorStandingsList(constructors: constructors)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Standings")
            .task { await load() }
            .refreshable { await load(force: true) }
        }
    }

    private func load(force: Bool = false) async {
        guard !isLoading else { return }
        await MainActor.run { isLoading = true; errorText = nil }
        defer { Task { await MainActor.run { isLoading = false } } }
        // Year hardcoded to 2025 per endpoint; cache whole payloads
        if !force {
            if let d: [DriverStandingItem] = LocalStore.load(LocalStore.driverStandingsKey(year: 2025)) {
                await MainActor.run { drivers = d }
            }
            if let c: [ConstructorStandingItem] = LocalStore.load(LocalStore.constructorStandingsKey(year: 2025)) {
                await MainActor.run { constructors = c }
            }
            if !drivers.isEmpty && !constructors.isEmpty { return }
        }
        do {
            async let d: [DriverStandingItem] = APIService.shared.getDriverStandings()
            async let c: [ConstructorStandingItem] = APIService.shared.getConstructorStandings()
            let (sd, sc) = try await (d, c)
            await MainActor.run { drivers = sd; constructors = sc }
            LocalStore.save(LocalStore.driverStandingsKey(year: 2025), value: sd)
            LocalStore.save(LocalStore.constructorStandingsKey(year: 2025), value: sc)
        } catch {
            await MainActor.run { errorText = error.localizedDescription }
        }
    }

}
