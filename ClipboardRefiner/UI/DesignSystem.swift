import SwiftUI
import AppKit

private enum TextLayoutEstimator {
    private static let bodyFont = NSFont.systemFont(ofSize: 13, weight: .regular)
    private static let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    private static let bodyLineHeight = ceil(bodyFont.ascender - bodyFont.descender + bodyFont.leading)
    private static let monoLineHeight = ceil(monoFont.ascender - monoFont.descender + monoFont.leading)
    private static let bodyCharacterWidth = ("W" as NSString).size(withAttributes: [.font: bodyFont]).width
    private static let monoCharacterWidth = ("W" as NSString).size(withAttributes: [.font: monoFont]).width

    static func bodyHeight(for text: String, width: CGFloat) -> CGFloat {
        estimatedHeight(for: text, width: width, lineHeight: bodyLineHeight, characterWidth: bodyCharacterWidth)
    }

    static func monoHeight(for text: String, width: CGFloat) -> CGFloat {
        estimatedHeight(for: text, width: width, lineHeight: monoLineHeight, characterWidth: monoCharacterWidth)
    }

    private static func estimatedHeight(for text: String, width: CGFloat, lineHeight: CGFloat, characterWidth: CGFloat) -> CGFloat {
        let safeWidth = max(1, width)
        let safeCharacterWidth = max(1, characterWidth)
        let maxColumns = max(1, Int(floor(safeWidth / safeCharacterWidth)))
        let lines = wrappedLineCount(for: text, maxColumns: maxColumns)
        return ceil(CGFloat(lines) * lineHeight)
    }

    private static func wrappedLineCount(for text: String, maxColumns: Int) -> Int {
        guard !text.isEmpty else { return 1 }
        let segments = text.split(separator: "\n", omittingEmptySubsequences: false)
        var total = 0
        for segment in segments {
            total += max(1, Int(ceil(Double(segment.count) / Double(maxColumns))))
        }
        return max(total, 1)
    }
}

// MARK: - Design System: "Warm Obsidian"
// A refined, premium aesthetic with soft amber accents and smooth glass effects

