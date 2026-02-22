import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct MenuBarView: View {
    let onDismiss: () -> Void

    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var engine = RewriteEngine.shared

    private let maxAttachments = 4
    private let composerFieldHeight: CGFloat = 300
    private let imagePanelWidth: CGFloat = 320

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
            }
        }
        .frame(minWidth: 820, minHeight: 720)
        .background(ShareSheetAnchorView(anchor: $shareAnchor).frame(width: 0, height: 0))
        .onAppear {
            if settings.autoLoadClipboard {
                loadClipboard(force: true)
            }
            withAnimation(DS.Animation.smooth.delay(0.05)) {
                hasAppeared = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipboardRefinerMenuPopoverDidShow)) { _ in
            if settings.autoLoadClipboard {
                loadClipboard(force: true)
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
        .onChange(of: outputText) { _, value in
            let shouldShow = !value.isEmpty || engine.isProcessing
            guard shouldShow != showResultPanel else { return }

            withAnimation(DS.Animation.standard) {
                showResultPanel = shouldShow
            }
        }
        .onChange(of: engine.isProcessing) { _, processing in
            let shouldShow = processing || !outputText.isEmpty
            guard shouldShow != showResultPanel else { return }

            withAnimation(DS.Animation.standard) {
                showResultPanel = shouldShow
            }
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

                HStack(alignment: .top, spacing: DS.Spacing.md) {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text("MODEL")
                            .font(DS.Typography.microFont)
                            .tracking(0.8)
                            .foregroundStyle(DS.Colors.textTertiary)

                        modelControl
                    }
                    .frame(
                        maxWidth: settings.selectedProvider == .local ? 420 : 360,
                        alignment: .leading
                    )

                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text("SKILL")
                            .font(DS.Typography.microFont)
                            .tracking(0.8)
                            .foregroundStyle(DS.Colors.textTertiary)

                        skillControl
                    }
                    .frame(width: 260, alignment: .leading)

                    Spacer(minLength: 0)
                }
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
            .frame(maxWidth: 320, alignment: .leading)
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
        .frame(maxWidth: 240, alignment: .leading)
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
                    minHeight: composerFieldHeight,
                    maxHeight: composerFieldHeight
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

                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "tray.and.arrow.down")
                            .foregroundStyle(isDropTargeted ? DS.Colors.accent : DS.Colors.textTertiary)
                        Text("Drop up to \(maxAttachments) images")
                            .font(DS.Typography.captionFont)
                            .foregroundStyle(DS.Colors.textSecondary)
                    }

                    if attachments.isEmpty {
                        Text("PNG, JPEG, HEIC, TIFF.")
                            .font(DS.Typography.microFont)
                            .foregroundStyle(DS.Colors.textMuted)
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                                ForEach(attachments) { item in
                                    AttachmentChip(item: item) {
                                        removeAttachment(item.id)
                                    }
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.85).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }

                    Spacer(minLength: 0)

                    Text("Cloud providers only. Local is text-only.")
                        .font(DS.Typography.microFont)
                        .foregroundStyle(DS.Colors.textMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(attachments.isEmpty ? 1 : 0.9)
                        .padding(.top, DS.Spacing.xs)

                    if attachments.isEmpty {
                        Text("Drag files here")
                            .font(DS.Typography.microFont)
                            .foregroundStyle(DS.Colors.textTertiary)
                            .padding(.top, DS.Spacing.xs)
                    }
                }
                .padding(DS.Spacing.md)
                .frame(
                    maxWidth: .infinity,
                    minHeight: composerFieldHeight,
                    maxHeight: composerFieldHeight,
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
                            style: StrokeStyle(lineWidth: isDropTargeted ? 1.4 : 1, dash: [6, 4])
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
                        minHeight: 170,
                        maxHeight: 320,
                        shouldMeasureHeight: false
                    )

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

    private func loadClipboard(force: Bool) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        guard force || inputText.isEmpty else { return }
        inputText = text
    }

    private func run(style: RewriteStyle) {
        guard canRun else { return }

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

    private func appendAttachment(_ item: AttachmentItem) {
        guard attachments.count < maxAttachments else { return }
        guard !attachments.contains(where: { $0.attachment.hash == item.attachment.hash }) else { return }
        withAnimation(DS.Animation.standard) {
            attachments.append(item)
        }
    }

    private func loadAttachment(fromFile url: URL) async {
        guard let data = try? Data(contentsOf: url) else { return }
        let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/png"
        await loadAttachment(fromData: data, filename: url.lastPathComponent, mimeType: mimeType)
    }

    private func loadAttachment(fromData data: Data, filename: String, mimeType: String) async {
        let attachment = ImageAttachment(filename: filename, mimeType: mimeType, data: data)
        let thumbnail = Self.makeThumbnail(from: data)
        let item = AttachmentItem(attachment: attachment, thumbnail: thumbnail)
        await MainActor.run {
            appendAttachment(item)
        }
    }

    private static func makeThumbnail(from data: Data) -> NSImage? {
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

    var id: UUID { attachment.id }
}

private struct AttachmentChip: View {
    let item: AttachmentItem
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            if let thumbnail = item.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 12, weight: .semibold))
            }

            Text(item.attachment.filename)
                .font(DS.Typography.microFont)
                .lineLimit(1)
                .foregroundStyle(DS.Colors.textSecondary)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(DS.Colors.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
        .glassAccentCapsule(active: false, tint: DS.Colors.secondary)
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
