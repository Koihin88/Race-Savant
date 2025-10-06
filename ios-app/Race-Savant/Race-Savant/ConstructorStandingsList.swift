import SwiftUI

struct ConstructorStandingsList: View {
    let constructors: [ConstructorStandingItem]

    var body: some View {
        ForEach(constructors) { row in
            HStack {
                Text(row.position).frame(width: 28, alignment: .leading)
                Text(row.name)
                Spacer()
                if let wins = Int(row.wins), wins > 0 {
                    Label("\(wins)", systemImage: "trophy.fill")
                        .labelStyle(.titleAndIcon)
                }
                Text("\(row.points)")
                    .monospacedDigit()
            }
        }
    }
}