enum DS {
    // MARK: - Spacing Scale
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }

    // MARK: - Corner Radius
    enum Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let xl: CGFloat = 18
        static let full: CGFloat = 9999
    }

    // MARK: - Typography
    enum Typography {
        static let displayFont = Font.system(size: 15, weight: .semibold, design: .rounded)
        static let headlineFont = Font.system(size: 13, weight: .semibold)
        static let bodyFont = Font.system(size: 13, weight: .regular)
        static let captionFont = Font.system(size: 11, weight: .medium)
        static let microFont = Font.system(size: 10, weight: .medium)
    }

    // MARK: - Colors
    enum Colors {
        // Primary accent - warm amber/gold
        static let accent = Color(red: 0.96, green: 0.72, blue: 0.26)
        static let accentSubtle = Color(red: 0.96, green: 0.72, blue: 0.26).opacity(0.15)
        static let accentGlow = Color(red: 1.0, green: 0.78, blue: 0.36)

        // Secondary accent - cool slate blue
        static let secondary = Color(red: 0.45, green: 0.55, blue: 0.72)
        static let secondarySubtle = Color(red: 0.45, green: 0.55, blue: 0.72).opacity(0.12)

        // Explain accent - soft purple
        static let explainAccent = Color(red: 0.68, green: 0.52, blue: 0.88)
        static let explainSubtle = Color(red: 0.68, green: 0.52, blue: 0.88).opacity(0.12)

        // Semantic colors
        static let success = Color(red: 0.35, green: 0.78, blue: 0.55)
        static let successSubtle = Color(red: 0.35, green: 0.78, blue: 0.55).opacity(0.12)
        static let warning = Color(red: 0.95, green: 0.65, blue: 0.25)
        static let warningSubtle = Color(red: 0.95, green: 0.65, blue: 0.25).opacity(0.12)
        static let error = Color(red: 0.92, green: 0.42, blue: 0.42)
        static let errorSubtle = Color(red: 0.92, green: 0.42, blue: 0.42).opacity(0.12)

        // Surface colors
        static let surfacePrimary = Color.primary.opacity(0.04)
        static let surfaceSecondary = Color.primary.opacity(0.06)
        static let surfaceElevated = Color.primary.opacity(0.08)
        static let surfaceHover = Color.primary.opacity(0.10)

        // Input backgrounds
        static let inputBackground = Color(nsColor: .textBackgroundColor).opacity(0.6)
        static let inputBackgroundFocused = Color(nsColor: .textBackgroundColor).opacity(0.8)

        // Text colors
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color.primary.opacity(0.4)
        static let textMuted = Color.primary.opacity(0.25)

        // Border colors
        static let border = Color.primary.opacity(0.08)
        static let borderSubtle = Color.primary.opacity(0.05)
        static let borderFocused = accent.opacity(0.4)
    }

    // MARK: - Shadows
    enum Shadow {
        static let soft = (color: Color.black.opacity(0.08), radius: CGFloat(8), y: CGFloat(2))
        static let medium = (color: Color.black.opacity(0.12), radius: CGFloat(12), y: CGFloat(4))
        static let glow = (color: Colors.accent.opacity(0.3), radius: CGFloat(12), y: CGFloat(0))
        static let glowSubtle = (color: Colors.accent.opacity(0.15), radius: CGFloat(8), y: CGFloat(0))
    }

    // MARK: - Animation
    enum Animation {
        static let micro = SwiftUI.Animation.easeOut(duration: 0.1)
        static let quick = SwiftUI.Animation.spring(response: 0.25, dampingFraction: 0.8)
        static let standard = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.75)
        static let smooth = SwiftUI.Animation.spring(response: 0.45, dampingFraction: 0.8)
        static let bouncy = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.65)
    }
}

// MARK: - Glow Effect Modifier (Subtle)

struct GlowEffect: ViewModifier {
    let color: Color
    let radius: CGFloat
    var isActive: Bool = true

    func body(content: Content) -> some View {
        content
            .shadow(color: isActive ? color.opacity(0.25) : .clear, radius: radius * 0.5, x: 0, y: 0)
    }
}

extension View {
    func glow(_ color: Color, radius: CGFloat = 4, isActive: Bool = true) -> some View {
        modifier(GlowEffect(color: color, radius: radius, isActive: isActive))
    }
}

// MARK: - Shimmer Effect

struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.1), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    phase = 300
                }
            }
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    var trailing: AnyView? = nil
    var icon: String? = nil

    init(_ title: String, icon: String? = nil) {
        self.title = title
        self.icon = icon
    }

    init(_ title: String, icon: String? = nil, @ViewBuilder trailing: () -> some View) {
        self.title = title
        self.icon = icon
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.Colors.textTertiary)
            }

            Text(title.uppercased())
                .font(DS.Typography.microFont)
                .tracking(0.8)
                .foregroundStyle(DS.Colors.textTertiary)

            Spacer()

            if let trailing {
                trailing
            }
        }
    }
}

// MARK: - Text Box (Refined)

struct TextBox: View {
    @Binding var text: String
    let placeholder: String
    var isEditable: Bool = true
    var minHeight: CGFloat = 80
    var maxHeight: CGFloat = 300
    var shouldMeasureHeight: Bool = true
    var font: Font = DS.Typography.bodyFont

    @State private var measuredHeight: CGFloat = 0
    @FocusState private var isFocused: Bool
    @State private var isHovering = false

