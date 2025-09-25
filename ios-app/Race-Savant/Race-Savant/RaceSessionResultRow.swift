import SwiftUI

struct RaceSessionResultRow: View {
    let result: APIService.OpenF1Result

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            PositionView(position: result.position)

            VStack(alignment: .leading, spacing: 6) {
                DriverNameView(driverNumber: result.driver_number)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 6) {
                if let points = result.points {
                    Text("\(points)")
                        .font(.headline)
                }
                StatusIndicator(flags: statusFlags)
            }
        }
        .padding(.vertical, 6)
    }

    private var statusFlags: StatusIndicator.Flags {
        StatusIndicator.Flags(
            dnf: result.dnf == true,
            dns: result.dns == true,
            dsq: result.dsq == true
        )
    }
}
