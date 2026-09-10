import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("HitchScope Example")
                .font(.headline)
            Text("Used for exercising local SDK changes on a simulator.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
}

#Preview {
    ContentView()
}
