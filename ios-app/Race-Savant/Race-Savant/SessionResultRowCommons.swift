import SwiftUI

struct PositionView: View {
    let position: Int?

    var body: some View {
        Text(positionText)
            .font(.title3.weight(.semibold))
            .frame(width: 36, alignment: .leading)
    }

    private var positionText: String {
        guard let position else { return "-" }
        return String(position)
    }
}

struct DriverNameView: View {
    let driverNumber: Int?

    var body: some View {
        Text(name)
            .fontWeight(.semibold)
    }

    private var name: String {
        guard let driverNumber else { return "#?" }
        if let mapped = DriverRoster.map[driverNumber] { return mapped.fullName }
        return "#\(driverNumber)"
    }
}

enum LapTimeFormatter {
    static func formattedLapTime(from raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.contains(":") { return raw }
        if let seconds = Double(raw) {
            return formattedLapTime(from: seconds)
        }
        return raw
    }

    static func formattedLapTime(from value: Double?) -> String? {
        guard let value else { return nil }
        let minutes = Int(value) / 60
        let remaining = value - Double(minutes * 60)
        let secondsPart = String(format: "%06.3f", remaining)
        return minutes > 0 ? "\(minutes):\(secondsPart)" : String(format: "%.3f", value)
    }

    static func bestLapText(from raw: String) -> String? {
        formattedLapTime(from: raw).map { "Best \($0)" }
    }

    static func bestLapText(from value: Double) -> String? {
        formattedLapTime(from: value).map { "Best \($0)" }
    }
}

struct StatusIndicator: View {
    struct Flags {
        let dnf: Bool
        let dns: Bool
        let dsq: Bool
    }

    let flags: Flags

    var body: some View {
        HStack(spacing: 6) {
            statusBadge("DNF", isActive: flags.dnf)
            statusBadge("DNS", isActive: flags.dns)
            statusBadge("DSQ", isActive: flags.dsq)
        }
    }

    private func statusBadge(_ label: String, isActive: Bool) -> some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(isActive ? Color.red : Color.gray)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background((isActive ? Color.red.opacity(0.15) : Color.gray.opacity(0.12)))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
