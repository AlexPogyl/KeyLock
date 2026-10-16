import Cocoa
import SwiftUI

// MARK: - Glass building blocks

/// A frosted, slightly translucent grey slab — the "liquid glass" surface the whole
/// menu is built from. Uses `NSVisualEffectView` underneath so the desktop really
/// shows through, plus hand-made specular highlights on top.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var intensity: Double = 1.0
    var tint: Color = .white
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(
                ZStack {
                    VisualEffectBackground(material: .hudWindow, blending: .behindWindow)
                    LinearGradient(
                        colors: [
                            tint.opacity(0.16 * intensity),
                            tint.opacity(0.04 * intensity),
                            Color.black.opacity(0.10 * intensity),
                        ],
                        startPoint: .top, endPoint: .bottom)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.38), .white.opacity(0.06)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1)
            )
            .overlay(
                // Inner top highlight — the "wet" edge that sells the glass look.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                    .blur(radius: 1.5)
                    .padding(1)
            )
            .shadow(color: .black.opacity(0.28), radius: 12, y: 6)
    }
}

/// Applies the native Liquid Glass material when running on macOS 26+.
struct LiquidGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if interactive {
                content.glassEffect(.regular.interactive(), in: shape)
            } else {
                content.glassEffect(.regular, in: shape)
            }
        } else {
            content
        }
    }
}

extension View {
    @ViewBuilder
    func liquidGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        modifier(LiquidGlassModifier(shape: shape, interactive: interactive))
    }
}

// MARK: - Rows

struct TargetRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    let isOn: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(isOn ? 0.16 : 0.07))
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isOn ? Color.white : Color.white.opacity(0.45))
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(enabled ? Color.white.opacity(0.95) : Color.white.opacity(0.35))
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.white.opacity(enabled ? 0.5 : 0.22))
                }
                Spacer(minLength: 6)
                GlassSwitch(isOn: isOn, enabled: enabled)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct GlassSwitch: View {
    let isOn: Bool
    var enabled: Bool = true

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Color.white.opacity(0.85) : Color.black.opacity(0.30))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8))
                .frame(width: 38, height: 22)
            Circle()
                .fill(isOn ? Color.black.opacity(0.75) : Color.white.opacity(0.75))
                .frame(width: 17, height: 17)
                .padding(.horizontal, 2.5)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        }
        .opacity(enabled ? 1 : 0.4)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isOn)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(1.1)
            .foregroundStyle(Color.white.opacity(0.42))
            .padding(.leading, 4)
    }
}

// MARK: - Big action button

struct BigLockButton: View {
    @ObservedObject var controller: LockController

    private var isLocked: Bool { controller.isLocked }
    private var counting: Bool { controller.countdown != nil }

    private var symbol: String {
        if counting { return "hourglass" }
        return isLocked ? "lock.fill" : "lock.open.fill"
    }

    private var title: String {
        if let c = controller.countdown { return "Блокировка через \(c)" }
        return isLocked ? "РАЗБЛОКИРОВАТЬ" : "ЗАБЛОКИРОВАТЬ"
    }

    private var subtitle: String {
        if isLocked { return "Нажмите или используйте \(controller.unlockCombo.display)" }
        if !controller.comboVerified { return "Сначала проверьте комбинацию" }
        return controller.blockedTargetsSummary
    }

    private var accent: Color {
        if counting { return .orange }
        return isLocked ? Color(red: 1.0, green: 0.36, blue: 0.36) : Color(red: 0.55, green: 0.82, blue: 1.0)
    }

