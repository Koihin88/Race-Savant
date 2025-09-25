import SwiftUI

struct PracticeSessionResultRow: View {
    let result: APIService.OpenF1Result

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            PositionView(position: result.position)

            VStack(alignment: .leading, spacing: 6) {
                DriverNameView(driverNumber: result.driver_number)
                if let best = bestLapText {
                    Text(best)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 6)
        }
        .padding(.vertical, 6)
    }

    private var bestLapText: String? {
        guard let duration = result.duration else { return nil }
        switch duration {
        case let .str(value):
            return LapTimeFormatter.bestLapText(from: value)
        case let .dbl(value):
            return LapTimeFormatter.bestLapText(from: value)
        default:
            return nil
        }
    }
}