    var body: some View {
        let effectiveHeight = min(max(measuredHeight + DS.Spacing.xl, minHeight), maxHeight)

        ZStack(alignment: .topLeading) {
            if isEditable {
                TextEditor(text: $text)
                    .font(font)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
            } else {
                ScrollView {
                    Text(text)
                        .font(font)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if text.isEmpty {
                Text(placeholder)
                    .font(font)
                    .foregroundStyle(DS.Colors.textMuted)
                    .allowsHitTesting(false)
                    .padding(.top, 1)
                    .padding(.leading, isEditable ? 5 : 0)
            }
        }
        .padding(DS.Spacing.md)
        .frame(height: effectiveHeight)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .fill(isFocused ? DS.Colors.inputBackgroundFocused : DS.Colors.inputBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .strokeBorder(
                    isFocused ? DS.Colors.borderFocused : (isHovering ? DS.Colors.border : DS.Colors.borderSubtle),
                    lineWidth: isFocused ? 1.5 : 1
                )
        )
        .onHover { isHovering = $0 }
        .animation(DS.Animation.quick, value: isFocused)
        .animation(DS.Animation.micro, value: isHovering)
        .background(shouldMeasureHeight ? measureText : nil)
    }

    private var measureText: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { updateHeight(width: geo.size.width) }
                .onChange(of: geo.size.width) { _, w in updateHeight(width: w) }
                .onChange(of: text) { _, _ in updateHeight(width: geo.size.width) }
        }
    }

    private func updateHeight(width: CGFloat) {
        guard width > 0 else { return }
        let textWidth = max(1, width - DS.Spacing.lg * 2)
        let measureText = text.isEmpty ? " " : text
        measuredHeight = TextLayoutEstimator.bodyHeight(for: measureText, width: textWidth)
    }
}

// MARK: - Icon Button (Refined)

struct IconButton: View {
    let icon: String
    let action: () -> Void
    var isActive: Bool = false
    var help: String? = nil
    var accessibilityLabel: String? = nil
    var size: CGFloat = 28
    var accentColor: Color = DS.Colors.accent

    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isActive ? accentColor : DS.Colors.textSecondary)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .fill(backgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .strokeBorder(isActive ? accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
                )
                .scaleEffect(isPressed ? 0.92 : 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .pressEvents(onPress: { isPressed = true }, onRelease: { isPressed = false })
        .animation(DS.Animation.micro, value: isPressed)
        .animation(DS.Animation.quick, value: isHovering)
        .help(help ?? "")
        .accessibilityLabel(accessibilityLabel ?? help ?? iconAccessibilityLabel)
    }

    private var backgroundColor: Color {
        if isActive {
            return accentColor.opacity(0.12)
        }
        if isHovering {
            return DS.Colors.surfaceHover
        }
        return Color.clear
    }

    private var iconAccessibilityLabel: String {
        icon.replacingOccurrences(of: ".", with: " ")
    }
}

// MARK: - Press Events Modifier

struct PressEventsModifier: ViewModifier {
    var onPress: () -> Void
    var onRelease: () -> Void

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onPress() }
                    .onEnded { _ in onRelease() }
            )
    }
}

extension View {
    func pressEvents(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        modifier(PressEventsModifier(onPress: onPress, onRelease: onRelease))
    }
}

// MARK: - Status Pill (Refined)

struct StatusPill: View {
    let isConnected: Bool
    let label: String
    var onTap: (() -> Void)? = nil

    @State private var isHovering = false
    @State private var pulseScale: CGFloat = 1

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Circle()
                .fill(isConnected ? DS.Colors.success : DS.Colors.warning)
                .frame(width: 6, height: 6)
                .scaleEffect(pulseScale)

            Text(label)
                .font(DS.Typography.captionFont)
                .foregroundStyle(DS.Colors.textSecondary)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .background(
            Capsule()
                .fill(DS.Colors.surfacePrimary)
                .overlay(
                    Capsule()
                        .strokeBorder(isHovering ? DS.Colors.border : DS.Colors.borderSubtle, lineWidth: 1)
                )
        )
        .onHover { isHovering = $0 }
        .onTapGesture { onTap?() }
        .animation(DS.Animation.quick, value: isHovering)
        .onAppear {
            if isConnected {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulseScale = 1.2
                }
            }
        }
    }
}

