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
            return "claude-4.5-sonnet"
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
            return ["claude-4.5-sonnet"]
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
    private var isReconcilingModelSelection = false
    private var hasPendingModelReconciliation = false
    private var pendingModelReconcileReason: ModelReconcileReason?

    private enum Keys {
        static let provider = "selectedProvider"
        static let model = "selectedModel"
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
                scheduleModelReconciliation(triggeredBy: .provider)
            }
        }
    }

    @Published var selectedModel: String {
        didSet {
            defaults.set(selectedModel, forKey: Keys.model)
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

    private init() {
        let providerRaw = defaults.string(forKey: Keys.provider) ?? LLMProviderType.openai.rawValue
        let provider = Self.provider(from: providerRaw)
        self.selectedProvider = provider

        let storedModel = defaults.string(forKey: Keys.model)
            ?? defaults.string(forKey: Keys.legacyOllamaModel)

        if provider == .local {
            self.selectedModel = storedModel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } else {
            let fallbackModel = provider.defaultModel
            let resolvedModel = Self.normalizedModel(storedModel, for: provider) ?? storedModel ?? fallbackModel
            self.selectedModel = provider.availableModels.contains(resolvedModel) ? resolvedModel : fallbackModel
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
        self.aggressiveness = defaults.object(forKey: Keys.aggressiveness) as? Double ?? 0.2

        let effortRaw = defaults.string(forKey: Keys.openAIReasoningEffort) ?? OpenAIReasoningEffort.none.rawValue
        self.openAIReasoningEffort = OpenAIReasoningEffort(rawValue: effortRaw) ?? .none

        self.hasSeenOnboarding = defaults.object(forKey: Keys.hasSeenOnboarding) as? Bool ?? true

        loadHistory()
        loadLocalModelPaths()
        reconcileModelSelection(triggeredBy: .provider)
    }

    var selectedSkill: PromptSkill? {
        PromptSkillBundle.skill(for: selectedSkillID)
    }

    var localModelNames: [String] {
        localModelPaths.map(\.modelName)
    }

    private static func provider(from rawValue: String) -> LLMProviderType {
        if rawValue == "Ollama (Local)" {
            return .local
        }
        return LLMProviderType(rawValue: rawValue) ?? .openai
    }

    private static func normalizedModel(_ model: String?, for provider: LLMProviderType) -> String? {
        guard let model else { return nil }
        let normalized = model.lowercased()

        switch provider {
        case .openai:
            if normalized == "gpt-5.2" || normalized.hasPrefix("gpt-5.2-") { return "gpt-5.2" }
            if normalized == "gpt-5.1" || normalized.hasPrefix("gpt-5.1-") { return "gpt-5.1-2025-11-13" }
            return nil
        case .anthropic, .xai, .local:
            return nil
        }
    }

    static func isOpenAIReasoningModel(_ model: String) -> Bool {
        model.lowercased().hasPrefix("gpt-5")
    }

    static func displayModelName(_ model: String, for provider: LLMProviderType) -> String {
        guard provider == .openai else { return model }

        let normalized = model.lowercased()
        if normalized == "gpt-5.2" || normalized.hasPrefix("gpt-5.2-") { return "GPT-5.2" }
        if normalized == "gpt-5.1" || normalized.hasPrefix("gpt-5.1-") { return "GPT-5.1" }
        if normalized.hasPrefix("gpt-5") { return normalized.replacingOccurrences(of: "gpt-", with: "GPT-") }
        return model
    }

    var apiKey: String? {
        if selectedProvider == .local {
            return "local"
        }
        return try? KeychainHelper.shared.retrieve(forKey: selectedProvider.apiKeyIdentifier)
    }

    func apiKey(for provider: LLMProviderType) -> String? {
        if provider == .local {
            return "local"
        }
        return try? KeychainHelper.shared.retrieve(forKey: provider.apiKeyIdentifier)
    }

    func setAPIKey(_ key: String, for provider: LLMProviderType) throws {
        guard provider.usesAPIKey else { return }
        try KeychainHelper.shared.save(key, forKey: provider.apiKeyIdentifier)
    }

    func deleteAPIKey(for provider: LLMProviderType) throws {
        guard provider.usesAPIKey else { return }
        try KeychainHelper.shared.delete(forKey: provider.apiKeyIdentifier)
    }

    func hasAPIKey(for provider: LLMProviderType) -> Bool {
        if provider == .local {
            return true
        }
        return KeychainHelper.shared.exists(forKey: provider.apiKeyIdentifier)
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

        saveHistory()
    }

    func clearHistory() {
        history = []
        saveHistory()
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

    private func loadHistory() {
        guard let data = defaults.data(forKey: Keys.history) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let entries = try? decoder.decode([HistoryEntry].self, from: data) {
            history = entries
        }
    }

    private func saveHistory() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        if let data = try? encoder.encode(history) {
            defaults.set(data, forKey: Keys.history)
        }
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
            guard let self else { return }

            self.hasPendingModelReconciliation = false
            let reconcileReason = self.pendingModelReconcileReason ?? .provider
            self.pendingModelReconcileReason = nil
            self.reconcileModelSelection(triggeredBy: reconcileReason)
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
            if let normalizedModel = Self.normalizedModel(selectedModel, for: selectedProvider),
               normalizedModel != selectedModel,
               selectedProvider.availableModels.contains(normalizedModel) {
                selectedModel = normalizedModel
                return
            }

            if !selectedProvider.availableModels.contains(selectedModel) {
                selectedModel = selectedProvider.defaultModel
            }
        }
    }
}
