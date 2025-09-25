import SwiftUI

struct QualifyingSessionResultRow: View {
    let result: APIService.OpenF1Result

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            PositionView(position: result.position)

            VStack(alignment: .leading, spacing: 6) {
                DriverNameView(driverNumber: result.driver_number)
                if let segments = qualiSegments {
                    HStack(spacing: 18) {
                        ForEach(segments, id: \.label) { segment in
                            Text(segment.value.map { "\(segment.label) \($0)" } ?? " ")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 62, alignment: .leading)
                        }
                    }
                }
            }

            Spacer(minLength: 6)
        }
        .padding(.vertical, 6)
    }

    private var qualiSegments: [(label: String, value: String?)]? {
        guard let duration = result.duration else { return nil }
        switch duration {
        case let .arr(values):
            let q1 = LapTimeFormatter.formattedLapTime(from: values[safe: 0] ?? nil)
            let q2 = LapTimeFormatter.formattedLapTime(from: values[safe: 1] ?? nil)
            let q3 = LapTimeFormatter.formattedLapTime(from: values[safe: 2] ?? nil)
            if q1 == nil && q2 == nil && q3 == nil { return nil }
            return [("Q1", q1), ("Q2", q2), ("Q3", q3)]
        case let .arrD(values):
            let q1 = LapTimeFormatter.formattedLapTime(from: values[safe: 0] ?? nil)
            let q2 = LapTimeFormatter.formattedLapTime(from: values[safe: 1] ?? nil)
            let q3 = LapTimeFormatter.formattedLapTime(from: values[safe: 2] ?? nil)
            if q1 == nil && q2 == nil && q3 == nil { return nil }
            return [("Q1", q1), ("Q2", q2), ("Q3", q3)]
        default:
            return nil
        }
    }
}
