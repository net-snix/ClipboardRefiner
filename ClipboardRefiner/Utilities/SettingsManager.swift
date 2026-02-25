import Foundation
import Combine

enum LLMProviderType: String, CaseIterable, Codable {
    case openai = "OpenAI"
    case anthropic = "Anthropic"
    case xai = "xAI"
    case local = "Local"

    var displayName: String { rawValue }

    var defaultModel: String {
        switch self {
        case .openai:
            return "gpt-5.2"
        case .anthropic:
            return "claude-sonnet-4-6"
        case .xai:
            return "grok-4-1-fast"
        case .local:
            return "local-model"
        }
    }

    var availableModels: [String] {
        switch self {
        case .openai:
            return ["gpt-5.2", "gpt-5.1-2025-11-13"]
        case .anthropic:
            return ["claude-sonnet-4-6", "claude-opus-4-6"]
        case .xai:
            return ["grok-4-1-fast", "grok-4-1-fast-reasoning-latest"]
        case .local:
            return []
        }
    }

    var apiKeyIdentifier: String {
        switch self {
        case .openai:
            return "openai_api_key"
        case .anthropic:
            return "anthropic_api_key"
        case .xai:
            return "xai_api_key"
        case .local:
            return ""
        }
    }

    var usesAPIKey: Bool {
        self != .local
    }
}

enum QuickBehavior: String, CaseIterable, Codable {
    case interactive = "Interactive (show popup)"
    case quickReplace = "Quick Replace (no UI)"

    var displayName: String { rawValue }
}

enum OpenAIReasoningEffort: String, CaseIterable, Codable {
    case none
    case low
    case medium
    case high

    var displayName: String { rawValue.capitalized }
}

struct HistoryEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let originalText: String
    let rewrittenText: String
    let style: String
    let provider: String

    init(originalText: String, rewrittenText: String, style: String, provider: String) {
        self.id = UUID()
        self.date = Date()
        self.originalText = originalText
        self.rewrittenText = rewrittenText
        self.style = style
        self.provider = provider
    }
}