    private var isReady: Bool { isLocked || controller.comboVerified }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 22, style: .continuous) }

    private var borderGradient: LinearGradient {
        LinearGradient(colors: [accent.opacity(isReady ? 0.65 : 0.2), .white.opacity(0.06)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    @ViewBuilder
    private var styledLabel: some View {
        if #available(macOS 26.0, *) {
            // Authentic Liquid Glass on macOS 26 (Tahoe).
            label
                .liquidGlass(in: shape)
                .overlay(
                    RadialGradient(colors: [accent.opacity(isLocked ? 0.30 : 0.14), .clear],
                                   center: .top, startRadius: 4, endRadius: 180)
                        .clipShape(shape)
                        .allowsHitTesting(false)
                )
        } else {
            label
                .background(
                    ZStack {
                        VisualEffectBackground(material: .hudWindow, blending: .behindWindow)
                        LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.03),
                                                Color.black.opacity(0.12)],
                                       startPoint: .top, endPoint: .bottom)
                        RadialGradient(colors: [accent.opacity(isLocked ? 0.22 : 0.10), .clear],
                                       center: .top, startRadius: 4, endRadius: 170)
                    }
                )
                .clipShape(shape)
        }
    }

    var body: some View {
        Button {
            controller.toggleLock()
        } label: {
            styledLabel
        }
        .buttonStyle(PressableStyle())
        .overlay(shape.strokeBorder(borderGradient, lineWidth: isLocked ? 1.4 : 1))
        .shadow(color: accent.opacity(isReady ? 0.28 : 0.0), radius: 16, y: 6)
        .opacity(isReady ? 1 : 0.72)
        .animation(.easeInOut(duration: 0.25), value: isLocked)
        .animation(.easeInOut(duration: 0.25), value: controller.comboVerified)
    }

    private var label: some View {
        VStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [accent.opacity(0.55), accent.opacity(0.08)],
                                         center: .center, startRadius: 2, endRadius: 46))
                    .frame(width: 84, height: 84)
                Circle()
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.05)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1)
                    .frame(width: 66, height: 66)
                Circle()
                    .fill(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 66, height: 66)
                Image(systemName: symbol)
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: accent.opacity(0.9), radius: 10)
            }
            .frame(width: 84, height: 84)

            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(.white)

            Text(subtitle)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 240)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .contentShape(shape)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Hotkey recorder

final class HotkeyRecorderModel: ObservableObject {
    @Published var isRecording = false
    @Published var draft: KeyCombo?

    private var monitor: Any?
    var onCommit: ((KeyCombo) -> Void)?
    var onCancel: (() -> Void)?

    func start(initial: KeyCombo) {
        guard !isRecording else { stop(); return }
        draft = nil
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        draft = nil
    }

    private func mods(from flags: NSEvent.ModifierFlags) -> Set<Mod> {
        var result = Set<Mod>()
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option)  { result.insert(.option) }
        if flags.contains(.shift)   { result.insert(.shift) }
        if flags.contains(.command) { result.insert(.command) }
        return result
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        let mods = mods(from: event.modifierFlags)

        if event.type == .flagsChanged {
            draft = KeyCombo(keyCode: event.keyCode, mods: mods)
            return nil
        }

        // Escape with no modifiers cancels the recording.
        if event.keyCode == 53 && mods.isEmpty {
            stop()
            onCancel?()
            return nil
        }

        let combo = KeyCombo(keyCode: event.keyCode, mods: mods)
        guard combo.isUsable else { return nil }
        stop()
        onCommit?(combo)
        return nil
    }
}

struct HotkeyRecorderView: View {
    @ObservedObject var controller: LockController
    @StateObject private var recorder = HotkeyRecorderModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Комбинация полной разблокировки")

            GlassCard(cornerRadius: 16, intensity: 0.8) {
                HStack(spacing: 10) {
                    Image(systemName: "keyboard.badge.ellipsis")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))

