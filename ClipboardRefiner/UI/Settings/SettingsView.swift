import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            ProviderSettingsView()
                .tabItem {
                    Label("Provider", systemImage: "network")
                }

            BehaviorSettingsView()
                .tabItem {
                    Label("Behavior", systemImage: "slider.horizontal.3")
                }

            HistorySettingsView()
                .tabItem {
                    Label("History", systemImage: "clock")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(minWidth: 620, idealWidth: 660, maxWidth: 700, minHeight: 560, idealHeight: 620)
    }
}

struct ProviderSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var engine = RewriteEngine.shared
    @State private var apiKeys: [LLMProviderType: String] = [:]
    @State private var visibleKeyProviders = Set<LLMProviderType>()
    @State private var saveStatusByProvider: [LLMProviderType: SaveStatus] = [:]
    @State private var localModelName = ""
    @State private var localModelPath = ""
    @State private var localStatusText: String?

    private static let cloudProviders: [LLMProviderType] = [.openai, .anthropic, .xai]
    private static let defaultsPickerWidth: CGFloat = 240

    private enum SaveStatus: Equatable {
        case saved
        case deleted
        case error(String)

        var message: String {
            switch self {
            case .saved:
                return "Saved"
            case .deleted:
                return "Deleted"
            case .error(let message):
                return message
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                settingsSection(title: "API Keys") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Self.cloudProviders, id: \.self) { provider in
                            apiKeyCard(for: provider)
                        }
                    }
                }

                settingsSection(title: "Local Models") {
                    localConfigurationSection
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            loadStoredAPIKeys()
        }
    }

    private var localConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if settings.selectedProvider != .local {
                HStack(alignment: .center, spacing: 10) {
                    Text("Cloud provider is active.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Use Local") {
                        settings.selectedProvider = .local
                    }
                }
            }

            if settings.localModelPaths.isEmpty {
                Text("No local models yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    Text("Selected model")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer(minLength: 0)

                    if settings.selectedProvider == .local {
                        Picker("Selected model", selection: localSettingsModelBinding) {
                            ForEach(settings.localModelPaths) { entry in
                                Text(entry.modelName).tag(entry.modelName)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 300)
                    } else {
                        Text(resolvedLocalModelSelection)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if settings.selectedProvider == .local, settings.selectedLocalModelPath != nil {
                    HStack(spacing: 10) {
                        Text(isSelectedLocalModelLoaded ? "Loaded in memory" : "Not loaded")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button(localModelActionTitle) {
                            toggleLocalModelLoadStateFromSettings()
                        }
                        .disabled(engine.isUnloadingLocalModel || engine.isLoadingLocalModel || engine.isProcessing)
                    }

                    Toggle("Keep loaded", isOn: $settings.keepLocalModelLoaded)
                        .font(.footnote)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Add model")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                TextField("Model name", text: $localModelName)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 8) {
                    TextField("Model folder path", text: $localModelPath)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)

                    Button("Choose…") {
                        chooseLocalModelPath()
                    }
                }

                HStack {
                    Spacer(minLength: 0)
                    Button("Add") {
                        saveLocalModelPath()
                    }
                    .disabled(!canAddLocalModelPath)
                }

                if let localStatusText {
                    Text(localStatusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !settings.localModelPaths.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Saved models")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    ForEach(settings.localModelPaths) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Text(entry.modelName)
                                    .font(.system(size: 13, weight: .semibold))
                                if isActiveLocalModel(entry) {
                                    Text("Active")
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.12), in: Capsule())
                                }
                                Spacer(minLength: 0)
                            }

                            Text(entry.path)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .textSelection(.enabled)

                            HStack(spacing: 8) {
                                Button("Use") {
                                    settings.useLocalModelPath(entry)
                                }
                                .disabled(isActiveLocalModel(entry))

                                Button("Remove", role: .destructive) {
                                    settings.removeLocalModelPath(id: entry.id)
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func apiKeyCard(for provider: LLMProviderType) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(provider.displayName)
                    .font(.headline)

                if settings.hasAPIKey(for: provider) {
                    Label("Saved", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("Missing", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(DS.Colors.warning)
                }

                Spacer()

                if settings.selectedProvider != provider {
                    Button("Use Provider") {
                        settings.selectedProvider = provider
                    }
                    .buttonStyle(.borderless)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("API key")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Group {
                        if visibleKeyProviders.contains(provider) {
                            TextField("API key", text: apiKeyBinding(for: provider))
                        } else {
                            SecureField("API key", text: apiKeyBinding(for: provider))
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)

                    Button(visibleKeyProviders.contains(provider) ? "Hide" : "Show") {
                        toggleKeyVisibility(for: provider)
                    }
                    .buttonStyle(.borderless)
                }
            }

            HStack(spacing: 8) {
                Button("Save") {
                    saveAPIKey(for: provider)
                }
                .disabled(trimmedAPIKey(for: provider).isEmpty)

                Button("Delete", role: .destructive) {
                    deleteAPIKey(for: provider)
                }
                .disabled(!settings.hasAPIKey(for: provider))
                Spacer()
            }

            if let saveStatus = saveStatusByProvider[provider] {
                Text(saveStatus.message)
                    .font(.footnote)
                    .foregroundStyle(statusColor(for: saveStatus))
            }

            apiKeyHelpLink(for: provider)
                .font(.footnote)

            providerDefaultsContent(for: provider)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func providerDefaultsContent(for provider: LLMProviderType) -> some View {
        providerDefaultsEditor(for: provider)
    }

    @ViewBuilder
    private func providerDefaultsEditor(for provider: LLMProviderType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Defaults")
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack(spacing: 8) {
                Text("Model")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Picker("Model", selection: modelBinding(for: provider)) {
                    ForEach(provider.availableModels, id: \.self) { model in
                        Text(SettingsManager.displayModelName(model, for: provider)).tag(model)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: Self.defaultsPickerWidth)
            }

            if provider == .openai,
               SettingsManager.isOpenAIReasoningModel(settings.modelDefault(for: provider)) {
                HStack(spacing: 8) {
                    Text("Reasoning effort")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Picker("Reasoning effort", selection: reasoningEffortBinding(for: provider)) {
                        ForEach(OpenAIReasoningEffort.allCases, id: \.self) { effort in
                            Text(effort.displayName).tag(effort)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: Self.defaultsPickerWidth)
                }
            }
        }
    }

    private func modelBinding(for provider: LLMProviderType) -> Binding<String> {
        Binding(
            get: {
                settings.modelDefault(for: provider)
            },
            set: { newValue in
                settings.setModelDefault(newValue, for: provider)
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

    private var localSettingsModelBinding: Binding<String> {
        Binding(
            get: {
                resolvedLocalModelSelection
            },
            set: { newValue in
                settings.selectedModel = newValue
            }
        )
    }

    private func reasoningEffortBinding(for provider: LLMProviderType) -> Binding<OpenAIReasoningEffort> {
        Binding(
            get: {
                settings.openAIReasoningEffort
            },
            set: { newValue in
                settings.openAIReasoningEffort = newValue
            }
        )
    }

    @ViewBuilder
    private func apiKeyHelpLink(for provider: LLMProviderType) -> some View {
        switch provider {
        case .openai:
            Link("OpenAI API keys", destination: URL(string: "https://platform.openai.com/api-keys")!)
        case .anthropic:
            Link("Anthropic API keys", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
        case .xai:
            Link("xAI console", destination: URL(string: "https://console.x.ai/")!)
        case .local:
            EmptyView()
        }
    }

    private func loadStoredAPIKeys() {
        for provider in Self.cloudProviders {
            if let key = try? KeychainHelper.shared.retrieve(forKey: provider.apiKeyIdentifier) {
                apiKeys[provider] = key
            } else {
                apiKeys[provider] = ""
            }
        }
    }

    private func apiKeyBinding(for provider: LLMProviderType) -> Binding<String> {
        Binding(
            get: {
                apiKeys[provider, default: ""]
            },
            set: { value in
                apiKeys[provider] = value
            }
        )
    }

    private func toggleKeyVisibility(for provider: LLMProviderType) {
        if visibleKeyProviders.contains(provider) {
            visibleKeyProviders.remove(provider)
        } else {
            visibleKeyProviders.insert(provider)
        }
    }

    private func trimmedAPIKey(for provider: LLMProviderType) -> String {
        apiKeys[provider, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveAPIKey(for provider: LLMProviderType) {
        let key = trimmedAPIKey(for: provider)
        guard !key.isEmpty else { return }

        do {
            try settings.setAPIKey(key, for: provider)
            apiKeys[provider] = key
            saveStatusByProvider[provider] = .saved
            clearStatusAfterDelay(for: provider)
        } catch {
            saveStatusByProvider[provider] = .error(error.localizedDescription)
        }
    }

    private func deleteAPIKey(for provider: LLMProviderType) {
        do {
            try settings.deleteAPIKey(for: provider)
            apiKeys[provider] = ""
            saveStatusByProvider[provider] = .deleted
            clearStatusAfterDelay(for: provider)
        } catch {
            saveStatusByProvider[provider] = .error(error.localizedDescription)
        }
    }

    private func clearStatusAfterDelay(for provider: LLMProviderType) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            saveStatusByProvider[provider] = nil
        }
    }

    private func statusColor(for status: SaveStatus) -> Color {
        switch status {
        case .saved, .deleted:
            return .green
        case .error:
            return .red
        }
    }

    private var canAddLocalModelPath: Bool {
        !localModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !localModelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isSelectedLocalModelLoaded: Bool {
        guard engine.isLocalModelLoaded else { return false }
        guard let loadedModel = engine.loadedLocalModelName else { return false }
        return loadedModel.caseInsensitiveCompare(settings.selectedModel) == .orderedSame
    }

    private func saveLocalModelPath() {
        let modelName = localModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelPath = localModelPath.trimmingCharacters(in: .whitespacesAndNewlines)

        guard settings.addLocalModelPath(modelName: modelName, path: modelPath) else {
            localStatusText = "Enter both model name and folder path."
            return
        }

        settings.selectedModel = modelName
        localModelName = ""
        localModelPath = ""
        localStatusText = "Saved."
        clearLocalStatusAfterDelay()
    }

    private func chooseLocalModelPath() {
        let panel = NSOpenPanel()
        panel.title = "Choose Local Model Folder"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = true

        let trimmedPath = localModelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: trimmedPath)
        }

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }

        localModelPath = selectedURL.path
        if localModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            localModelName = selectedURL.lastPathComponent
        }
        localStatusText = nil
    }

    private func isActiveLocalModel(_ entry: LocalModelPathEntry) -> Bool {
        entry.modelName.caseInsensitiveCompare(settings.selectedModel) == .orderedSame
    }

    private func clearLocalStatusAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            localStatusText = nil
        }
    }

    private func unloadLocalModelFromSettings() {
        localStatusText = nil
        engine.unloadLocalModel { result in
            switch result {
            case .success:
                localStatusText = "Unloaded."
                clearLocalStatusAfterDelay()
            case .failure(let error):
                localStatusText = error.localizedDescription
            }
        }
    }

    private var localModelActionTitle: String {
        if engine.isUnloadingLocalModel { return "Unloading…" }
        if engine.isLoadingLocalModel { return "Loading…" }
        return isSelectedLocalModelLoaded ? "Unload" : "Load"
    }

    private func toggleLocalModelLoadStateFromSettings() {
        if isSelectedLocalModelLoaded {
            unloadLocalModelFromSettings()
        } else {
            loadLocalModelFromSettings()
        }
    }

    private func loadLocalModelFromSettings() {
        localStatusText = nil
        engine.loadLocalModel { result in
            switch result {
            case .success:
                localStatusText = "Loaded."
                clearLocalStatusAfterDelay()
            case .failure(let error):
                localStatusText = error.localizedDescription
            }
        }
    }
}

struct BehaviorSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var promptEditorStyle: RewriteStyle = .rewrite

    var body: some View {
        Form {
            Section("Enhancement defaults") {
                Picker("Default style", selection: $settings.defaultStyle) {
                    ForEach(RewriteStyle.userSelectableCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }

                Picker("Prompt skill", selection: $settings.selectedSkillID) {
                    Text("None").tag(PromptSkillBundle.noneID)
                    ForEach(PromptSkillBundle.bundled, id: \.id) { skill in
                        Text(skill.name).tag(skill.id)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Rewrite aggressiveness")
                        Spacer()
                        Text(aggressivenessValueLabel)
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $settings.aggressiveness, in: 0...1, step: 0.01)
                }
            }

            Section("System prompts") {
                Picker("Edit style", selection: $promptEditorStyle) {
                    ForEach(RewriteStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("System prompt")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    TextEditor(text: systemPromptEditorBinding)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .frame(minHeight: 200)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                        )
                }

                HStack(spacing: 10) {
                    Button("Reset selected to default") {
                        settings.resetSystemPromptOverride(for: promptEditorStyle)
                    }
                    .disabled(!settings.hasSystemPromptOverride(for: promptEditorStyle))

                    Text("Saved automatically.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text("Aggressiveness slider instructions are injected automatically at request time and are not editable here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Runtime") {
                Toggle("Keep local model loaded", isOn: $settings.keepLocalModelLoaded)
                Toggle("Streaming response updates", isOn: $settings.streamingEnabled)
                Toggle("Auto-copy after success", isOn: $settings.autoCopyEnabled)
                Toggle("Auto-load clipboard on open", isOn: $settings.autoLoadClipboard)
                Toggle("Enable offline cache fallback", isOn: $settings.offlineCacheEnabled)
            }

            Section("Services") {
                Picker("Quick service behavior", selection: $settings.quickBehavior) {
                    ForEach(QuickBehavior.allCases, id: \.self) { behavior in
                        Text(behavior.displayName).tag(behavior)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var aggressivenessValueLabel: String {
        let clamped = min(max(settings.aggressiveness, 0), 1)
        return "\(Int(round(clamped * 100)))%"
    }

    private var systemPromptEditorBinding: Binding<String> {
        Binding(
            get: {
                settings.systemPromptOverride(for: promptEditorStyle) ??
                settings.systemPrompt(for: promptEditorStyle)
            },
            set: { newValue in
                settings.setSystemPromptOverride(newValue, for: promptEditorStyle)
            }
        )
    }
}

struct HistorySettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        Form {
            Section("Storage") {
                Toggle("Enable local history", isOn: $settings.historyEnabled)
                Text("History and offline cache stay on-device. No telemetry.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Entries") {
                HStack {
                    Text("\(settings.history.count) saved rewrites")
                    Spacer()
                    Button("Export JSON") {
                        exportHistory()
                    }
                    .disabled(settings.history.isEmpty)

                    Button("Clear", role: .destructive) {
                        settings.clearHistory()
                    }
                    .disabled(settings.history.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func exportHistory() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "clipboard_refiner_history.json"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                let json = settings.exportHistory()
                try? json.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

struct AboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Clipboard Refiner")
                .font(.system(size: 24, weight: .semibold, design: .rounded))

            Text("Native macOS SwiftUI app for enhancing posts with cloud or local models.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Label("Drag-and-drop image context", systemImage: "photo.on.rectangle")
                Label("Offline cache fallback", systemImage: "externaldrive.badge.timemachine")
                Label("macOS Share Sheet integration", systemImage: "square.and.arrow.up")
                Label("Reusable Codex prompt skills", systemImage: "shippingbox")
                Label("Local private mode via on-device models", systemImage: "lock.shield")
            }
            .font(.system(size: 13, weight: .medium))

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
#endif
