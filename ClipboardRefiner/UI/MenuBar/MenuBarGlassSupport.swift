import AppKit
import SwiftUI

struct GlassCard<Content: View>: View {
    @ViewBuilder let content: Content
    var tint: Color = Color.white.opacity(0.06)

    init(tint: Color = Color.white.opacity(0.06), @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .padding(DS.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCardStyle(cornerRadius: DS.Radius.lg, tint: tint, interactive: false)
    }
}

struct GlassAwareActionButton: View {
    enum Style {
        case prominent
        case secondary
    }

    let title: String
    let icon: String
    let style: Style
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                if style == .prominent {
                    Button(action: action) {
                        Label(title, systemImage: icon)
                            .font(DS.Typography.captionFont)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isDisabled)
                    .opacity(isDisabled ? 0.5 : 1)
                } else {
                    Button(action: action) {
                        Label(title, systemImage: icon)
                            .font(DS.Typography.captionFont)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .disabled(isDisabled)
                    .opacity(isDisabled ? 0.5 : 1)
                }
            } else {
                if style == .prominent {
                    PrimaryActionButton(
                        title: title,
                        icon: icon,
                        isDisabled: isDisabled,
                        action: action
                    )
                } else {
                    SecondaryActionButton(
                        title: title,
                        icon: icon,
                        isDisabled: isDisabled,
                        action: action
                    )
                }
            }
        }
    }
}

extension View {
    @ViewBuilder
    func glassCardStyle(cornerRadius: CGFloat, tint: Color, interactive: Bool) -> some View {
        if #available(macOS 26.0, *) {
            self
                .glassEffect(
                    .regular
                        .tint(tint)
                        .interactive(interactive),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        } else {
            self
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(DS.Colors.borderSubtle, lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    func glassAccentCapsule(active: Bool, tint: Color) -> some View {
        if #available(macOS 26.0, *) {
            self
                .padding(DS.Spacing.xxs)
                .glassEffect(
                    .regular
                        .tint(tint.opacity(active ? 0.26 : 0.15))
                        .interactive(active),
                    in: Capsule()
                )
        } else {
            self
                .background(
                    Capsule()
                        .fill(tint.opacity(active ? 0.26 : 0.14))
                )
        }
    }

    @ViewBuilder
    func glassMorph<ID: Hashable>(id: ID, namespace: Namespace.ID) -> some View {
        if #available(macOS 26.0, *) {
            self
                .glassEffectID(id, in: namespace)
                .glassEffectTransition(.matchedGeometry)
        } else {
            self
        }
    }

    func staggeredAppear(index: Int, isVisible: Bool) -> some View {
        self
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : CGFloat(8 + index * 2))
            .animation(DS.Animation.smooth.delay(Double(index) * 0.04), value: isVisible)
    }
}

struct ShareSheetAnchorView: NSViewRepresentable {
    @Binding var anchor: NSView?

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            anchor = view
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            anchor = nsView
        }
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
