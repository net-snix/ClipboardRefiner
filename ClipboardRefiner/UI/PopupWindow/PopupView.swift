import SwiftUI

final class PopupViewModel: ObservableObject {
    let originalText: String

    @Published var selectedStyle: RewriteStyle
    @Published var outputText: String = ""
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var showOriginal: Bool = false

    var onComplete: ((PopupResult) -> Void)?

    private let engine = RewriteEngine.shared
    private var activeRewriteID: UUID?

    init(originalText: String, initialStyle: RewriteStyle) {
        self.originalText = originalText
        self.selectedStyle = initialStyle
    }

    func startRewrite() {
        guard !isLoading else { return }

        let rewriteID = UUID()
        activeRewriteID = rewriteID
        isLoading = true
        error = nil
        outputText = ""

        let options = RewriteOptions(
            style: selectedStyle,
            aggressiveness: SettingsManager.shared.aggressiveness,
            streaming: SettingsManager.shared.streamingEnabled
        )

        engine.rewrite(
            text: originalText,
            options: options,
            streamHandler: { [weak self] text in
                guard self?.activeRewriteID == rewriteID else { return }
                self?.outputText = text
            },
            completion: { [weak self] result in
                guard let self = self else { return }
                guard self.activeRewriteID == rewriteID else { return }
                self.activeRewriteID = nil
                self.isLoading = false

                switch result {
                case .success(let text):
                    self.outputText = text
                case .failure(let llmError):
                    self.error = llmError.localizedDescription
                }
            }
        )
    }

    func retry() {
        startRewrite()
    }

    func styleChanged() {
        if isLoading {
            engine.cancel()
            isLoading = false
        }
        startRewrite()
    }

    func replace() {
        onComplete?(.replace(outputText))
    }

    func copy() {
        onComplete?(.copy(outputText))
    }

    func cancel() {
        engine.cancel()
        onComplete?(.cancel)
    }

    func cleanup() {
        engine.cancel()
        activeRewriteID = nil
    }
}

struct PopupView: View {
    @ObservedObject var viewModel: PopupViewModel
    @State private var appearAnimationComplete = false

