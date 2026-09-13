import SwiftUI

/// Deliberate per-row synchronous stalls during scrolling. `hitchTime` is a
/// continuous daily ratio of janky-to-total animation time, not a discrete
/// trigger, so this only ever *contributes* real jank - actually scroll up
/// and down repeatedly for it to matter, don't just load the screen once.
struct ScrollJankView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 0) {
      Text(
        "Scroll up and down repeatedly - contributes to hitchTime, won't show up until MetricKit's next daily report."
      )
      .font(.caption)
      .padding(8)
      .frame(maxWidth: .infinity)
      .background(.yellow.opacity(0.25))

      List(0..<200, id: \.self) { i in
        Text("Row \(i)")
          .onAppear {
            guard i % 5 == 0 else { return }
            // Deliberate synchronous stall on the main thread while scrolling
            // - this is what real jank looks like to MetricKit.
            Thread.sleep(forTimeInterval: 0.04)
          }
      }

      Button("Done") { dismiss() }
        .buttonStyle(.borderedProminent)
        .padding()
    }
  }
}

#Preview {
  ScrollJankView()
}
