import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct MenuBarView: View {
    let onDismiss: () -> Void

    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var engine = RewriteEngine.shared

    private let maxAttachments = 4
    private let maxAttachmentBytes = 8 * 1024 * 1024
    private let supportedAttachmentMIMETypes: Set<String> = [
        "image/png",
        "image/jpeg",
        "image/heic",
        "image/heif",
        "image/tiff"
    ]
    private let baseWindowMinWidth: CGFloat = 920
    private let baseWindowInitialHeight: CGFloat = 720
    private let baseWindowFloorHeight: CGFloat = 520
    private let maxVisibleTextLines: CGFloat = 20
    private let inputMinVisibleTextLines: CGFloat = 8
    private let resultMinVisibleTextLines: CGFloat = 6
    private let resultSectionChromeHeight: CGFloat = 82
    private let windowMaxHeight: CGFloat = 1240
    private let imagePanelWidth: CGFloat = 320
    private let windowSizingDebounceInterval: TimeInterval = 0.04

    @Namespace private var glassNamespace

    @State private var inputText = ""
    @State private var outputText = ""
    @State private var attachments: [AttachmentItem] = []
    @State private var activeRequestID: UUID?
    @State private var isDropTargeted = false
    @State private var errorText: String?
    @State private var runSummary: String?
    @State private var shareAnchor: NSView?
    @State private var hasAppeared = false
    @State private var showResultPanel = false
    @State private var windowMinHeight: CGFloat = 720
    @State private var inputBoxHeight: CGFloat = 170
    @State private var resultBoxHeight: CGFloat = 120
    @State private var isAutoConsumingPastedImagePath = false
    @State private var isApplyingClipboardAutoload = false
    @State private var measuredContentHeight: CGFloat = 0
    @State private var pendingWindowSizingWorkItem: DispatchWorkItem?
    @State private var pendingWindowSizingAnimated = false

    init(onDismiss: @escaping () -> Void = {}) {
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            background

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    headerSection
                        .staggeredAppear(index: 0, isVisible: hasAppeared)

                    controlsSection
                        .staggeredAppear(index: 1, isVisible: hasAppeared)

                    composerSection
                        .staggeredAppear(index: 2, isVisible: hasAppeared)

                    actionsSection
                        .staggeredAppear(index: 3, isVisible: hasAppeared)

                    resultSection
                        .staggeredAppear(index: 4, isVisible: hasAppeared)
                }
                .padding(DS.Spacing.xl)
                .padding(.bottom, DS.Spacing.xxxl)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: MenuBarContentHeightPreferenceKey.self,
                            value: ceil(proxy.size.height)
                        )
                    }
                )
            }
        }
        .frame(minWidth: baseWindowMinWidth, minHeight: windowMinHeight)
        .background(ShareSheetAnchorView(anchor: $shareAnchor).frame(width: 0, height: 0))
        .onAppear {
            let restoredDraft = restoreDraftIfNeeded()
            if settings.autoLoadClipboard, !restoredDraft {
                loadClipboard(force: true, persistDraft: false)
            }
            updateWindowSizing(animated: false)
            withAnimation(DS.Animation.smooth.delay(0.05)) {
                hasAppeared = true
            }
        }
        .onDisappear {
            pendingWindowSizingWorkItem?.cancel()
            pendingWindowSizingWorkItem = nil
            pendingWindowSizingAnimated = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipboardRefinerMenuPopoverDidShow)) { _ in
            if settings.autoLoadClipboard {
                loadClipboard(
                    force: inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    persistDraft: false
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipboardRefinerMenuPrefillText)) { notification in
            guard let text = notification.userInfo?["text"] as? String else { return }
            inputText = text
            outputText = ""
            errorText = nil
            if let action = notification.userInfo?["action"] as? String, action == "explain" {
                run(style: .explain)
            }
        }
        .onChange(of: inputText) { oldValue, newValue in
            if !isApplyingClipboardAutoload {
                settings.saveMenuDraftText(newValue)
            }
            maybeConsumePastedImagePath(previousValue: oldValue, currentValue: newValue)
        }
        .onChange(of: outputText) { _, _ in
            syncResultPanelVisibility()
        }
        .onChange(of: engine.isProcessing) { _, _ in
            syncResultPanelVisibility()
        }
        .onChange(of: errorText) { _, _ in
            syncResultPanelVisibility()
        }
        .onChange(of: showResultPanel) { _, _ in
            scheduleWindowSizingUpdate(animated: true)
        }
        .onChange(of: inputBoxHeight) { _, _ in
            scheduleWindowSizingUpdate(animated: false)
        }
        .onChange(of: resultBoxHeight) { _, _ in
            scheduleWindowSizingUpdate(animated: false)
        }
        .onChange(of: shareAnchor?.window != nil) { _, hasWindow in
            guard hasWindow else { return }
            scheduleWindowSizingUpdate(animated: false)
        }
        .onPreferenceChange(MenuBarContentHeightPreferenceKey.self) { newHeight in
            guard newHeight > 0 else { return }
            guard abs(measuredContentHeight - newHeight) > 0.5 else { return }
            measuredContentHeight = newHeight
            scheduleWindowSizingUpdate(animated: false)
        }
    }

    private var background: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.22),
                    Color.black.opacity(0.1),
                    Color.black.opacity(0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(DS.Colors.accent.opacity(0.25))
                .blur(radius: 120)
                .offset(x: -280, y: -320)

            Circle()
                .fill(DS.Colors.secondary.opacity(0.22))
                .blur(radius: 140)
                .offset(x: 300, y: 300)
        }
        .ignoresSafeArea()
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: DS.Spacing.lg) {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: "text.quote")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.Colors.accent)
                    .frame(width: 36, height: 36)
                    .glassAccentCapsule(active: true, tint: DS.Colors.accent)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Clipboard Refiner")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("ClipboardRefiner style, rebuilt for window workflow")
                        .font(DS.Typography.captionFont)
                        .foregroundStyle(Color.white.opacity(0.65))
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: DS.Spacing.sm) {
                StatusPill(
                    isConnected: providerReady,
                    label: providerStatusLabel
                )

                settingsLinkButton
                IconButton(icon: "xmark", action: onDismiss, help: "Close", size: 30)
            }
        }
    }

    private var settingsLinkButton: some View {
        SettingsLink {
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.Colors.textSecondary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .fill(Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help("Settings")
        .accessibilityLabel("Settings")
    }

    private var controlsSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                SectionHeader("Provider", icon: "network")

                Picker("Provider", selection: $settings.selectedProvider) {
                    ForEach(LLMProviderType.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.segmented)

                HStack(alignment: .top, spacing: DS.Spacing.sm) {
                    controlColumn("MODEL") {
                        modelControl
                    }

                    if showsOpenAIReasoningEffort {
                        controlColumn("REASONING") {
                            reasoningEffortControl
                        }
                    }

                    controlColumn("SKILL") {
                        skillControl
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .glassMorph(id: "controls", namespace: glassNamespace)
    }

    @ViewBuilder
    private var modelControl: some View {
        if settings.selectedProvider == .local {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                if settings.localModelPaths.isEmpty {
                    Text("No local models configured. Add paths in Settings.")
                        .font(DS.Typography.microFont)
                        .foregroundStyle(DS.Colors.textMuted)
                } else {
                    Picker("Local model", selection: localModelSelectionBinding) {
                        ForEach(settings.localModelPaths) { entry in
                            Text(entry.modelName).tag(entry.modelName)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 320, alignment: .leading)
                }

                if let selectedPath = settings.selectedLocalModelPath {
                    Text(selectedPath)
                        .font(DS.Typography.microFont)
                        .foregroundStyle(DS.Colors.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 340, alignment: .leading)
                }

                if settings.selectedLocalModelPath != nil {
                    HStack(spacing: DS.Spacing.sm) {
                        Text(isSelectedLocalModelLoaded ? "Loaded in memory" : "Not loaded")
                            .font(DS.Typography.microFont)
                            .foregroundStyle(DS.Colors.textMuted)

                        Button(localModelActionTitle) {
                            toggleLocalModelLoadState()
                        }
                        .disabled(engine.isUnloadingLocalModel || engine.isLoadingLocalModel || engine.isProcessing)
                    }

                    Toggle("Keep loaded", isOn: $settings.keepLocalModelLoaded)
                        .font(DS.Typography.microFont)
                        .toggleStyle(.switch)
                }
            }
        } else {
            Picker("Model", selection: cloudModelSelectionBinding) {
                ForEach(settings.selectedProvider.availableModels, id: \.self) { model in
                    Text(SettingsManager.displayModelName(model, for: settings.selectedProvider)).tag(model)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 150, alignment: .leading)
        }
    }

    private var localModelSelectionBinding: Binding<String> {
        Binding(
            get: {
                resolvedLocalModelSelection
            },
            set: { newValue in
                settings.selectedModel = newValue
            }
        )
    }

    private var cloudModelSelectionBinding: Binding<String> {
        Binding(
            get: {
                resolvedCloudModelSelection(for: settings.selectedProvider)
            },
            set: { newValue in
                settings.selectedModel = newValue
            }
        )
    }

    private var resolvedLocalModelSelection: String {
        guard let first = settings.localModelPaths.first?.modelName else {
            return ""
        }

        if let matched = settings.localModelPaths.first(where: {
            $0.modelName.caseInsensitiveCompare(settings.selectedModel) == .orderedSame
        }) {
            return matched.modelName
        }

        return first
    }

    private func resolvedCloudModelSelection(for provider: LLMProviderType) -> String {
        let models = provider.availableModels
        guard !models.isEmpty else { return settings.selectedModel }

        if models.contains(settings.selectedModel) {
            return settings.selectedModel
        }

        let preferred = settings.modelDefault(for: provider)
        if models.contains(preferred) {
            return preferred
        }

        return models[0]
    }

    private var skillControl: some View {
        Picker("Skill", selection: $settings.selectedSkillID) {
            Text("None").tag(PromptSkillBundle.noneID)
            ForEach(PromptSkillBundle.bundled, id: \.id) { skill in
                Text(skill.name).tag(skill.id)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 170, alignment: .leading)
    }

    private var reasoningEffortControl: some View {
        Picker("Reasoning effort", selection: $settings.openAIReasoningEffort) {
            ForEach(OpenAIReasoningEffort.allCases, id: \.self) { effort in
                Text(effort.displayName).tag(effort)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 130, alignment: .leading)
    }

    private var showsOpenAIReasoningEffort: Bool {
        guard settings.selectedProvider == .openai else { return false }
        return SettingsManager.isOpenAIReasoningModel(resolvedCloudModelSelection(for: .openai))
    }

    private func controlColumn<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(title)
                .font(DS.Typography.microFont)
                .tracking(0.8)
                .foregroundStyle(DS.Colors.textTertiary)
            content()
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var composerSection: some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            inputSection
            attachmentsSection
        }
    }

    private var inputSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                SectionHeader("Input", icon: "square.and.pencil") {
                    AnyView(
                        Picker("Style", selection: $settings.defaultStyle) {
                            ForEach(RewriteStyle.userSelectableCases) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 220)
                    )
                }

                TextBox(
                    text: $inputText,
                    placeholder: "Paste text or drop images. Keep empty to generate from image context.",
                    minHeight: inputTextBoxMinHeight,
                    maxHeight: textBoxMaxHeight,
                    onHeightChange: { height in
                        inputBoxHeight = height
                    },
                    onPasteImageProviders: handleInputPaste(providers:)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassMorph(id: "input", namespace: glassNamespace)
    }

    private var attachmentsSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                SectionHeader("Image Context", icon: "photo.on.rectangle") {
                    AnyView(
                        Tag(
                            text: "\(attachments.count)/\(maxAttachments)",
                            color: attachments.isEmpty ? DS.Colors.textTertiary : DS.Colors.accent,
                            size: .small
                        )
                    )
                }

                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "tray.and.arrow.down")
                            .foregroundStyle(isDropTargeted ? DS.Colors.accent : DS.Colors.textTertiary)
                        Text(attachments.isEmpty ? "Drop or paste up to \(maxAttachments) images" : "Drop or paste to add more images")
                            .font(DS.Typography.captionFont)
                            .foregroundStyle(DS.Colors.textSecondary)
                    }

                    if attachments.isEmpty {
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text("PNG, JPEG, HEIC, TIFF")
                                .font(DS.Typography.microFont)
                                .foregroundStyle(DS.Colors.textMuted)
                            Text("Max 8 MB each")
                                .font(DS.Typography.microFont)
                                .foregroundStyle(DS.Colors.textMuted)
                        }
                        .padding(DS.Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.sm)
                                .fill(DS.Colors.surfaceSecondary)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.sm)
                                .strokeBorder(DS.Colors.borderSubtle, lineWidth: 1)
                        )
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                                ForEach(attachments) { item in
                                    AttachmentChip(item: item) {
                                        removeAttachment(item.id)
                                    }
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }

                    Text("Cloud providers only. Local provider ignores image context.")
                        .font(DS.Typography.microFont)
                        .foregroundStyle(DS.Colors.textMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(DS.Spacing.md)
                .frame(
                    maxWidth: .infinity,
                    minHeight: composerPanelHeight,
                    maxHeight: composerPanelHeight,
                    alignment: .topLeading
                )
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .fill(isDropTargeted ? DS.Colors.accentSubtle : DS.Colors.surfacePrimary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .stroke(
                            isDropTargeted ? DS.Colors.accent.opacity(0.55) : DS.Colors.border,
                            style: StrokeStyle(lineWidth: isDropTargeted ? 1.4 : 1, dash: attachments.isEmpty ? [6, 4] : [])
                        )
                )
                .onDrop(
                    of: [UTType.fileURL.identifier, UTType.image.identifier],
                    isTargeted: $isDropTargeted,
                    perform: handleDrop
                )
            }
        }
        .frame(width: imagePanelWidth, alignment: .topLeading)
        .glassMorph(id: "attachments", namespace: glassNamespace)
    }

    private var actionsSection: some View {
        HStack(spacing: DS.Spacing.md) {
            GlassAwareActionButton(
                title: engine.isProcessing ? "Enhancing" : "Enhance",
                icon: "sparkles",
                style: .prominent,
                isDisabled: engine.isProcessing || engine.isLoadingLocalModel || engine.isUnloadingLocalModel || !canRun,
                action: {
                    run(style: settings.defaultStyle)
                }
            )

            GlassAwareActionButton(
                title: "Cancel",
                icon: "stop.fill",
                style: .secondary,
                isDisabled: !engine.isProcessing,
                action: cancelCurrentRun
            )

            GlassAwareActionButton(
                title: "Explain",
                icon: "text.book.closed",
                style: .secondary,
                isDisabled: engine.isProcessing || engine.isLoadingLocalModel || engine.isUnloadingLocalModel || !canRun,
                action: {
                    run(style: .explain)
                }
            )

            GlassAwareActionButton(
                title: "Clear",
                icon: "trash",
                style: .secondary,
                isDisabled: engine.isProcessing || engine.isLoadingLocalModel || engine.isUnloadingLocalModel,
                action: clearAll
            )
        }
        .glassMorph(id: "actions", namespace: glassNamespace)
    }

    @ViewBuilder
    private var resultSection: some View {
        if showResultPanel {
            GlassCard {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    SectionHeader("Result", icon: "sparkles") {
                        AnyView(
                            HStack(spacing: DS.Spacing.sm) {
                                if let runSummary {
                                    Text(runSummary)
                                        .font(DS.Typography.microFont)
                                        .foregroundStyle(DS.Colors.textMuted)
                                }

                                CompactButton(icon: "doc.on.doc", label: "Copy", isDisabled: outputText.isEmpty) {
                                    copyResult()
                                }

                                CompactButton(icon: "square.and.arrow.up", label: "Share", isDisabled: outputText.isEmpty) {
                                    shareResult()
                                }
                            }
                        )
                    }

                    TextBox(
                        text: .constant(outputText),
                        placeholder: engine.isProcessing ? "Processing…" : "Run Enhance to generate output.",
                        isEditable: false,
                        minHeight: resultTextBoxMinHeight,
                        maxHeight: textBoxMaxHeight,
                        shouldMeasureHeight: !engine.isProcessing,
                        onHeightChange: { height in
                            guard !engine.isProcessing else { return }
                            resultBoxHeight = height
                        }
                    )
                    .padding(.bottom, DS.Spacing.sm)

                    if let errorText {
                        Toast(message: errorText, icon: "exclamationmark.triangle.fill")
                    }
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .opacity
            ))
            .glassMorph(id: "result", namespace: glassNamespace)
        }
    }

    private var canRun: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    private var shouldShowResultPanel: Bool {
        engine.isProcessing || !outputText.isEmpty || errorText != nil
    }

    private func syncResultPanelVisibility() {
        let shouldShow = shouldShowResultPanel
        guard shouldShow != showResultPanel else { return }

        withAnimation(DS.Animation.standard) {
            showResultPanel = shouldShow
        }
    }

    private var providerReady: Bool {
        if settings.selectedProvider == .local {
            return settings.isSelectedLocalModelConfigured
        }
        return settings.hasAPIKey(for: settings.selectedProvider)
    }

    private var providerStatusLabel: String {
        if providerReady {
            return "Ready"
        }

        if settings.selectedProvider == .local {
            return "Model path missing"
        }

        return "Provider key missing"
    }

    private var optionAttachments: [ImageAttachment] {
        attachments.map(\.attachment)
    }

    private var selectedProviderModelName: String {
        settings.modelDefault(for: settings.selectedProvider)
    }

    private var isSelectedLocalModelLoaded: Bool {
        guard engine.isLocalModelLoaded else { return false }
        guard let loadedModel = engine.loadedLocalModelName else { return false }
        return loadedModel.caseInsensitiveCompare(settings.selectedModel) == .orderedSame
    }

    private var bodyLineHeight: CGFloat {
        let font = NSFont.systemFont(ofSize: 13, weight: .regular)
        return ceil(font.ascender - font.descender + font.leading)
    }

    private var textBoxMaxHeight: CGFloat {
        ceil(maxVisibleTextLines * bodyLineHeight + DS.Spacing.xl)
    }

    private var inputTextBoxMinHeight: CGFloat {
        ceil(inputMinVisibleTextLines * bodyLineHeight + DS.Spacing.xl)
    }

    private var resultTextBoxMinHeight: CGFloat {
        ceil(resultMinVisibleTextLines * bodyLineHeight + DS.Spacing.xl)
    }

    private var composerPanelHeight: CGFloat {
        max(inputTextBoxMinHeight, inputBoxHeight)
    }

    private var desiredWindowMinHeight: CGFloat {
        let lowerBound = baseWindowFloorHeight

        if measuredContentHeight > 0 {
            return min(max(lowerBound, measuredContentHeight), windowMaxHeight)
        }

        let resultExpansion = showResultPanel ? (resultBoxHeight + resultSectionChromeHeight) : 0
        let inputExpansion = max(0, inputBoxHeight - inputTextBoxMinHeight)
        let target = baseWindowInitialHeight + resultExpansion + inputExpansion
        return min(max(lowerBound, target), windowMaxHeight)
    }

    private func updateWindowSizing(animated: Bool) {
        let targetHeight = desiredWindowMinHeight
        guard abs(windowMinHeight - targetHeight) > 0.5 else { return }
        windowMinHeight = targetHeight

        guard let window = shareAnchor?.window else { return }

        window.minSize = NSSize(width: baseWindowMinWidth, height: targetHeight)

        let currentFrame = window.frame
        let shouldGrow = currentFrame.height + 0.5 < targetHeight
        let shouldShrink = measuredContentHeight > 0 && currentFrame.height - targetHeight > 12

        if shouldGrow || shouldShrink {
            let delta = targetHeight - currentFrame.height
            var frame = currentFrame
            frame.origin.y -= delta
            frame.size.height = targetHeight
            window.setFrame(frame, display: true, animate: animated)
        }
    }

    private func scheduleWindowSizingUpdate(animated: Bool) {
        pendingWindowSizingAnimated = pendingWindowSizingAnimated || animated
        pendingWindowSizingWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            let shouldAnimate = pendingWindowSizingAnimated
            pendingWindowSizingAnimated = false
            pendingWindowSizingWorkItem = nil
            updateWindowSizing(animated: shouldAnimate)
        }

        pendingWindowSizingWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + windowSizingDebounceInterval,
            execute: workItem
        )
    }

    private func maybeConsumePastedImagePath(previousValue: String, currentValue: String) {
        guard !isAutoConsumingPastedImagePath else { return }
        guard settings.selectedProvider != .local else { return }
        guard attachments.count < maxAttachments else { return }
        guard previousValue != currentValue else { return }

        let previousLength = (previousValue as NSString).length
        let currentLength = (currentValue as NSString).length
        let lengthDelta = abs(currentLength - previousLength)
        let previousHasPathMarkers = containsPotentialPathMarker(previousValue)
        let currentHasPathMarkers = containsPotentialPathMarker(currentValue)
        guard lengthDelta > 1 || previousHasPathMarkers || currentHasPathMarkers else { return }
        guard currentHasPathMarkers else { return }

        if let inserted = insertedSegment(from: previousValue, to: currentValue),
           let fileURL = imageFileURLFromSingleLineText(inserted) {
            consumePastedImagePath(fileURL, expectedInput: currentValue, restoredInput: previousValue)
            return
        }

        let previousTrimmed = previousValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard previousTrimmed.isEmpty, let fileURL = imageFileURLFromSingleLineText(currentValue) else { return }
        consumePastedImagePath(fileURL, expectedInput: currentValue, restoredInput: "")
    }

    private func containsPotentialPathMarker(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.contains("/")
            || value.contains("\\")
            || value.contains("~/")
            || value.contains("file://")
    }

    private func consumePastedImagePath(_ fileURL: URL, expectedInput: String, restoredInput: String) {
        isAutoConsumingPastedImagePath = true

        Task {
            let attached = await loadAttachment(fromFile: fileURL)
            await MainActor.run {
                defer { isAutoConsumingPastedImagePath = false }
                guard attached else { return }
                guard inputText == expectedInput else { return }
                inputText = restoredInput
                if restoredInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    settings.clearMenuDraftText()
                }
            }
        }
    }

    private func insertedSegment(from previousValue: String, to currentValue: String) -> String? {
        let previousNSString = previousValue as NSString
        let currentNSString = currentValue as NSString

        let previousLength = previousNSString.length
        let currentLength = currentNSString.length
        let sharedLength = min(previousLength, currentLength)

        var prefixLength = 0
        while prefixLength < sharedLength,
              previousNSString.character(at: prefixLength) == currentNSString.character(at: prefixLength) {
            prefixLength += 1
        }

        var previousSuffixStart = previousLength
        var currentSuffixStart = currentLength
        while previousSuffixStart > prefixLength,
              currentSuffixStart > prefixLength,
              previousNSString.character(at: previousSuffixStart - 1) == currentNSString.character(at: currentSuffixStart - 1) {
            previousSuffixStart -= 1
            currentSuffixStart -= 1
        }

        guard currentSuffixStart > prefixLength else { return nil }
        let inserted = currentNSString.substring(
            with: NSRange(location: prefixLength, length: currentSuffixStart - prefixLength)
        )
        let normalized = inserted.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func imageFileURLFromSingleLineText(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.contains("\n") else { return nil }

        let unquoted: String
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) || (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            unquoted = String(trimmed.dropFirst().dropLast())
        } else {
            unquoted = trimmed
        }

        let fileURL: URL
        if let parsedURL = URL(string: unquoted), parsedURL.isFileURL {
            fileURL = parsedURL
        } else {
            let expandedPath = (unquoted as NSString).expandingTildeInPath
            guard expandedPath.hasPrefix("/") else { return nil }
            fileURL = URL(fileURLWithPath: expandedPath)
        }

        var isDirectory: ObjCBool = false
        let standardizedURL = fileURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardizedURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return nil
        }

        guard let mimeType = UTType(filenameExtension: standardizedURL.pathExtension)?.preferredMIMEType?.lowercased() else {
            return nil
        }
        guard supportedAttachmentMIMETypes.contains(mimeType) else { return nil }

        return standardizedURL
    }

    private func loadClipboard(force: Bool, persistDraft: Bool = true) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        guard force || inputText.isEmpty else { return }

        if !persistDraft {
            isApplyingClipboardAutoload = true
        }
        inputText = text
        guard !isApplyingClipboardAutoload else {
            DispatchQueue.main.async {
                isApplyingClipboardAutoload = false
            }
            return
        }
    }

    private func run(style: RewriteStyle) {
        guard canRun else { return }
        guard validateRunPreconditions() else { return }

        errorText = nil
        runSummary = nil

        let start = Date()
        let requestID = UUID()
        activeRequestID = requestID

        let normalizedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let promptText = normalizedInput.isEmpty
            ? "Generate a polished social post using attached images as context."
            : normalizedInput

        if settings.selectedProvider == .local && !isSelectedLocalModelLoaded {
            runSummary = "Loading local model…"
            engine.loadLocalModel { loadResult in
                guard activeRequestID == requestID else { return }

                switch loadResult {
                case .success:
                    runSummary = nil
                    performRewrite(
                        style: style,
                        promptText: promptText,
                        start: start,
                        requestID: requestID
                    )
                case .failure(let error):
                    runSummary = nil
                    errorText = error.localizedDescription
                }
            }
            return
        }

        performRewrite(
            style: style,
            promptText: promptText,
            start: start,
            requestID: requestID
        )
    }

    private func cancelCurrentRun() {
        activeRequestID = nil
        engine.cancel()
        runSummary = "Cancelled"
    }

    private func performRewrite(style: RewriteStyle, promptText: String, start: Date, requestID: UUID) {
        let options = RewriteOptions(
            style: style,
            aggressiveness: settings.aggressiveness,
            streaming: settings.streamingEnabled,
            skill: settings.selectedSkill,
            imageAttachments: optionAttachments
        )

        engine.rewrite(text: promptText, options: options, streamHandler: { streamedText in
            guard activeRequestID == requestID else { return }
            outputText = streamedText
        }) { result in
            guard activeRequestID == requestID else { return }

            switch result {
            case .success(let newValue):
                outputText = newValue
                let elapsed = max(0.05, Date().timeIntervalSince(start))
                runSummary = "\(style.displayName) • \(selectedProviderModelName) • \(String(format: "%.2fs", elapsed))"

                if settings.autoCopyEnabled {
                    copyResult()
                }

            case .failure(let error):
                errorText = error.localizedDescription
            }
        }
    }

    private var localModelActionTitle: String {
        if engine.isUnloadingLocalModel { return "Unloading…" }
        if engine.isLoadingLocalModel { return "Loading…" }
        return isSelectedLocalModelLoaded ? "Unload" : "Load"
    }

    private func toggleLocalModelLoadState() {
        if isSelectedLocalModelLoaded {
            unloadLocalModel()
        } else {
            loadLocalModel()
        }
    }

    private func loadLocalModel() {
        errorText = nil
        runSummary = "Loading local model…"
        engine.loadLocalModel { result in
            switch result {
            case .success:
                runSummary = "Local model loaded"
            case .failure(let error):
                runSummary = nil
                errorText = error.localizedDescription
            }
        }
    }

    private func unloadLocalModel() {
        errorText = nil
        runSummary = nil
        engine.unloadLocalModel { result in
            switch result {
            case .success:
                runSummary = "Local model unloaded"
            case .failure(let error):
                errorText = error.localizedDescription
            }
        }
    }

    private func clearAll() {
        inputText = ""
        outputText = ""
        errorText = nil
        runSummary = nil
        attachments = []
        settings.clearMenuDraftText()
    }

    private func copyResult() {
        guard !outputText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(outputText, forType: .string)
    }

    private func shareResult() {
        guard !outputText.isEmpty, let shareAnchor else { return }

        var items: [Any] = [outputText]
        if let first = attachments.first?.thumbnail {
            items.append(first)
        }

        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: shareAnchor.bounds, of: shareAnchor, preferredEdge: .maxY)
    }

    private func removeAttachment(_ id: UUID) {
        withAnimation(DS.Animation.quick) {
            attachments.removeAll { $0.id == id }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        guard settings.selectedProvider != .local else {
            errorText = "Local provider is text-only. Remove images or switch to a cloud provider."
            return false
        }

        let remaining = maxAttachments - attachments.count
        guard remaining > 0 else { return false }

        var accepted = false
        for provider in providers.prefix(remaining) {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let url = Self.url(from: item) else { return }
                    Task {
                        await loadAttachment(fromFile: url)
                    }
                }
                continue
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                accepted = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    Task {
                        await loadAttachment(fromData: data, filename: "drop-\(Int(Date().timeIntervalSince1970)).png", mimeType: "image/png")
                    }
                }
            }
        }

        return accepted
    }

    private func handleInputPaste(providers: [NSItemProvider]) {
        _ = handleDrop(providers: providers)
    }

    private func appendAttachment(_ item: AttachmentItem) -> Bool {
        guard attachments.count < maxAttachments else { return false }
        guard !attachments.contains(where: { $0.attachment.hash == item.attachment.hash }) else { return true }
        withAnimation(DS.Animation.standard) {
            attachments.append(item)
        }
        return true
    }

    private func loadAttachment(fromFile url: URL) async -> Bool {
        let loadSpan = PerfTelemetry.begin(
            "attachments.load_file",
            fields: [
                "extension": url.pathExtension.lowercased(),
                "filename_len": "\(url.lastPathComponent.count)"
            ]
        )

        let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        if resourceValues?.isRegularFile == false {
            PerfTelemetry.end(loadSpan, fields: ["status": "not_regular_file"])
            return false
        }

        if let fileSize = resourceValues?.fileSize, fileSize > maxAttachmentBytes {
            await MainActor.run {
                let bytes = ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
                errorText = "\(url.lastPathComponent) is too large (\(bytes)). Max size is 8 MB per image."
            }
            PerfTelemetry.end(
                loadSpan,
                fields: [
                    "status": "too_large",
                    "bytes": "\(fileSize)"
                ]
            )
            return false
        }

        let data = await Task.detached(priority: .utility) {
            try? Data(contentsOf: url, options: [.mappedIfSafe])
        }.value
        guard let data else {
            PerfTelemetry.end(loadSpan, fields: ["status": "read_failed"])
            return false
        }

        let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/png"
        let didAttach = await loadAttachment(fromData: data, filename: url.lastPathComponent, mimeType: mimeType)
        PerfTelemetry.end(
            loadSpan,
            fields: [
                "status": didAttach ? "attached" : "rejected",
                "bytes": "\(data.count)"
            ]
        )
        return didAttach
    }

    private func loadAttachment(fromData data: Data, filename: String, mimeType: String) async -> Bool {
        let normalizedMimeType = mimeType.lowercased()
        let prepareSpan = PerfTelemetry.begin(
            "attachments.prepare",
            fields: [
                "mime": normalizedMimeType,
                "bytes": "\(data.count)",
                "filename_len": "\(filename.count)"
            ]
        )

        guard supportedAttachmentMIMETypes.contains(normalizedMimeType) else {
            await MainActor.run {
                errorText = "Unsupported image format for \(filename). Use PNG, JPEG, HEIC, or TIFF."
            }
            PerfTelemetry.end(prepareSpan, fields: ["status": "unsupported_format"])
            return false
        }

        guard data.count <= maxAttachmentBytes else {
            await MainActor.run {
                let bytes = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
                errorText = "\(filename) is too large (\(bytes)). Max size is 8 MB per image."
            }
            PerfTelemetry.end(prepareSpan, fields: ["status": "too_large"])
            return false
        }

        let attachment = ImageAttachment(filename: filename, mimeType: mimeType, data: data)
        let thumbnail = await Task.detached(priority: .utility) {
            Self.makeThumbnail(from: data)
        }.value
        let item = AttachmentItem(attachment: attachment, thumbnail: thumbnail, byteCount: data.count)
        let didAttach = await MainActor.run {
            let attached = appendAttachment(item)
            if attached {
                errorText = nil
            }
            return attached
        }
        PerfTelemetry.end(
            prepareSpan,
            fields: [
                "status": didAttach ? "attached" : "duplicate_or_limit",
                "thumbnail_present": thumbnail == nil ? "0" : "1"
            ]
        )
        return didAttach
    }

    private func restoreDraftIfNeeded() -> Bool {
        let trimmedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedInput.isEmpty else { return false }

        let savedDraft = settings.loadMenuDraftText()
        guard !savedDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        inputText = savedDraft
        return true
    }

    private func validateRunPreconditions() -> Bool {
        if settings.selectedProvider == .local && !attachments.isEmpty {
            errorText = "Local provider is text-only. Remove images or switch to a cloud provider."
            return false
        }

        return true
    }

    nonisolated private static func makeThumbnail(from data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return NSImage(data: data)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 120,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return NSImage(data: data)
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: 120, height: 120))
    }

    private static func url(from item: NSSecureCoding?) -> URL? {
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }
        if let url = item as? URL {
            return url
        }
        if let str = item as? String {
            return URL(string: str)
        }
        return nil
    }
}

