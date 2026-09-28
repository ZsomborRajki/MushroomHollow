import SwiftUI

/// Minimal heads-up display. Phase 1 adds health, target frame, and the skill bar.
struct HUDView: View {
    let session: GameSession

    var body: some View {
        VStack {
            HStack(alignment: .top) {
                PlayerPlate()
                Spacer()
                if session.isGamepadConnected {
                    Image(systemName: "gamecontroller.fill")
                        .font(.title3)
                        .padding(10)
                        .glassEffect(.regular, in: .circle)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            Spacer()
            #if DEBUG
            Text(session.debugText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .trailing)
            #endif
        }
        .padding()
        .animation(.snappy, value: session.isGamepadConnected)
        .allowsHitTesting(false)
    }
}

private struct PlayerPlate: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("🍄")
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sprout")
                    .font(.headline)
                Text("Lv 1 · Capstone Village")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
    }
}
