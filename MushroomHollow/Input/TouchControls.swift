import SwiftUI

/// Floating thumbstick: touch anywhere in its region and it appears under your thumb.
struct FloatingJoystick: View {
    var onChange: (SIMD2<Float>) -> Void

    @State private var origin: CGPoint?
    @State private var knob: CGSize = .zero

    private let radius: CGFloat = 56

    var body: some View {
        GeometryReader { geometry in
            let restingOrigin = CGPoint(x: radius + 40, y: geometry.size.height - radius - 40)
            let center = origin ?? restingOrigin

            ZStack {
                Color.clear.contentShape(Rectangle())

                Circle()
                    .fill(.clear)
                    .frame(width: radius * 2, height: radius * 2)
                    .glassEffect(.regular, in: .circle)
                    .opacity(origin == nil ? 0.45 : 1)
                    .position(center)

                Circle()
                    .fill(.white.opacity(0.85))
                    .frame(width: 46, height: 46)
                    .shadow(radius: 4)
                    .position(x: center.x + knob.width, y: center.y + knob.height)
                    .opacity(origin == nil ? 0.5 : 1)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if origin == nil { origin = value.startLocation }
                        var offset = value.translation
                        let length = hypot(offset.width, offset.height)
                        if length > radius {
                            offset = CGSize(width: offset.width / length * radius, height: offset.height / length * radius)
                        }
                        knob = offset
                        onChange(SIMD2(Float(offset.width / radius), Float(-offset.height / radius)))
                    }
                    .onEnded { _ in
                        withAnimation(.spring(duration: 0.2)) {
                            origin = nil
                            knob = .zero
                        }
                        onChange(.zero)
                    }
            )
        }
    }
}