private struct AttachmentItem: Identifiable {
    let attachment: ImageAttachment
    let thumbnail: NSImage?
    let byteCount: Int

    var id: UUID { attachment.id }
}

private struct MenuBarContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct AttachmentChip: View {
    let item: AttachmentItem
    let onRemove: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            if let thumbnail = item.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Colors.textTertiary)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(DS.Colors.surfacePrimary)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.attachment.filename)
                    .font(DS.Typography.captionFont)
                    .lineLimit(1)
                    .foregroundStyle(DS.Colors.textSecondary)

                Text(metadataLabel)
                    .font(DS.Typography.microFont)
                    .lineLimit(1)
                    .foregroundStyle(DS.Colors.textMuted)
            }

            Spacer(minLength: DS.Spacing.sm)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DS.Colors.textMuted)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle()
                            .fill(DS.Colors.surfacePrimary)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .fill(isHovering ? DS.Colors.surfaceHover : DS.Colors.surfaceSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .strokeBorder(DS.Colors.borderSubtle, lineWidth: 1)
        )
        .onHover { isHovering = $0 }
        .animation(DS.Animation.micro, value: isHovering)
    }

    private var metadataLabel: String {
        let format = item.attachment.mimeType
            .replacingOccurrences(of: "image/", with: "")
            .uppercased()
        let size = ByteCountFormatter.string(fromByteCount: Int64(item.byteCount), countStyle: .file)
        return "\(format) | \(size)"
    }
}

#if DEBUG
struct MenuBarView_Previews: PreviewProvider {
    static var previews: some View {
        MenuBarView()
            .frame(width: 920, height: 760)
    }
}
#endif