// MARK: - Tag (Refined)

struct Tag: View {
    let text: String
    var color: Color = DS.Colors.accent
    var size: TagSize = .regular

    enum TagSize {
        case small, regular

        var font: Font {
            switch self {
            case .small: return DS.Typography.microFont
            case .regular: return DS.Typography.captionFont
            }
        }

        var padding: (h: CGFloat, v: CGFloat) {
            switch self {
            case .small: return (DS.Spacing.sm, DS.Spacing.xs)
            case .regular: return (DS.Spacing.md, DS.Spacing.sm)
            }
        }
    }

    var body: some View {
        Text(text)
            .font(size.font)
            .foregroundStyle(color)
            .padding(.horizontal, size.padding.h)
            .padding(.vertical, size.padding.v)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .fill(color.opacity(0.12))
            )
    }
}

// MARK: - Card (Refined)

struct Card<Content: View>: View {
    let content: Content
    var isInteractive: Bool = false
    var isSelected: Bool = false
    var action: (() -> Void)? = nil

    @State private var isHovering = false
    @State private var isPressed = false

    init(isInteractive: Bool = false, isSelected: Bool = false, action: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.isInteractive = isInteractive
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Group {
            if isInteractive, let action {
                Button(action: action) {
                    cardContent
                }
                .buttonStyle(.plain)
                .pressEvents(onPress: { isPressed = true }, onRelease: { isPressed = false })
            } else {
                cardContent
            }
        }
    }

    private var cardContent: some View {
        content
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .strokeBorder(borderColor, lineWidth: isSelected ? 1.5 : 1)
            )
            .scaleEffect(isPressed ? 0.98 : 1)
            .onHover { isHovering = $0 }
            .animation(DS.Animation.micro, value: isPressed)
            .animation(DS.Animation.quick, value: isHovering)
    }

    private var backgroundColor: Color {
        if isSelected {
            return DS.Colors.accentSubtle
        }
        if isHovering && isInteractive {
            return DS.Colors.surfaceElevated
        }
        return DS.Colors.surfacePrimary
    }

    private var borderColor: Color {
        if isSelected {
            return DS.Colors.accent.opacity(0.4)
        }
        if isHovering && isInteractive {
            return DS.Colors.border
        }
        return DS.Colors.borderSubtle
    }
}

// MARK: - Segmented Picker (Refined)

struct StyledSegmentedPicker<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(DS.Animation.quick) {
                        selection = option
                    }
                } label: {
                    Text(label(option))
                        .font(DS.Typography.captionFont)
                        .foregroundStyle(selection == option ? DS.Colors.textPrimary : DS.Colors.textTertiary)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.xs)
                                .fill(selection == option ? DS.Colors.surfaceElevated : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DS.Spacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .fill(DS.Colors.surfacePrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .strokeBorder(DS.Colors.borderSubtle, lineWidth: 1)
                )
        )
    }
}

// MARK: - Primary Action Button

