import Cocoa
import SwiftUI

/// Small, non-interactive overlay used for the "3‑2‑1" warning and for the
/// "unlocked / locked" confirmation. It never becomes key and never blocks input,
/// so it can stay on screen even while the keyboard is suppressed.
final class HUD {

    static let shared = HUD()

    private var window: NSWindow?
    private var hideWorkItem: DispatchWorkItem?

    private init() {}

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 160),
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .screenSaver
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return window
    }

    func show(symbol: String, title: String, subtitle: String? = nil, tint: NSColor, duration: TimeInterval) {
        hideWorkItem?.cancel()

        let view = HUDView(symbol: symbol, title: title, subtitle: subtitle, tint: tint)
        let hosting = NSHostingView(rootView: view)
        hosting.setFrameSize(hosting.fittingSize)

        let window = self.window ?? makeWindow()
        self.window = window
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let size = hosting.fittingSize
            window.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2,
                                          y: frame.midY - size.height / 2 + 40))
        }
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            window.animator().alphaValue = 1
        }

        let item = DispatchWorkItem { [weak self] in self?.hide() }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    func hide() {
        guard let window else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            window.orderOut(nil)
            self?.window = nil
        })
    }
}

private struct HUDView: View {
    let symbol: String
    let title: String
    let subtitle: String?
    let tint: NSColor

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color(nsColor: tint))
            Text(title)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 26)
        .background(
            ZStack {
                VisualEffectBackground(material: .hudWindow, blending: .behindWindow)
                Color.black.opacity(0.25)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 30, y: 12)
    }
}

/// Thin SwiftUI wrapper around `NSVisualEffectView` so we can use real AppKit
/// materials inside SwiftUI hierarchies.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    var appearance: NSAppearance.Name? = .vibrantDark

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        if let appearance { view.appearance = NSAppearance(named: appearance) }
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
        view.state = .active
        if let appearance { view.appearance = NSAppearance(named: appearance) }
    }
}