                    Text(displayText)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(recorder.isRecording ? Color.orange : Color.white.opacity(0.95))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        if recorder.isRecording {
                            recorder.stop()
                            recorder.onCancel?()
                        } else {
                            recorder.start(initial: controller.unlockCombo)
                        }
                    } label: {
                        Text(recorder.isRecording ? "Отмена" : "Изменить")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(Color.white.opacity(0.14))
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8))
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }

            if let message = controller.unlockCombo.validationMessage, !recorder.isRecording {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.orange.opacity(0.95))
                    .padding(.leading, 4)
            }

            Text(recorder.isRecording
                 ? "Нажмите нужные клавиши… (⎋ — отменить)"
                 : "Для разблокировки одна комбинация. Аварийный выход ⎋ ×5 работает всегда.")
                .font(.system(size: 10.5, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.leading, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onDisappear { recorder.stop() }
        .onAppear {
            recorder.onCommit = { combo in
                controller.unlockCombo = combo
                controller.show(.init(kind: .info, text: "Новая комбинация: \(combo.display). Проверьте её перед блокировкой."))
            }
            recorder.onCancel = {
                if controller.isVerifying { controller.cancelVerification() }
            }
        }
    }

    private var displayText: String {
        if let draft = recorder.draft, recorder.isRecording {
            let mods = draft.modifierSymbols
            return mods.isEmpty ? "…" : mods + "…"
        }
        return controller.unlockCombo.display
    }
}

// MARK: - Verification block

struct VerificationRow: View {
    @ObservedObject var controller: LockController

    var body: some View {
        GlassCard(cornerRadius: 16, intensity: 0.7) {
            HStack(spacing: 10) {
                Image(systemName: statusSymbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(statusColor)

                VStack(alignment: .leading, spacing: 1) {
                    Text(statusTitle)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                    Text(statusSubtitle)
                        .font(.system(size: 10.5, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)

                Button {
                    if controller.isVerifying { controller.cancelVerification() }
                    else { controller.beginVerification() }
                } label: {
                    Text(controller.isVerifying ? "Отмена" : (controller.comboVerified ? "Ещё раз" : "Проверить"))
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(controller.comboVerified ? Color.green.opacity(0.35)
                                                                : Color.orange.opacity(0.35))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private var statusSymbol: String {
        if controller.isVerifying { return "dot.radiowaves.left.and.right" }
        return controller.comboVerified ? "checkmark.shield.fill" : "shield.lefthalf.filled"
    }

    private var statusColor: Color {
        if controller.isVerifying { return .orange }
        return controller.comboVerified ? .green : .white.opacity(0.55)
    }

    private var statusTitle: String {
        if controller.isVerifying { return "Нажмите \(controller.unlockCombo.display)" }
        return controller.comboVerified ? "Разблокировка проверена" : "Разблокировка не проверена"
    }

    private var statusSubtitle: String {
        if controller.isVerifying {
            return "Проверка идёт глобально, ничего не блокируется."
        }
        return controller.comboVerified
            ? "Комбинация поймана системным перехватчиком."
            : "Обязательный шаг до блокировки ввода."
    }
}

// MARK: - Notice banner

struct NoticeBanner: View {
    let notice: LockController.Notice

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
            Text(notice.text)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.16))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(color.opacity(0.4), lineWidth: 0.8))
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var symbol: String {
        switch notice.kind {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch notice.kind {
        case .info: return .cyan
        case .warning: return .orange
        case .success: return .green
        case .error: return .red
        }
    }
}

// MARK: - Footer

struct FooterView: View {
    @ObservedObject var controller: LockController

    var body: some View {
        VStack(spacing: 8) {
            if !controller.accessibilityGranted {
                Button {
                    controller.requestAccessibility()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.orange)
                        Text("Разрешить «Универсальный доступ»")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.92))
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.orange.opacity(0.18))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.orange.opacity(0.45), lineWidth: 0.8))
                    )
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { controller.showAdvanced.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "gearshape.fill")
                        Text("Дополнительно")
                        Image(systemName: controller.showAdvanced ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Text("Выйти")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            if controller.showAdvanced {
                VStack(spacing: 6) {
                    HStack {
                        Text("Авторазблокировка")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                        Spacer()
                        Picker("", selection: $controller.autoUnlockMinutes) {
                            Text("Никогда").tag(0)
                            Text("1 мин").tag(1)
                            Text("5 мин").tag(5)
                            Text("15 мин").tag(15)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 108)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.12))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8))
                        )
                    }
                    HStack {
                        Text("Снимать блокировку при пробуждении")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                        Spacer()
                        Button {
                            controller.unlockOnWake.toggle()
                        } label: {
                            GlassSwitch(isOn: controller.unlockOnWake)
                        }
                        .buttonStyle(.plain)
                    }
                    HStack {
                        Text("Аварийный выход")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                        Spacer()
                        Text("⎋ ×5 подряд")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(height: 1)
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Иконка в строке меню")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.75))
                            Text("Без иконки меню открывается из Spotlight")
                                .font(.system(size: 9.5, weight: .regular, design: .rounded))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        Spacer()
                        Button {
                            controller.showMenuBarIcon.toggle()
                        } label: {
                            GlassSwitch(isOn: controller.showMenuBarIcon)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }
}

// MARK: - Root menu

struct MenuView: View {
    @ObservedObject var controller: LockController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            BigLockButton(controller: controller)

