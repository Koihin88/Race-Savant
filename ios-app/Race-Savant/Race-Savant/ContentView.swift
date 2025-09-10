//
//  ContentView.swift
//  Race-Savant
//
//  Created by Koihin Wong on 9/7/25.
//

import SwiftUI

struct ContentView: View {
    @State private var message: String = "Loading…"
    @State private var isLoading: Bool = false

    private let apiURL = URL(string: "http://127.0.0.1:8000/")!

    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            if isLoading {
                ProgressView()
                    .padding(.bottom, 8)
            }
            Text(message)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            Button("Refresh") { Task { await fetchMessage() } }
                .padding(.top, 12)
        }
        .padding()
        .task { await fetchMessage() }
    }

    private func fetchMessage() async {
        guard !isLoading else { return }
        await MainActor.run { isLoading = true }
        defer { Task { await MainActor.run { isLoading = false } } }

        struct HelloResponse: Decodable { let message: String }

        do {
            let (data, response) = try await URLSession.shared.data(from: apiURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let decoded = try JSONDecoder().decode(HelloResponse.self, from: data)
            await MainActor.run { message = decoded.message }
        } catch {
            await MainActor.run { message = "Failed to fetch message: \(error.localizedDescription)" }
        }
    }
}

#Preview {
    ContentView()
}
