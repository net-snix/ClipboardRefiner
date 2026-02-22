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
                Text("Each provider card contains its API key and defaults.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(Self.cloudProviders, id: \.self) { provider in
                    apiKeyCard(for: provider)
                }
            } header: {
                Text("API Keys")
            } footer: {
                Text("Local models run on-device and do not require API keys.")
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
                Text("No local models configured yet. Add one below.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Selected model", selection: $settings.selectedModel) {
                    ForEach(settings.localModelPaths) { entry in
                        Text(entry.modelName).tag(entry.modelName)
                    }
                }
                .onChange(of: settings.selectedModel) { _, _ in
                    RewriteEngine.shared.updateProvider()
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Local model paths")
                    .font(.headline)

                HStack {
                    TextField("Model name", text: $localModelName)
                        .textFieldStyle(.roundedBorder)

                    TextField("Model folder path", text: $localModelPath)
                        .textFieldStyle(.roundedBorder)

                    Button("Add path") {
                        saveLocalModelPath()
                    }
                    .disabled(!canAddLocalModelPath)
                }

                if settings.localModelPaths.isEmpty {
                    Text("No model paths added yet. Paste a model folder path and save it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(settings.localModelPaths) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.modelName)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(entry.path)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                }

                                Spacer(minLength: 0)

                                Button("Remove", role: .destructive) {
                                    settings.removeLocalModelPath(id: entry.id)
                                    RewriteEngine.shared.updateProvider()
                                }
                            }
                        }
                    }
                }

                if let selectedPath = settings.selectedLocalModelPath {
                    Text("Active path: \(selectedPath)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                } else {
                    Text("Add a path for the selected local model before running rewrites.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                if let localStatusText {
                    Text(localStatusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Local provider uses your configured model folder paths.")
                .foregroundStyle(.secondary)
                .font(.footnote)
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

            if settings.selectedProvider == provider {
                providerDefaultsEditor(for: provider)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Defaults are editable when this provider is active.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func providerDefaultsEditor(for provider: LLMProviderType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Defaults")
                .font(.subheadline)
                .fontWeight(.semibold)

            Picker("Model", selection: $settings.selectedModel) {
                ForEach(provider.availableModels, id: \.self) { model in
                    Text(SettingsManager.displayModelName(model, for: provider)).tag(model)
                }
            }

            if provider == .openai,
               SettingsManager.isOpenAIReasoningModel(settings.selectedModel) {
                Picker("Reasoning effort", selection: $settings.openAIReasoningEffort) {
                    ForEach(OpenAIReasoningEffort.allCases, id: \.self) { effort in
                        Text(effort.displayName).tag(effort)
                    }
                }
            }
        }
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
        localStatusText = "Saved path for \(modelName)."
        RewriteEngine.shared.updateProvider()
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