            VStack(alignment: .leading, spacing: 7) {
                SectionLabel(text: "Что блокировать")
                GlassCard(cornerRadius: 16, intensity: 0.8) {
                    VStack(spacing: 0) {
                        TargetRow(symbol: "keyboard.fill",
                                  title: "Клавиатура",
                                  subtitle: "Все нажатия, кроме комбинации разблокировки",
                                  isOn: controller.blockKeyboard,
                                  enabled: !controller.isLocked) {
                            controller.blockKeyboard.toggle()
                        }
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 1)
                            .padding(.horizontal, 12)
                        TargetRow(symbol: "rectangle.and.hand.point.up.left.fill",
                                  title: "Трекпад",
                                  subtitle: "Указатель замирает (внешняя мышь тоже)",
                                  isOn: controller.blockTrackpad,
                                  enabled: !controller.isLocked) {
                            controller.blockTrackpad.toggle()
                        }
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 1)
                            .padding(.horizontal, 12)
                        TargetRow(symbol: "rectangle.topthird.inset.filled",
                                  title: "Touch Bar",
                                  subtitle: "Тапы по панели не доходят до системы",
                                  isOn: controller.blockTouchBar,
                                  enabled: !controller.isLocked && TouchBarController.shared.isAvailable) {
                            controller.blockTouchBar.toggle()
                        }
                    }
                    .padding(.vertical, 3)
                }
            }

            HotkeyRecorderView(controller: controller)
            VerificationRow(controller: controller)

            if let notice = controller.notice {
                NoticeBanner(notice: notice)
            }

            FooterView(controller: controller)
        }
        .padding(14)
        .frame(width: 348)
        .background(
            ZStack {
                VisualEffectBackground(material: .hudWindow, blending: .behindWindow)
                LinearGradient(colors: [Color(white: 0.62).opacity(0.22),
                                        Color(white: 0.28).opacity(0.16),
                                        Color(white: 0.10).opacity(0.24)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [.white.opacity(0.10), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 320)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0.08)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.black.opacity(0.4), lineWidth: 0.5)
                .padding(-0.5)
        )
        .animation(.easeInOut(duration: 0.2), value: controller.notice)
    }

    private var header: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.85).opacity(0.35),
                                                  Color(white: 0.4).opacity(0.18)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.8))
                Image(systemName: controller.isLocked ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(controller.isLocked ? Color(red: 1, green: 0.4, blue: 0.4) : .white)
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 0) {
                Text("KeyLock")
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(statusLine)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            statusPill
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
    }

    private var statusLine: String {
        if controller.isLocked {
            return controller.pointerFallbackActive ? "заблокировано (мышь тоже)" : "заблокировано"
        }
        if controller.countdown != nil { return "отсчёт до блокировки" }
        return "готово к работе"
    }

    private var statusPill: some View {
        Text(controller.isLocked ? "LOCKED" : "IDLE")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(controller.isLocked ? Color(red: 1, green: 0.45, blue: 0.45) : Color.white.opacity(0.5))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.09))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.7))
            )
    }
}
