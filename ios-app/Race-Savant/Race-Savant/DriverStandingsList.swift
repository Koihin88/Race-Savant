import SwiftUI

struct DriverStandingsList: View {
    let drivers: [DriverStandingItem]

    var body: some View {
        ForEach(drivers) { row in
            HStack {
                Text("\(row.position)")
                    .monospacedDigit()
                    .frame(width: 28, alignment: .leading)
                VStack(alignment: .leading) {
                    Text(driverName(number: row.driverNumber))
                    Text(teamName(number: row.driverNumber))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(row.points)")
                    .monospacedDigit()
                if let wins = Int(row.wins), wins > 0 {
                    Label("\(wins)", systemImage: "trophy.fill")
                        .labelStyle(.titleAndIcon)
                }
            }
        }
    }

    // Mapping from driver number to display info.
    private func driverName(number: String) -> String {
        if let n = Int(number), let m = DriverRoster.map[n] { return m.fullName }
        // When using backend progression, `number` may actually be a code (e.g., VER)
        return number
    }
    private func teamName(number: String) -> String {
        if let n = Int(number), let m = DriverRoster.map[n] { return m.team }
        return ""
    }
}
