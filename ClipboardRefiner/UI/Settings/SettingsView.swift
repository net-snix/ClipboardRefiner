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
        .frame(width: 620, height: 470)
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
        Form {
            Section {
                ForEach(Self.cloudProviders, id: \.self) { provider in
                    apiKeyCard(for: provider)
                }
            } header: {
                Text("API Keys")
            }

            Section("Local Models") {
                if settings.selectedProvider != .local {
                    HStack {
                        Text("Not active")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Use Local") {
                            settings.selectedProvider = .local
                        }
                    }
                }

                localConfigurationSection
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadStoredAPIKeys()
        }
    }

    private var localConfigurationSection: some View {
        Group {
            if settings.localModelPaths.isEmpty {
                Text("No local models yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !settings.localModelPaths.isEmpty {
                Picker("Selected model", selection: $settings.selectedModel) {
                    ForEach(settings.localModelPaths) { entry in
                        Text(entry.modelName).tag(entry.modelName)
                    }
                }
                .onChange(of: settings.selectedModel) { _, _ in
                    RewriteEngine.shared.updateProvider()
                }

                if settings.selectedLocalModelPath != nil {
                    HStack {
                        Text(engine.isLocalModelLoaded ? "Model loaded in memory" : "Model not loaded")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(localModelActionTitle) {
                            toggleLocalModelLoadStateFromSettings()
                        }
                        .disabled(engine.isUnloadingLocalModel || engine.isLoadingLocalModel || engine.isProcessing)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Add model")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                HStack(spacing: 8) {
                    TextField("", text: $localModelName, prompt: Text("Model name"))
                        .frame(width: 220)
                        .textFieldStyle(.roundedBorder)

                    TextField("", text: $localModelPath, prompt: Text("Model folder path"))
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 260, maxWidth: .infinity)
                        .layoutPriority(1)

                    Button("Choose…") {
                        chooseLocalModelPath()
                    }
                    .frame(width: 100)

                    Button("Add") {
                        saveLocalModelPath()
                    }
                    .disabled(!canAddLocalModelPath)
                    .frame(width: 72)
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
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(entry.modelName)
                                        .font(.system(size: 13, weight: .semibold))
                                    if isActiveLocalModel(entry) {
                                        Text("Active")
                                            .font(.caption2)
                                            .foregroundStyle(.green)
                                    }
                                }

                                Text(entry.path)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                            }

                            Spacer(minLength: 0)

                            Button("Use") {
                                settings.useLocalModelPath(entry)
                                RewriteEngine.shared.updateProvider()
                            }
                            .disabled(isActiveLocalModel(entry))

                            Button("Remove", role: .destructive) {
                                settings.removeLocalModelPath(id: entry.id)
                                RewriteEngine.shared.updateProvider()
                            }
                        }
                    }
                }
            }
        }
    }

    private func apiKeyCard(for provider: LLMProviderType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
                        .foregroundStyle(.orange)
                }

                Spacer()

                if settings.selectedProvider != provider {
                    Button("Use Provider") {
                        settings.selectedProvider = provider
                    }
                    .buttonStyle(.borderless)
                }
            }

            HStack(spacing: 8) {
                Group {
                    if visibleKeyProviders.contains(provider) {
                        TextField("API key", text: apiKeyBinding(for: provider))
                    } else {
                        SecureField("API key", text: apiKeyBinding(for: provider))
                    }
                }
                .textFieldStyle(.roundedBorder)

                Button(visibleKeyProviders.contains(provider) ? "Hide" : "Show") {
                    toggleKeyVisibility(for: provider)
                }
                .buttonStyle(.borderless)
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

                if let saveStatus = saveStatusByProvider[provider] {
                    Text(saveStatus.message)
                        .font(.footnote)
                        .foregroundStyle(statusColor(for: saveStatus))
                }

                Spacer()
            }

            apiKeyHelpLink(for: provider)
                .font(.footnote)

            providerDefaultsContent(for: provider)
        }
        .padding(.vertical, 2)
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

            Picker("Model", selection: modelBinding(for: provider)) {
                ForEach(provider.availableModels, id: \.self) { model in
                    Text(SettingsManager.displayModelName(model, for: provider)).tag(model)
                }
            }
            .pickerStyle(.menu)

            if provider == .openai,
               SettingsManager.isOpenAIReasoningModel(settings.modelDefault(for: provider)) {
                Picker("Reasoning effort", selection: reasoningEffortBinding(for: provider)) {
                    ForEach(OpenAIReasoningEffort.allCases, id: \.self) { effort in
                        Text(effort.displayName).tag(effort)
                    }
                }
                .pickerStyle(.menu)
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
                if settings.selectedProvider == provider {
                    RewriteEngine.shared.updateProvider()
                }
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
                if settings.selectedProvider == provider {
                    RewriteEngine.shared.updateProvider()
                }
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
            if settings.selectedProvider == provider {
                RewriteEngine.shared.updateProvider()
            }
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
            if settings.selectedProvider == provider {
                RewriteEngine.shared.updateProvider()
            }
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
        RewriteEngine.shared.updateProvider()
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
        return engine.isLocalModelLoaded ? "Unload" : "Load"
    }

    private func toggleLocalModelLoadStateFromSettings() {
        if engine.isLocalModelLoaded {
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
                        Text(aggressivenessLabel)
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $settings.aggressiveness, in: 0...1, step: 0.05)
                }
            }

            Section("Runtime") {
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

    private var aggressivenessLabel: String {
        switch settings.aggressiveness {
        case 0..<0.25: return "Minimal"
        case 0.25..<0.55: return "Balanced"
        case 0.55..<0.8: return "Strong"
        default: return "Heavy"
        }
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
            Text("Post Enhancer 2.0")
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
