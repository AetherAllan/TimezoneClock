import AppKit
import SwiftUI

struct ClockGlassBar<Content: View>: View {
    let style: InterfaceStyle
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if #available(macOS 26, *), style == .liquidGlass, !reduceTransparency {
            GlassEffectContainer(spacing: 8) {
                paddedContent.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
            }
        } else {
            paddedContent
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(0.06), lineWidth: 1))
        }
    }

    private var paddedContent: some View {
        content.padding(.horizontal, 12).padding(.vertical, 10)
    }
}

struct ClockActionStyle: ViewModifier {
    let style: InterfaceStyle
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if #available(macOS 26, *), style == .liquidGlass, !reduceTransparency {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

struct ClockAppearanceView: View {
    @Bindable var store: ClockStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.text("System Appearance")).font(.headline)
                    Text(store.text("Changes the appearance of macOS. Your schedule resumes at the next planned transition."))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                modeControl
            }
            if let status = store.appearance.manualStatus {
                Text(status.text(language: store.language))
                    .font(.caption).textSelection(.enabled)
                    .accessibilityIdentifier("manualAppearanceStatus")
            } else if store.appearance.actualDark == nil {
                Text(store.text("System appearance is unknown. Choose Light or Dark to request access."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Picker(store.text("Interface Style"), selection: $store.preferences.interfaceStyle) {
                Text(store.text("Liquid Glass")).tag(InterfaceStyle.liquidGlass)
                Text(store.text("Standard")).tag(InterfaceStyle.standard)
            }
            .pickerStyle(.segmented)
            if #unavailable(macOS 26) {
                if store.preferences.interfaceStyle == .liquidGlass {
                    Text(store.text("Liquid Glass requires macOS 26. Standard appearance is used on this Mac."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button(store.text("Appearance Settings")) { openSettings("com.apple.Appearance-Settings.extension") }
                Button(store.text("Automation Settings")) { openSettings("com.apple.preference.security?Privacy_Automation") }
            }
            .modifier(ClockActionStyle(style: store.preferences.interfaceStyle))
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var modeControl: some View {
        if #available(macOS 26, *), store.preferences.interfaceStyle == .liquidGlass, !reduceTransparency {
            GlassEffectContainer(spacing: 4) { modeButtons }
        } else {
            modeButtons
        }
    }

    private var modeButtons: some View {
        HStack(spacing: 4) {
            modeButton(dark: false)
            modeButton(dark: true)
        }
        .frame(width: 200, height: 44)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.appearance.actualDark)
        .disabled(store.appearance.isBusy)
    }

    @ViewBuilder
    private func modeButton(dark: Bool) -> some View {
        let selected = store.appearance.actualDark == dark
        let color: Color = dark ? .indigo : .orange
        let button = Button {
            store.appearance.setAppearanceManually(dark: dark)
        } label: {
            Label(store.text(dark ? "Dark" : "Light"), systemImage: dark ? "moon.fill" : "sun.max.fill")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 72, height: 28)
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .accessibilityLabel(store.text(dark ? "Dark" : "Light"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(dark ? "darkAppearanceButton" : "lightAppearanceButton")

        if #available(macOS 26, *), store.preferences.interfaceStyle == .liquidGlass, !reduceTransparency {
            if selected {
                button.buttonStyle(.glassProminent).tint(color)
            } else {
                button.buttonStyle(.glass)
            }
        } else if selected {
            button.buttonStyle(.borderedProminent).tint(color)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:\(pane)") { NSWorkspace.shared.open(url) }
    }
}