struct LocalModelPathEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let modelName: String
    let path: String

    init(id: UUID = UUID(), modelName: String, path: String) {
        self.id = id
        self.modelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.path = path.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        !modelName.isEmpty && !path.isEmpty
    }
}

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard
    private let historyPersistenceQueue = DispatchQueue(
        label: "com.clipboardrefiner.settings.history.persistence",
        qos: .utility
    )
    private let menuDraftPersistenceQueue = DispatchQueue(
        label: "com.clipboardrefiner.settings.menuDraft.persistence",
        qos: .utility
    )
    private var isReconcilingModelSelection = false
    private var hasPendingModelReconciliation = false
    private var pendingModelReconcileReason: ModelReconcileReason?
    private var pendingHistorySaveWorkItem: DispatchWorkItem?
    private var pendingMenuDraftSaveWorkItem: DispatchWorkItem?
    private let apiKeyCacheLock = NSLock()
    private var apiKeyCache: [LLMProviderType: String?] = [:]
    private var cachedMenuDraftText = ""

    private enum Keys {
        static let provider = "selectedProvider"
        static let model = "selectedModel"
        static let openAIModel = "openAIModel"
        static let anthropicModel = "anthropicModel"
        static let xaiModel = "xaiModel"
        static let localModelPaths = "localModelPaths"
        static let legacyOllamaModel = "ollamaModel"
        static let defaultStyle = "defaultStyle"
        static let selectedSkillID = "selectedSkillID"
        static let quickBehavior = "quickBehavior"
        static let streamingEnabled = "streamingEnabled"
        static let autoCopyEnabled = "autoCopyEnabled"
        static let historyEnabled = "historyEnabled"
        static let history = "rewriteHistory"
        static let aggressiveness = "aggressiveness"
        static let openAIReasoningEffort = "openaiReasoningEffort"
        static let hasSeenOnboarding = "hasSeenOnboarding"
        static let offlineCacheEnabled = "offlineCacheEnabled"
        static let autoLoadClipboard = "autoLoadClipboard"
        static let keepLocalModelLoaded = "keepLocalModelLoaded"
        static let systemPromptOverrides = "systemPromptOverrides"
        static let menuDraftText = "menuDraftText"
    }

    private enum ModelReconcileReason {
        case provider
        case selectedModel
        case localModelPaths
    }

    @Published var selectedProvider: LLMProviderType {
        didSet {
            defaults.set(selectedProvider.rawValue, forKey: Keys.provider)
            if !isReconcilingModelSelection {
                // Keep provider/model in sync immediately so Picker selection
                // never needs to write back during SwiftUI view updates.
                reconcileModelSelection(triggeredBy: .provider)
            }
        }
    }

    @Published var selectedModel: String {
        didSet {
            defaults.set(selectedModel, forKey: Keys.model)
            persistModelPreference(selectedModel, for: selectedProvider)
            if !isReconcilingModelSelection {
                scheduleModelReconciliation(triggeredBy: .selectedModel)
            }
        }
    }

    @Published var defaultStyle: RewriteStyle {
        didSet {
            defaults.set(defaultStyle.rawValue, forKey: Keys.defaultStyle)
        }
    }

    @Published var selectedSkillID: String {
        didSet {
            defaults.set(selectedSkillID, forKey: Keys.selectedSkillID)
        }
    }

    @Published var quickBehavior: QuickBehavior {
        didSet {
            defaults.set(quickBehavior.rawValue, forKey: Keys.quickBehavior)
        }
    }

    @Published var streamingEnabled: Bool {
        didSet {
            defaults.set(streamingEnabled, forKey: Keys.streamingEnabled)
        }
    }

    @Published var autoCopyEnabled: Bool {
        didSet {
            defaults.set(autoCopyEnabled, forKey: Keys.autoCopyEnabled)
        }
    }

    @Published var historyEnabled: Bool {
        didSet {
            defaults.set(historyEnabled, forKey: Keys.historyEnabled)
        }
    }

    @Published var offlineCacheEnabled: Bool {
        didSet {
            defaults.set(offlineCacheEnabled, forKey: Keys.offlineCacheEnabled)
        }
    }

    @Published var autoLoadClipboard: Bool {
        didSet {
            defaults.set(autoLoadClipboard, forKey: Keys.autoLoadClipboard)
        }
    }

    @Published var keepLocalModelLoaded: Bool {
        didSet {
            defaults.set(keepLocalModelLoaded, forKey: Keys.keepLocalModelLoaded)
        }
    }

    @Published var aggressiveness: Double {
        didSet {
            defaults.set(aggressiveness, forKey: Keys.aggressiveness)
        }
    }

    @Published var openAIReasoningEffort: OpenAIReasoningEffort {
        didSet {
            defaults.set(openAIReasoningEffort.rawValue, forKey: Keys.openAIReasoningEffort)
        }
    }

    @Published var hasSeenOnboarding: Bool {
        didSet {
            defaults.set(hasSeenOnboarding, forKey: Keys.hasSeenOnboarding)
        }
    }

    @Published private(set) var history: [HistoryEntry] = []
    @Published private(set) var localModelPaths: [LocalModelPathEntry] = []
    @Published private(set) var systemPromptOverrides: [String: String] = [:]

    private init() {
        let providerRaw = defaults.string(forKey: Keys.provider) ?? LLMProviderType.openai.rawValue
        let provider = Self.provider(from: providerRaw)
        self.selectedProvider = provider

        let storedModel = defaults.string(forKey: Keys.model)
            ?? defaults.string(forKey: Keys.legacyOllamaModel)

        Self.seedCloudModelPreferencesIfNeeded(
            defaults: defaults,
            usingLegacyModel: storedModel,
            selectedProvider: provider
        )

        if provider == .local {
            self.selectedModel = storedModel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } else {
            let resolvedModel = Self.storedModelPreference(for: provider, defaults: defaults) ?? provider.defaultModel
            self.selectedModel = resolvedModel
        }

        let styleRaw = defaults.string(forKey: Keys.defaultStyle) ?? RewriteStyle.rewrite.rawValue
        let resolvedStyle = RewriteStyle(rawValue: styleRaw) ?? .rewrite
        self.defaultStyle = resolvedStyle == .explain ? .rewrite : resolvedStyle

        self.selectedSkillID = defaults.string(forKey: Keys.selectedSkillID) ?? PromptSkillBundle.noneID

        let behaviorRaw = defaults.string(forKey: Keys.quickBehavior) ?? QuickBehavior.interactive.rawValue
        self.quickBehavior = QuickBehavior(rawValue: behaviorRaw) ?? .interactive

        self.streamingEnabled = defaults.object(forKey: Keys.streamingEnabled) as? Bool ?? false
        self.autoCopyEnabled = defaults.object(forKey: Keys.autoCopyEnabled) as? Bool ?? false
        self.historyEnabled = defaults.object(forKey: Keys.historyEnabled) as? Bool ?? true
        self.offlineCacheEnabled = defaults.object(forKey: Keys.offlineCacheEnabled) as? Bool ?? true
        self.autoLoadClipboard = defaults.object(forKey: Keys.autoLoadClipboard) as? Bool ?? true
        self.keepLocalModelLoaded = defaults.object(forKey: Keys.keepLocalModelLoaded) as? Bool ?? true
        self.aggressiveness = defaults.object(forKey: Keys.aggressiveness) as? Double ?? 0.2

        let effortRaw = defaults.string(forKey: Keys.openAIReasoningEffort) ?? OpenAIReasoningEffort.none.rawValue
        self.openAIReasoningEffort = OpenAIReasoningEffort(rawValue: effortRaw) ?? .none

        self.hasSeenOnboarding = defaults.object(forKey: Keys.hasSeenOnboarding) as? Bool ?? true
        self.cachedMenuDraftText = defaults.string(forKey: Keys.menuDraftText) ?? ""

        loadHistory()
        loadLocalModelPaths()
        loadSystemPromptOverrides()
        reconcileModelSelection(triggeredBy: .provider)
    }

    var selectedSkill: PromptSkill? {
        PromptSkillBundle.skill(for: selectedSkillID)
    }

    var localModelNames: [String] {
        localModelPaths.map(\.modelName)
    }

    func modelDefault(for provider: LLMProviderType) -> String {
        switch provider {
        case .local:
            let selectedLocal = localModelName(for: selectedModel)
            return selectedLocal ?? localModelPaths.first?.modelName ?? ""
        case .openai, .anthropic, .xai:
            return storedModelPreference(for: provider) ?? provider.defaultModel
        }
    }

    func setModelDefault(_ model: String, for provider: LLMProviderType) {
        switch provider {
        case .local:
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
            if selectedProvider == .local {
                selectedModel = trimmed
            }
        case .openai, .anthropic, .xai:
            let normalized = Self.normalizedModel(model, for: provider) ?? model
            let resolvedModel = provider.availableModels.contains(normalized) ? normalized : provider.defaultModel
            persistModelPreference(resolvedModel, for: provider)

            if selectedProvider == provider, selectedModel != resolvedModel {
                selectedModel = resolvedModel
            }
        }
    }

    private static func provider(from rawValue: String) -> LLMProviderType {
        if rawValue == "Ollama (Local)" {
            return .local
        }
        return LLMProviderType(rawValue: rawValue) ?? .openai
    }

    private static func normalizedModel(_ model: String?, for provider: LLMProviderType) -> String? {
        guard let model else { return nil }
        let normalized = model.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        switch provider {
        case .openai:
            if normalized == "gpt-5.2" || normalized.hasPrefix("gpt-5.2-") { return "gpt-5.2" }
            if normalized == "gpt-5.1" || normalized.hasPrefix("gpt-5.1-") { return "gpt-5.1-2025-11-13" }
            return nil
        case .anthropic:
            if normalized == "claude-sonnet-4-6" || normalized.hasPrefix("claude-sonnet-4-6-") { return "claude-sonnet-4-6" }
            if normalized == "claude-opus-4-6" || normalized.hasPrefix("claude-opus-4-6-") { return "claude-opus-4-6" }

            // Legacy and informal labels mapped to current Anthropic API aliases.
            if normalized == "claude-4.6-sonnet" || normalized == "claude-4-6-sonnet" { return "claude-sonnet-4-6" }
            if normalized == "claude-4.6-opus" || normalized == "claude-4-6-opus" { return "claude-opus-4-6" }
            if normalized == "claude-4.5-sonnet" || normalized == "claude-4-5-sonnet" { return "claude-sonnet-4-6" }
            return nil
        case .xai, .local:
            return nil
        }
    }

    static func isOpenAIReasoningModel(_ model: String) -> Bool {
        model.lowercased().hasPrefix("gpt-5")
    }

    static func displayModelName(_ model: String, for provider: LLMProviderType) -> String {
        let normalized = model.lowercased()

        switch provider {
        case .openai:
            if normalized == "gpt-5.2" || normalized.hasPrefix("gpt-5.2-") { return "GPT-5.2" }
            if normalized == "gpt-5.1" || normalized.hasPrefix("gpt-5.1-") { return "GPT-5.1" }
            if normalized.hasPrefix("gpt-5") { return normalized.replacingOccurrences(of: "gpt-", with: "GPT-") }
        case .anthropic:
            if normalized == "claude-sonnet-4-6" || normalized.hasPrefix("claude-sonnet-4-6-") { return "Claude Sonnet 4.6" }
            if normalized == "claude-opus-4-6" || normalized.hasPrefix("claude-opus-4-6-") { return "Claude Opus 4.6" }
        case .xai, .local:
            break
        }

        return model
    }

    var apiKey: String? {
        cachedAPIKey(for: selectedProvider)
    }

    func apiKey(for provider: LLMProviderType) -> String? {
        cachedAPIKey(for: provider)
    }

    func setAPIKey(_ key: String, for provider: LLMProviderType) throws {
        guard provider.usesAPIKey else { return }
        try KeychainHelper.shared.save(key, forKey: provider.apiKeyIdentifier)
        setCachedAPIKey(key, for: provider)
    }

    func deleteAPIKey(for provider: LLMProviderType) throws {
        guard provider.usesAPIKey else { return }
        try KeychainHelper.shared.delete(forKey: provider.apiKeyIdentifier)
        setCachedAPIKey(nil, for: provider)
    }

    func hasAPIKey(for provider: LLMProviderType) -> Bool {
        cachedAPIKey(for: provider) != nil
    }

    var selectedLocalModelPath: String? {
        localModelPath(for: selectedModel)
    }

    var isSelectedLocalModelConfigured: Bool {
        selectedLocalModelPath != nil
    }

    func localModelPath(for modelName: String) -> String? {
        let trimmedName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        return localModelPaths.first {
            $0.modelName.caseInsensitiveCompare(trimmedName) == .orderedSame
        }?.path
    }

    @discardableResult
    func addLocalModelPath(modelName: String, path: String) -> Bool {
        let entry = LocalModelPathEntry(modelName: modelName, path: path)
        guard entry.isValid else { return false }

        if let existingIndex = localModelPaths.firstIndex(where: {
            $0.modelName.caseInsensitiveCompare(entry.modelName) == .orderedSame
        }) {
            localModelPaths[existingIndex] = LocalModelPathEntry(
                id: localModelPaths[existingIndex].id,
                modelName: entry.modelName,
                path: entry.path
            )
        } else {
            localModelPaths.append(entry)
        }

        localModelPaths.sort {
            $0.modelName.localizedCaseInsensitiveCompare($1.modelName) == .orderedAscending
        }
        saveLocalModelPaths()
        scheduleModelReconciliation(triggeredBy: .localModelPaths)
        return true
    }

    func removeLocalModelPath(id: UUID) {
        guard let index = localModelPaths.firstIndex(where: { $0.id == id }) else { return }
        localModelPaths.remove(at: index)
        saveLocalModelPaths()
        scheduleModelReconciliation(triggeredBy: .localModelPaths)
    }

    func useLocalModelPath(_ entry: LocalModelPathEntry) {
        let trimmed = entry.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        selectedModel = trimmed
    }

    func addHistoryEntry(_ entry: HistoryEntry) {
        guard historyEnabled else { return }

        history.insert(entry, at: 0)

        if history.count > 150 {
            history = Array(history.prefix(150))
        }

        scheduleHistorySave()
    }

    func clearHistory() {
        history = []
        scheduleHistorySave()
    }

    func exportHistory() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(history),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }

        return json
    }

    func systemPrompt(for style: RewriteStyle) -> String {
        let key = style.rawValue
        if let override = systemPromptOverrides[key],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return override
        }
        return style.systemPrompt
    }

    func systemPromptOverride(for style: RewriteStyle) -> String? {
        let key = style.rawValue
        guard let value = systemPromptOverrides[key],
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    func hasSystemPromptOverride(for style: RewriteStyle) -> Bool {
        systemPromptOverride(for: style) != nil
    }

    func setSystemPromptOverride(_ prompt: String, for style: RewriteStyle) {
        let key = style.rawValue
        if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            systemPromptOverrides.removeValue(forKey: key)
        } else {
            systemPromptOverrides[key] = prompt
        }
        saveSystemPromptOverrides()
    }

    func resetSystemPromptOverride(for style: RewriteStyle) {
        let key = style.rawValue
        guard systemPromptOverrides[key] != nil else { return }
        systemPromptOverrides.removeValue(forKey: key)
        saveSystemPromptOverrides()
    }

    func loadMenuDraftText() -> String {
        cachedMenuDraftText
    }

    func saveMenuDraftText(_ text: String) {
        guard text != cachedMenuDraftText else { return }
        cachedMenuDraftText = text

        pendingMenuDraftSaveWorkItem?.cancel()
        let snapshot = text
        let workItem = DispatchWorkItem { [defaults] in
            defaults.set(snapshot, forKey: Keys.menuDraftText)
            PerfTelemetry.event(
                "menu_draft.persist",
                fields: [
                    "chars": "\(snapshot.count)",
                    "bytes": "\(snapshot.lengthOfBytes(using: .utf8))"
                ]
            )
        }

        pendingMenuDraftSaveWorkItem = workItem
        menuDraftPersistenceQueue.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    func clearMenuDraftText() {
        cachedMenuDraftText = ""
        pendingMenuDraftSaveWorkItem?.cancel()
        pendingMenuDraftSaveWorkItem = nil
        defaults.removeObject(forKey: Keys.menuDraftText)
        PerfTelemetry.event("menu_draft.clear")
    }

    private func loadHistory() {
        guard let data = defaults.data(forKey: Keys.history) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let entries = try? decoder.decode([HistoryEntry].self, from: data) {
            history = entries
        }
    }

    private func loadSystemPromptOverrides() {
        guard let raw = defaults.dictionary(forKey: Keys.systemPromptOverrides) else {
            systemPromptOverrides = [:]
            return
        }

        let validKeys = Set(RewriteStyle.allCases.map(\.rawValue))
        let decoded = raw.reduce(into: [String: String]()) { partialResult, pair in
            guard validKeys.contains(pair.key),
                  let value = pair.value as? String,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            partialResult[pair.key] = value
        }

        systemPromptOverrides = decoded
    }

    private func saveSystemPromptOverrides() {
        defaults.set(systemPromptOverrides, forKey: Keys.systemPromptOverrides)
    }

    private func saveHistory() {
        saveHistory(snapshot: history)
    }

    private func saveHistory(snapshot: [HistoryEntry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        if let data = try? encoder.encode(snapshot) {
            defaults.set(data, forKey: Keys.history)
        }
    }

    private func scheduleHistorySave() {
        pendingHistorySaveWorkItem?.cancel()
        let snapshot = history

        let workItem = DispatchWorkItem { [defaults] in
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601

            if let data = try? encoder.encode(snapshot) {
                defaults.set(data, forKey: Keys.history)
            }
        }

        pendingHistorySaveWorkItem = workItem
        historyPersistenceQueue.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func cachedAPIKey(for provider: LLMProviderType) -> String? {
        if provider == .local {
            return "local"
        }

        apiKeyCacheLock.lock()
        let cachedEntry = apiKeyCache[provider]
        apiKeyCacheLock.unlock()

        if case let .some(cachedValue) = cachedEntry {
            return cachedValue
        }

        let loadedValue = try? KeychainHelper.shared.retrieve(forKey: provider.apiKeyIdentifier)
        setCachedAPIKey(loadedValue, for: provider)
        return loadedValue
    }

    private func setCachedAPIKey(_ value: String?, for provider: LLMProviderType) {
        apiKeyCacheLock.lock()
        apiKeyCache[provider] = .some(value)
        apiKeyCacheLock.unlock()
    }

    private func loadLocalModelPaths() {
        guard let data = defaults.data(forKey: Keys.localModelPaths) else { return }

        let decoder = JSONDecoder()
        guard let decoded = try? decoder.decode([LocalModelPathEntry].self, from: data) else { return }

        localModelPaths = decoded
            .filter(\.isValid)
            .sorted { $0.modelName.localizedCaseInsensitiveCompare($1.modelName) == .orderedAscending }
    }

    private func saveLocalModelPaths() {
        let encoder = JSONEncoder()

        if let data = try? encoder.encode(localModelPaths) {
            defaults.set(data, forKey: Keys.localModelPaths)
        }
    }

    private func localModelName(for candidate: String) -> String? {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return localModelPaths.first {
            $0.modelName.caseInsensitiveCompare(trimmed) == .orderedSame
        }?.modelName
    }

    private func scheduleModelReconciliation(triggeredBy reason: ModelReconcileReason) {
        pendingModelReconcileReason = reason
        guard !hasPendingModelReconciliation else { return }

        hasPendingModelReconciliation = true
        DispatchQueue.main.async { [weak self] in
            // Defer reconciliation to the next main-loop turn to avoid publishing
            // while SwiftUI is still reconciling the provider/model picker update.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                self.hasPendingModelReconciliation = false
                let reconcileReason = self.pendingModelReconcileReason ?? .provider
                self.pendingModelReconcileReason = nil
                self.reconcileModelSelection(triggeredBy: reconcileReason)
            }
        }
    }

    private func reconcileModelSelection(triggeredBy reason: ModelReconcileReason) {
        guard !isReconcilingModelSelection else { return }
        isReconcilingModelSelection = true
        defer { isReconcilingModelSelection = false }

        switch selectedProvider {
        case .local:
            let preferredSelectedModel = localModelName(for: selectedModel)
            let fallbackModel = localModelPaths.first?.modelName ?? ""

            let resolvedModel: String
            switch reason {
            case .provider, .localModelPaths, .selectedModel:
                resolvedModel = preferredSelectedModel ?? fallbackModel
            }

            if selectedModel != resolvedModel {
                selectedModel = resolvedModel
            }

        case .openai, .anthropic, .xai:
            let preferredModel = storedModelPreference(for: selectedProvider) ?? selectedProvider.defaultModel

            if reason == .provider {
                let normalizedPreferred = Self.normalizedModel(preferredModel, for: selectedProvider) ?? preferredModel
                let resolvedPreferred = selectedProvider.availableModels.contains(normalizedPreferred)
                    ? normalizedPreferred
                    : selectedProvider.defaultModel
                if selectedModel != resolvedPreferred {
                    selectedModel = resolvedPreferred
                }
                persistModelPreference(resolvedPreferred, for: selectedProvider)
                return
            }

            let candidateModel: String
            switch reason {
            case .selectedModel, .localModelPaths:
                candidateModel = selectedModel
            case .provider:
                return
            }

            var resolvedModel = Self.normalizedModel(candidateModel, for: selectedProvider) ?? candidateModel
            if !selectedProvider.availableModels.contains(resolvedModel) {
                resolvedModel = preferredModel
            }
            if !selectedProvider.availableModels.contains(resolvedModel) {
                resolvedModel = selectedProvider.defaultModel
            }

            if selectedModel != resolvedModel {
                selectedModel = resolvedModel
            }

            persistModelPreference(resolvedModel, for: selectedProvider)
        }
    }

    private static func modelPreferenceKey(for provider: LLMProviderType) -> String? {
        switch provider {
        case .openai:
            return Keys.openAIModel
        case .anthropic:
            return Keys.anthropicModel
        case .xai:
            return Keys.xaiModel
        case .local:
            return nil
        }
    }

    private static func storedModelPreference(for provider: LLMProviderType, defaults: UserDefaults) -> String? {
        guard let key = modelPreferenceKey(for: provider),
              let stored = defaults.string(forKey: key) else {
            return nil
        }

        let normalized = Self.normalizedModel(stored, for: provider) ?? stored
        guard provider.availableModels.contains(normalized) else {
            return nil
        }

        return normalized
    }

    private func storedModelPreference(for provider: LLMProviderType) -> String? {
        Self.storedModelPreference(for: provider, defaults: defaults)
    }

    private func persistModelPreference(_ model: String, for provider: LLMProviderType) {
        guard let key = Self.modelPreferenceKey(for: provider) else { return }

        let normalized = Self.normalizedModel(model, for: provider) ?? model
        let resolvedModel = provider.availableModels.contains(normalized) ? normalized : provider.defaultModel
        defaults.set(resolvedModel, forKey: key)
    }

    private static func seedCloudModelPreferencesIfNeeded(
        defaults: UserDefaults,
        usingLegacyModel legacyModel: String?,
        selectedProvider: LLMProviderType
    ) {
        let cloudProviders: [LLMProviderType] = [.openai, .anthropic, .xai]
        for provider in cloudProviders {
            guard let key = modelPreferenceKey(for: provider),
                  defaults.string(forKey: key) == nil else {
                continue
            }

            let seedCandidate: String
            if provider == selectedProvider, let legacyModel {
                seedCandidate = legacyModel
            } else {
                seedCandidate = provider.defaultModel
            }

            let normalized = Self.normalizedModel(seedCandidate, for: provider) ?? seedCandidate
            let resolved = provider.availableModels.contains(normalized) ? normalized : provider.defaultModel
            defaults.set(resolved, forKey: key)
        }
    }
}