    var body: some View {
        VStack(spacing: 0) {
            headerView
                .opacity(appearAnimationComplete ? 1 : 0)
                .offset(y: appearAnimationComplete ? 0 : -6)

            StyledDivider()

            contentView
                .opacity(appearAnimationComplete ? 1 : 0)
                .offset(y: appearAnimationComplete ? 0 : 4)

            StyledDivider()

            footerView
                .opacity(appearAnimationComplete ? 1 : 0)
                .offset(y: appearAnimationComplete ? 0 : 6)
        }
        .frame(minWidth: 420, minHeight: 320)
        .background(
            ZStack {
                VisualEffectBlur(material: .popover, blendingMode: .behindWindow)

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.02),
                        Color.clear,
                        Color.black.opacity(0.02)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
        .onAppear {
            withAnimation(DS.Animation.smooth.delay(0.05)) {
                appearAnimationComplete = true
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: DS.Spacing.md) {
            // Style picker
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("STYLE")
                    .font(DS.Typography.microFont)
                    .tracking(0.8)
                    .foregroundStyle(DS.Colors.textTertiary)

                stylePickerMenu
            }

            Spacer()

            // Toggle original text
            IconButton(
                icon: viewModel.showOriginal ? "eye.slash" : "eye",
                action: {
                    withAnimation(DS.Animation.quick) {
                        viewModel.showOriginal.toggle()
                    }
                },
                isActive: viewModel.showOriginal,
                help: viewModel.showOriginal ? "Hide original" : "Show original"
            )
        }
        .padding(DS.Spacing.lg)
    }

    private var stylePickerMenu: some View {
        Menu {
            ForEach(RewriteStyle.userSelectableCases) { style in
                Button {
                    viewModel.selectedStyle = style
                    viewModel.styleChanged()
                } label: {
                    HStack {
                        Text(style.displayName)
                        if style == viewModel.selectedStyle {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.Colors.accent)

                Text(viewModel.selectedStyle.displayName)
                    .font(DS.Typography.bodyFont)
                    .foregroundStyle(DS.Colors.textPrimary)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DS.Colors.textTertiary)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .fill(DS.Colors.surfacePrimary)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.sm)
                            .strokeBorder(DS.Colors.borderSubtle, lineWidth: 1)
                    )
            )
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Content

    private var contentView: some View {
        VStack(spacing: DS.Spacing.md) {
            if viewModel.showOriginal {
                originalTextSection
            }

            outputTextSection
        }
        .padding(DS.Spacing.lg)
        .frame(maxHeight: .infinity)
    }

    private var originalTextSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            SectionHeader("Original", icon: "doc.text")

            ScrollView {
                Text(viewModel.originalText)
                    .font(DS.Typography.bodyFont)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(DS.Spacing.md)
            .frame(maxHeight: 100)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(DS.Colors.surfacePrimary)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .strokeBorder(DS.Colors.borderSubtle, lineWidth: 1)
                    )
            )
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity
        ))
    }

    private var outputTextSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                SectionHeader("Output", icon: "sparkles")

                if viewModel.isLoading {
                    LoadingDots()
                }

                Spacer()

                if let error = viewModel.error, !viewModel.outputText.isEmpty {
                    errorBadge(error)
                }
            }

            outputContent
        }
    }

    @ViewBuilder
    private var outputContent: some View {
        if viewModel.error != nil && viewModel.outputText.isEmpty {
            errorStateView
        } else {
            ScrollView {
                Text(viewModel.outputText.isEmpty ? "Processing\u{2026}" : viewModel.outputText)
                    .font(DS.Typography.bodyFont)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(viewModel.outputText.isEmpty ? DS.Colors.textMuted : DS.Colors.textPrimary)
            }
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(DS.Colors.inputBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .strokeBorder(DS.Colors.borderSubtle, lineWidth: 1)
                    )
            )
        }
    }

    private var errorStateView: some View {
        VStack(spacing: DS.Spacing.lg) {
            Spacer()

            VStack(spacing: DS.Spacing.md) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(DS.Colors.warning)
                    .glow(DS.Colors.warning, radius: 6, isActive: true)

                Text(viewModel.error ?? "An error occurred")
                    .font(DS.Typography.bodyFont)
                    .foregroundStyle(DS.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 240)
            }

            SecondaryActionButton(
                title: "Try Again",
                icon: "arrow.clockwise",
                accentColor: DS.Colors.accent
            ) {
                viewModel.retry()
            }
            .frame(width: 140)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .fill(DS.Colors.surfacePrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .strokeBorder(DS.Colors.borderSubtle, lineWidth: 1)
                )
        )
    }

    private func errorBadge(_ message: String) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .semibold))
            Text(message)
                .font(DS.Typography.microFont)
                .lineLimit(1)
        }
        .foregroundStyle(DS.Colors.warning)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
        .background(
            Capsule()
                .fill(DS.Colors.warningSubtle)
                .overlay(
                    Capsule()
                        .strokeBorder(DS.Colors.warning.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack(spacing: DS.Spacing.md) {
            // Cancel button
            Button {
                viewModel.cancel()
            } label: {
                Text("Cancel")
                    .font(DS.Typography.captionFont)
                    .foregroundStyle(DS.Colors.textSecondary)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.sm)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])

            Spacer()

            // Action buttons
            HStack(spacing: DS.Spacing.sm) {
                CompactButton(
                    icon: "arrow.clockwise",
                    label: "Retry",
                    isDisabled: viewModel.isLoading
                ) {
                    viewModel.retry()
                }

                CompactButton(
                    icon: "doc.on.doc",
                    label: "Copy",
                    isDisabled: viewModel.outputText.isEmpty || viewModel.isLoading
                ) {
                    viewModel.copy()
                }

                // Primary action - Replace
                PrimaryActionButton(
                    title: "Replace",
                    icon: "arrow.down.to.line",
                    isDisabled: viewModel.outputText.isEmpty || viewModel.isLoading,
                    accentColor: DS.Colors.accent
                ) {
                    viewModel.replace()
                }
                .frame(width: 120)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(DS.Spacing.lg)
    }
}

// MARK: - Preview

#if DEBUG
struct PopupView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = PopupViewModel(
            originalText: "This is some sample text that needs to be rewritten.",
            initialStyle: .rewrite
        )
        viewModel.outputText = "This is sample text requiring revision."

        return PopupView(viewModel: viewModel)
            .frame(width: 500, height: 400)
    }
}
#endif
