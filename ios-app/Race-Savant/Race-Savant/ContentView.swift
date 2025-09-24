//
//  ContentView.swift
//  Race-Savant
//
//  Created by Koihin Wong on 9/7/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
            StandingsView()
                .tabItem { Label("Standings", systemImage: "list.number") }
            TelemetryView()
                .tabItem { Label("Telemetry", systemImage: "waveform") }
        }
    }
}

#Preview { ContentView() }
