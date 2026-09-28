import RealityKit
import SwiftUI

struct GameView: View {
    @State private var session = GameSession()
    @State private var lastDrag: CGSize = .zero
    @State private var lastMagnification: CGFloat = 1

    var body: some View {
        let session = session
        ZStack {
            RealityView { content in
                session.attach(to: &content)
            }
            .ignoresSafeArea()
            .gesture(cameraOrbit)
            .simultaneousGesture(cameraZoom)

            if !session.isGamepadConnected {
                HStack(spacing: 0) {
                    FloatingJoystick { session.setTouchMove($0) }
                        .containerRelativeFrame(.horizontal) { width, _ in width * 0.4 }
                    Spacer(minLength: 0)
                        .allowsHitTesting(false)
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }

            HUDView(session: session)
        }
        .animation(.easeInOut(duration: 0.25), value: session.isGamepadConnected)
        .persistentSystemOverlays(.hidden)
        .statusBarHidden()
    }

    /// One-finger drag on the world orbits the camera.
    private var cameraOrbit: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let delta = CGSize(
                    width: value.translation.width - lastDrag.width,
                    height: value.translation.height - lastDrag.height)
                lastDrag = value.translation
                session.touchLook(delta)
            }
            .onEnded { _ in lastDrag = .zero }
    }

    /// Pinch to zoom.
    private var cameraZoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let ratio = value.magnification / lastMagnification
                lastMagnification = value.magnification
                session.zoom(by: Float((1 - ratio) * 12))
            }
            .onEnded { _ in lastMagnification = 1 }
    }
}