struct PrimaryActionButton: View {
    let title: String
    let icon: String
    var isLoading: Bool = false
    var isDisabled: Bool = false
    var accentColor: Color = DS.Colors.accent
    let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                if isLoading {
                    LoadingDots()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(DS.Typography.captionFont)
            }
            .foregroundColor(.black.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(
                        LinearGradient(
                            colors: [accentColor, accentColor.opacity(0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .scaleEffect(isPressed ? 0.97 : 1)
            .opacity(isDisabled ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isLoading)
        .onHover { isHovering = $0 }
        .pressEvents(onPress: { isPressed = true }, onRelease: { isPressed = false })
        .animation(DS.Animation.micro, value: isPressed)
        .animation(DS.Animation.quick, value: isHovering)
    }
}

// MARK: - Secondary Action Button

struct SecondaryActionButton: View {
    let title: String
    let icon: String
    var isLoading: Bool = false
    var isDisabled: Bool = false
    var accentColor: Color = DS.Colors.secondary
    let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                if isLoading {
                    LoadingDots()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                }
                Text(title)
                    .font(DS.Typography.captionFont)
            }
            .foregroundColor(accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(accentColor.opacity(isHovering ? 0.15 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .strokeBorder(accentColor.opacity(0.3), lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.97 : 1)
            .opacity(isDisabled ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isLoading)
        .onHover { isHovering = $0 }
        .pressEvents(onPress: { isPressed = true }, onRelease: { isPressed = false })
        .animation(DS.Animation.micro, value: isPressed)
        .animation(DS.Animation.quick, value: isHovering)
    }
}

// MARK: - Action Row Button (Legacy Support)

struct ActionRowButton: View {
    let title: String
    let icon: String
    var style: ButtonVariant = .primary
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    enum ButtonVariant {
        case primary
        case secondary
        case accent(Color)
    }

    var body: some View {
        Group {
            switch style {
            case .primary:
                PrimaryActionButton(
                    title: title,
                    icon: icon,
                    isLoading: isLoading,
                    isDisabled: isDisabled,
                    action: action
                )
            case .secondary:
                SecondaryActionButton(
                    title: title,
                    icon: icon,
                    isLoading: isLoading,
                    isDisabled: isDisabled,
                    action: action
                )
            case .accent(let color):
                SecondaryActionButton(
                    title: title,
                    icon: icon,
                    isLoading: isLoading,
                    isDisabled: isDisabled,
                    accentColor: color,
                    action: action
                )
            }
        }
    }
}

// MARK: - Empty State

struct EmptyState: View {
    let icon: String
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(DS.Colors.textMuted)

            Text(title)
                .font(DS.Typography.captionFont)
                .foregroundStyle(DS.Colors.textTertiary)

            if let message {
                Text(message)
                    .font(DS.Typography.microFont)
                    .foregroundStyle(DS.Colors.textMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xxl)
    }
}

// MARK: - Toast (Refined)

struct Toast: View {
    let message: String
    var icon: String? = nil
    var action: (label: String, handler: () -> Void)? = nil

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.Colors.success)
            }

            Text(message)
                .font(DS.Typography.captionFont)
                .foregroundStyle(DS.Colors.textSecondary)

            if let action {
                Button(action.label, action: action.handler)
                    .font(DS.Typography.captionFont)
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.Colors.accent)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(DS.Colors.borderSubtle, lineWidth: 1)
                )
                .shadow(color: DS.Shadow.soft.color, radius: DS.Shadow.soft.radius, y: DS.Shadow.soft.y)
        )
        .onHover { isHovering = $0 }
    }
}

// MARK: - Diff Text View (Refined)

struct DiffTextView: View {
    let spans: [DiffSpan]
    let placeholder: String
    var minHeight: CGFloat = 80
    var maxHeight: CGFloat = 300

    struct DiffSpan {
        enum Kind { case equal, insert, delete }
        let kind: Kind
        var text: String
    }

    @State private var measuredHeight: CGFloat = 0

