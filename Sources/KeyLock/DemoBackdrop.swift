import SwiftUI

/// A colourful abstract wallpaper used only by `--demo --backdrop` so that
/// screenshots show what the grey liquid glass actually does: pick up and blur
/// whatever is behind it.
struct DemoWallpaper: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                LinearGradient(colors: [
                    Color(red: 0.05, green: 0.07, blue: 0.15),
                    Color(red: 0.09, green: 0.06, blue: 0.21),
                    Color(red: 0.03, green: 0.05, blue: 0.12),
                ], startPoint: .topLeading, endPoint: .bottomTrailing)

                blob(Color(red: 0.32, green: 0.22, blue: 0.98), 0.95 * w, x: 0.12, y: 0.18, w: w, h: h)
                blob(Color(red: 0.95, green: 0.24, blue: 0.58), 0.85 * w, x: 0.82, y: 0.14, w: w, h: h)
                blob(Color(red: 0.18, green: 0.78, blue: 0.95), 0.75 * w, x: 0.72, y: 0.82, w: w, h: h)
                blob(Color(red: 0.99, green: 0.66, blue: 0.24), 0.62 * w, x: 0.20, y: 0.88, w: w, h: h)
                blob(Color(red: 0.55, green: 0.30, blue: 1.00), 0.55 * w, x: 0.55, y: 0.45, w: w, h: h)

                // Fine grain + vignette so the glass has texture to blur.
                RadialGradient(colors: [.clear, .black.opacity(0.55)],
                               center: .center, startRadius: w * 0.25, endRadius: w * 0.85)
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .ignoresSafeArea()
    }

    private func blob(_ color: Color, _ size: CGFloat, x: CGFloat, y: CGFloat,
                      w: CGFloat, h: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: 110)
            .opacity(0.75)
            .blendMode(.screen)
            .position(x: w * x, y: h * y)
    }
}
