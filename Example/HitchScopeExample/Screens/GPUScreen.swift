import SwiftUI

/// Sustained GPU-heavy rendering. `gpuTime` is a continuous daily aggregate,
/// not a discrete trigger, so this only ever *contributes* real GPU work -
/// stay on this screen for a couple of minutes for it to matter.
struct GPUScreen: View {
    private let entry = MetricCatalog.entry(for: "gpu")

    var body: some View {
        ZStack {
            TimelineView(.animation) { context in
                Canvas { ctx, size in
                    let time = context.date.timeIntervalSinceReferenceDate
                    for i in 0..<400 {
                        let angle = time + Double(i) * 0.15
                        let radius = size.width / 2 * (0.3 + 0.5 * abs(sin(time * 0.3 + Double(i))))
                        let x = size.width / 2 + cos(angle) * radius
                        let y = size.height / 2 + sin(angle) * radius
                        let hue = (Double(i) / 400 + time * 0.1).truncatingRemainder(dividingBy: 1)
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: x - 8, y: y - 8, width: 16, height: 16)),
                            with: .color(Color(hue: hue, saturation: 0.8, brightness: 0.9)))
                    }
                }
                // The blur is what makes this genuinely GPU-expensive, not just decorative.
                .blur(radius: 12)
            }
            .ignoresSafeArea()

            VStack {
                Text(entry.reproducibilityNote)
                    .font(.caption)
                    .padding(8)
                    .background(.black.opacity(0.6))
                    .foregroundStyle(.white)
                    .padding(.top, 8)
                Spacer()
            }
        }
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .reportsScreenState(entry.id)
        .onAppear { ReproducibleState.set() }
    }
}

#Preview {
    NavigationStack { GPUScreen() }
}