    var body: some View {
        let rawText = spans.map { $0.text }.joined()
        let effectiveHeight = min(max(measuredHeight + DS.Spacing.xl, minHeight), maxHeight)

        ScrollView {
            if spans.isEmpty && !placeholder.isEmpty {
                Text(placeholder)
                    .font(DS.Typography.bodyFont)
                    .foregroundStyle(DS.Colors.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(makeAttributedText())
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(DS.Spacing.md)
        .frame(height: effectiveHeight)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .fill(DS.Colors.inputBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .strokeBorder(DS.Colors.borderSubtle, lineWidth: 1)
        )
        .background(measureText(rawText: rawText))
    }

    private func measureText(rawText: String) -> some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { updateHeight(width: geo.size.width, text: rawText) }
                .onChange(of: geo.size.width) { _, w in updateHeight(width: w, text: rawText) }
                .onChange(of: rawText) { _, t in updateHeight(width: geo.size.width, text: t) }
        }
    }

    private func updateHeight(width: CGFloat, text: String) {
        guard width > 0 else { return }
        let textWidth = max(1, width - DS.Spacing.lg * 2)
        let measureText = text.isEmpty ? placeholder : text
        let safeText = measureText.isEmpty ? " " : measureText

        measuredHeight = TextLayoutEstimator.monoHeight(for: safeText, width: textWidth)
    }

    private func makeAttributedText() -> AttributedString {
        var output = AttributedString()

        for span in spans {
            var fragment = AttributedString(span.text)
            switch span.kind {
            case .equal:
                break
            case .insert:
                fragment.foregroundColor = DS.Colors.success
                fragment.backgroundColor = DS.Colors.successSubtle
            case .delete:
                fragment.foregroundColor = DS.Colors.error
                fragment.backgroundColor = DS.Colors.errorSubtle
                fragment.strikethroughStyle = Text.LineStyle(pattern: .solid, color: DS.Colors.error)
            }
            output.append(fragment)
        }

        return output
    }
}

// MARK: - Toolbar Divider

struct ToolbarDivider: View {
    var body: some View {
        Rectangle()
            .fill(DS.Colors.border)
            .frame(width: 1, height: 14)
    }
}

// MARK: - Styled Divider

struct StyledDivider: View {
    var opacity: Double = 0.08

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(opacity))
            .frame(height: 1)
    }
}

// MARK: - Compact Button

struct CompactButton: View {
    let icon: String
    var label: String? = nil
    var accessibilityLabel: String? = nil
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                if let label {
                    Text(label)
                        .font(DS.Typography.microFont)
                }
            }
            .foregroundStyle(isDisabled ? DS.Colors.textMuted : DS.Colors.textSecondary)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.xs)
                    .fill(isHovering ? DS.Colors.surfaceHover : DS.Colors.surfacePrimary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xs)
                    .strokeBorder(isHovering ? DS.Colors.border : DS.Colors.borderSubtle, lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.95 : 1)
            .opacity(isDisabled ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovering = $0 }
        .pressEvents(onPress: { isPressed = true }, onRelease: { isPressed = false })
        .animation(DS.Animation.micro, value: isPressed)
        .animation(DS.Animation.quick, value: isHovering)
        .accessibilityLabel(accessibilityLabel ?? label ?? icon.replacingOccurrences(of: ".", with: " "))
    }
}

// MARK: - Preset Picker (New)

struct PresetPicker<T: Hashable & Identifiable>: View where T: CaseIterable, T.AllCases: RandomAccessCollection {
    let title: String
    @Binding var selection: T
    let displayName: (T) -> String

    @State private var isHovering = false

    var body: some View {
        Menu {
            ForEach(Array(T.allCases), id: \.id) { option in
                Button {
                    selection = option
                } label: {
                    HStack {
                        Text(displayName(option))
                        if option.id == selection.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                Text(displayName(selection))
                    .font(DS.Typography.captionFont)
                    .foregroundStyle(DS.Colors.textPrimary)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DS.Colors.textTertiary)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .fill(isHovering ? DS.Colors.surfaceElevated : DS.Colors.surfacePrimary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .strokeBorder(isHovering ? DS.Colors.border : DS.Colors.borderSubtle, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .onHover { isHovering = $0 }
        .animation(DS.Animation.quick, value: isHovering)
    }
}

// MARK: - Loading Dots Animation

struct LoadingDots: View {
    @State private var animatingDots = [false, false, false]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(DS.Colors.accent)
                    .frame(width: 5, height: 5)
                    .scaleEffect(animatingDots[index] ? 1.2 : 0.6)
                    .opacity(animatingDots[index] ? 1 : 0.3)
            }
        }
        .onAppear {
            for index in 0..<3 {
                withAnimation(
                    .easeInOut(duration: 0.4)
                    .repeatForever(autoreverses: true)
                    .delay(Double(index) * 0.15)
                ) {
                    animatingDots[index] = true
                }
            }
        }
    }
}
