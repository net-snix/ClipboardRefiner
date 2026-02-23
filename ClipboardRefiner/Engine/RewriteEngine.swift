import Foundation
import CryptoKit

final class RewriteEngine: ObservableObject {
    static let shared = RewriteEngine()

    @Published var isProcessing = false
    @Published var currentOutput = ""
    @Published var error: LLMError?
    @Published private(set) var isLocalModelLoaded = false
    @Published private(set) var loadedLocalModelName: String?
    @Published private(set) var isLoadingLocalModel = false
    @Published private(set) var isUnloadingLocalModel = false

    private var currentCancellable: Cancellable?
    private var provider: LLMProvider?
    private var activeRewriteProviderType: LLMProviderType?
    private let localWorkerLifecycleQueue = DispatchQueue(
        label: "com.clipboardrefiner.local-worker-lifecycle",
        qos: .userInitiated
    )
    private let rewriteRequestLock = NSLock()
    private var activeRewriteRequestID = UUID()
    private var completedRewriteRequestID: UUID?

    private let cacheStore = RewriteCacheStore()

    private init() {
        updateProvider()
    }

    func updateProvider() {
        let settings = SettingsManager.shared
        let previousProviderType = provider?.providerType

        switch settings.selectedProvider {
        case .openai:
            guard let apiKey = settings.apiKey, !apiKey.isEmpty else {
                provider = nil
                syncLocalWorkerStateForNonLocalSelection(previousProviderType: previousProviderType)
                return
            }
            let model = settings.modelDefault(for: .openai)
            provider = OpenAIProvider(
                apiKey: apiKey,
                model: model,
                reasoningEffort: settings.openAIReasoningEffort
            )

        case .anthropic:
            guard let apiKey = settings.apiKey, !apiKey.isEmpty else {
                provider = nil
                syncLocalWorkerStateForNonLocalSelection(previousProviderType: previousProviderType)
                return
            }
            let model = settings.modelDefault(for: .anthropic)
            provider = AnthropicProvider(apiKey: apiKey, model: model)

        case .xai:
            guard let apiKey = settings.apiKey, !apiKey.isEmpty else {
                provider = nil
                syncLocalWorkerStateForNonLocalSelection(previousProviderType: previousProviderType)
                return
            }
            let model = settings.modelDefault(for: .xai)
            provider = XAIProvider(apiKey: apiKey, model: model)

        case .local:
            let modelName = settings.modelDefault(for: .local)
            guard !modelName.isEmpty else {
                provider = nil
                releaseLocalWorkerResources()
                return
            }
            guard let modelPath = settings.localModelPath(for: modelName) else {
                provider = nil
                releaseLocalWorkerResources()
                return
            }
            if loadedLocalModelName?.caseInsensitiveCompare(modelName) != .orderedSame {
                clearLocalModelLoadedState()
            }
            provider = LocalModelProvider(modelName: modelName, modelPath: modelPath)
        }

        if settings.selectedProvider != .local {
            syncLocalWorkerStateForNonLocalSelection(previousProviderType: previousProviderType)
        }
    }

    func rewrite(
        text: String,
        options: RewriteOptions,
        providerOverride: LLMProvider?,
        streamHandler: @escaping (String) -> Void,
        completion: @escaping (Result<String, LLMError>) -> Void
    ) {
        cancel()
        let rewriteRequestID = beginRewriteRequest()

        let settings = SettingsManager.shared
        let requestProviderType = providerOverride?.providerType ?? settings.selectedProvider
        let requestProviderName = providerOverride?.name ?? requestProviderType.rawValue
        let requestModelName = resolvedModelName(for: requestProviderType, settings: settings)
        let cacheKey = makeCacheKey(
            text: text,
            options: options,
            providerName: requestProviderName,
            model: requestModelName
        )
        activeRewriteProviderType = requestProviderType

        let finalizeRequest: (Result<String, LLMError>, String?) -> Void = { [weak self] result, finalOutput in
            guard let self else { return }

            self.deliverOnMain {
                let isActiveRequest = self.isActiveRewriteRequest(rewriteRequestID)
                let finalResult = isActiveRequest ? result : .failure(.cancelled)
                let finalText = finalOutput ?? (try? finalResult.get())

                guard self.markRewriteRequestCompleted(rewriteRequestID, result: finalResult, completion: completion) else {
                    return
                }

                guard isActiveRequest else {
                    return
                }

                self.isProcessing = false

                switch finalResult {
                case .success(let output):
                    AppLogger.shared.info("Rewrite completed successfully")
                    self.currentOutput = output
                    if let activeProviderText = finalText {
                        self.currentOutput = activeProviderText
                    }

                    if settings.historyEnabled {
                        let entry = HistoryEntry(
                            originalText: text,
                            rewrittenText: output,
                            style: options.style.rawValue,
                            provider: requestProviderName
                        )
                        settings.addHistoryEntry(entry)
                    }

                    if settings.offlineCacheEnabled {
                        Task {
                            await self.cacheStore.store(value: output, for: cacheKey)
                        }
                    }

                    if requestProviderType == .local {
                        self.isLocalModelLoaded = true
                        self.loadedLocalModelName = requestModelName
                    }

                case .failure(let failure):
                    AppLogger.shared.error("Rewrite failed: \(failure.localizedDescription)")
                    self.error = failure
                }

                self.maybeUnloadLocalModelAfterRequest(
                    providerType: requestProviderType,
                    settings: settings
                )
                self.activeRewriteProviderType = nil
            }
        }

        let activeProvider: LLMProvider
        if let providerOverride {
            activeProvider = providerOverride
        } else {
            updateProvider()

            guard let provider else {
                let missingProviderError: LLMError = settings.selectedProvider == .local
                    ? .localModelUnavailable("Add a local model path for this model in Provider settings.")
                    : .invalidAPIKey

                Task {
                    if settings.offlineCacheEnabled, let cached = await cacheStore.lookup(for: cacheKey) {
                        await MainActor.run { [weak self] in
                            guard let self else { return }
                            if self.isActiveRewriteRequest(rewriteRequestID) {
                                streamHandler(cached)
                            }
                            finalizeRequest(.success(cached), cached)
                        }
                        return
                    }

                    await MainActor.run {
                        finalizeRequest(.failure(missingProviderError), nil)
                    }
                }
                return
            }

            activeProvider = provider
        }

        deliverOnMain {
            self.isProcessing = true
            self.error = nil
            self.currentOutput = ""
        }

        AppLogger.shared.info("Starting rewrite with style: \(options.style.rawValue)")

        let startProviderRewrite: () -> Void = { [weak self] in
            guard let self else { return }
            guard self.isActiveRewriteRequest(rewriteRequestID) else { return }

            self.currentCancellable = activeProvider.rewrite(
                text: text,
                options: options,
                streamHandler: { [weak self] output in
                    self?.deliverOnMain {
                        guard let self, self.isActiveRewriteRequest(rewriteRequestID) else { return }
                        self.currentOutput = output
                        streamHandler(output)
                    }
                },
                completion: { [weak self] result in
                    guard let self else { return }
                    self.deliverOnMain {
                        switch result {
                        case .success(let output):
                            finalizeRequest(.success(output), output)
                        case .failure(let failure):
                            Task {
                                if settings.offlineCacheEnabled,
                                   let cached = await self.cacheStore.lookup(for: cacheKey) {
                                    await MainActor.run { [weak self] in
                                        guard let self else { return }
                                        if self.isActiveRewriteRequest(rewriteRequestID) {
                                            streamHandler(cached)
                                        }
                                        finalizeRequest(.success(cached), cached)
                                    }
                                    return
                                }

                                await MainActor.run {
                                    finalizeRequest(.failure(failure), nil)
                                }
                            }
                        }
                    }
                }
            )
        }

        if requestProviderType == .local {
            localWorkerLifecycleQueue.async { [weak self] in
                self?.deliverOnMain {
                    startProviderRewrite()
                }
            }
        } else {
            deliverOnMain {
                startProviderRewrite()
            }
        }
    }


    func rewrite(
        text: String,
        options: RewriteOptions,
        streamHandler: @escaping (String) -> Void,
        completion: @escaping (Result<String, LLMError>) -> Void
    ) {
        rewrite(
            text: text,
            options: options,
            providerOverride: nil,
            streamHandler: streamHandler,
            completion: completion
        )
    }

    func rewriteForService(
        text: String,
        style: RewriteStyle,
        completion: @escaping (Result<String, LLMError>) -> Void
    ) {
        let settings = SettingsManager.shared
        let options = RewriteOptions(
            style: style,
            aggressiveness: settings.aggressiveness,
            streaming: false,
            skill: settings.selectedSkill
        )

        rewrite(text: text, options: options, providerOverride: nil, streamHandler: { _ in }, completion: completion)
    }

    func rewriteSync(text: String, style: RewriteStyle) -> Result<String, LLMError> {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var result: Result<String, LLMError> = .failure(.cancelled)
        var didComplete = false

        let options = RewriteOptions(
            style: style,
            aggressiveness: SettingsManager.shared.aggressiveness,
            streaming: false,
            skill: SettingsManager.shared.selectedSkill
        )

        rewrite(text: text, options: options, streamHandler: { _ in }) { res in
            lock.lock()
            defer { lock.unlock() }
            guard !didComplete else { return }
            didComplete = true
            result = res
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 60) == .timedOut {
            lock.lock()
            let alreadyCompleted = didComplete
            didComplete = true
            lock.unlock()

            if !alreadyCompleted {
                cancel()
                return .failure(.networkError(URLError(.timedOut)))
            }
        }

        return result
    }

    func cancel() {
        currentCancellable?.cancel()
        currentCancellable = nil
        isProcessing = false
        invalidateActiveRewriteRequest()

        if let providerType = activeRewriteProviderType {
            maybeUnloadLocalModelAfterRequest(
                providerType: providerType,
                settings: SettingsManager.shared,
                forceUnload: true
            )
            activeRewriteProviderType = nil
        }
    }

    func unloadLocalModel(completion: @escaping (Result<Void, LLMError>) -> Void = { _ in }) {
        let settings = SettingsManager.shared
        guard settings.selectedProvider == .local else {
            completion(.success(()))
            return
        }

        guard isLocalModelLoaded else {
            completion(.success(()))
            return
        }

        guard !isUnloadingLocalModel else { return }

        cancel()
        isUnloadingLocalModel = true

        localWorkerLifecycleQueue.async { [weak self] in
            guard let self else { return }

            let semaphore = DispatchSemaphore(value: 0)
            var unloadResult: Result<Void, LLMError> = .success(())
            LocalModelProvider.unloadFromMemory { result in
                unloadResult = result
                semaphore.signal()
            }
            semaphore.wait()

            self.deliverOnMain {
                self.isUnloadingLocalModel = false

                switch unloadResult {
                case .success:
                    self.clearLocalModelLoadedState()
                    completion(.success(()))
                case .failure(let error):
                    self.error = error
                    completion(.failure(error))
                }
            }
        }
    }

    func loadLocalModel(completion: @escaping (Result<Void, LLMError>) -> Void = { _ in }) {
        let settings = SettingsManager.shared
        guard settings.selectedProvider == .local else {
            completion(.success(()))
            return
        }

        let localModelName = settings.modelDefault(for: .local)
        guard !localModelName.isEmpty else {
            let error = LLMError.localModelUnavailable("Add a local model path for this model in Provider settings.")
            self.error = error
            completion(.failure(error))
            return
        }

        guard let modelPath = settings.localModelPath(for: localModelName) else {
            let error = LLMError.localModelUnavailable("Add a local model path for this model in Provider settings.")
            self.error = error
            completion(.failure(error))
            return
        }

        if isLocalModelLoaded,
           loadedLocalModelName?.caseInsensitiveCompare(localModelName) == .orderedSame {
            completion(.success(()))
            return
        }

        guard !isLoadingLocalModel, !isUnloadingLocalModel else { return }

        isLoadingLocalModel = true
        localWorkerLifecycleQueue.async { [weak self] in
            guard let self else { return }

            let semaphore = DispatchSemaphore(value: 0)
            var loadResult: Result<Void, LLMError> = .success(())
            LocalModelProvider.preloadToMemory(modelName: localModelName, modelPath: modelPath) { result in
                loadResult = result
                semaphore.signal()
            }
            semaphore.wait()

            self.deliverOnMain {
                self.isLoadingLocalModel = false

                switch loadResult {
                case .success:
                    self.isLocalModelLoaded = true
                    self.loadedLocalModelName = localModelName
                    completion(.success(()))
                case .failure(let error):
                    self.error = error
                    completion(.failure(error))
                }
            }
        }
    }

    var hasValidProvider: Bool {
        let settings = SettingsManager.shared
        let selectedProvider = settings.selectedProvider

        switch selectedProvider {
        case .local:
            let localModelName = settings.modelDefault(for: .local)
            guard !localModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            return settings.localModelPath(for: localModelName) != nil

        case .openai, .anthropic, .xai:
            guard let apiKey = settings.apiKey(for: selectedProvider) else {
                return false
            }
            return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func deliverOnMain(_ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async(execute: action)
        }
    }

    private func clearLocalModelLoadedState() {
        let applyClear: (RewriteEngine) -> Void = { engine in
            guard engine.isLocalModelLoaded || engine.loadedLocalModelName != nil || engine.isLoadingLocalModel else {
                return
            }
            engine.isLocalModelLoaded = false
            engine.loadedLocalModelName = nil
            engine.isLoadingLocalModel = false
        }

        if Thread.isMainThread {
            applyClear(self)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                applyClear(self)
            }
        }
    }

    private func releaseLocalWorkerResources() {
        clearLocalModelLoadedState()
        localWorkerLifecycleQueue.async {
            let semaphore = DispatchSemaphore(value: 0)
            LocalModelProvider.unloadFromMemory { _ in
                semaphore.signal()
            }
            semaphore.wait()
        }
    }

    private func maybeUnloadLocalModelAfterRequest(
        providerType: LLMProviderType,
        settings: SettingsManager,
        forceUnload: Bool = false
    ) {
        guard providerType == .local else { return }
        guard forceUnload || !settings.keepLocalModelLoaded else { return }
        releaseLocalWorkerResources()
    }

    private func syncLocalWorkerStateForNonLocalSelection(previousProviderType: LLMProviderType?) {
        if previousProviderType == .local || isLocalModelLoaded || loadedLocalModelName != nil {
            releaseLocalWorkerResources()
        } else {
            clearLocalModelLoadedState()
        }
    }

    private func beginRewriteRequest() -> UUID {
        rewriteRequestLock.lock()
        defer { rewriteRequestLock.unlock() }
        let id = UUID()
        activeRewriteRequestID = id
        completedRewriteRequestID = nil
        return id
    }

    private func isActiveRewriteRequest(_ id: UUID) -> Bool {
        rewriteRequestLock.lock()
        defer { rewriteRequestLock.unlock() }
        return activeRewriteRequestID == id
    }

    private func markRewriteRequestCompleted(
        _ id: UUID,
        result: Result<String, LLMError>,
        completion: @escaping (Result<String, LLMError>) -> Void
    ) -> Bool {
        rewriteRequestLock.lock()
        if completedRewriteRequestID == id {
            rewriteRequestLock.unlock()
            return false
        }
        completedRewriteRequestID = id
        rewriteRequestLock.unlock()

        completion(result)

        return isActiveRewriteRequest(id)
    }

    private func invalidateActiveRewriteRequest() {
        rewriteRequestLock.lock()
        activeRewriteRequestID = UUID()
        completedRewriteRequestID = nil
        rewriteRequestLock.unlock()
    }

    private func resolvedModelName(for provider: LLMProviderType, settings: SettingsManager) -> String {
        settings.modelDefault(for: provider)
    }

    private func makeCacheKey(text: String, options: RewriteOptions, providerName: String, model: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        let textHash = digest.compactMap { String(format: "%02x", $0) }.joined()

        return [providerName, model, textHash, options.cacheKeyComponent].joined(separator: "|")
    }
}

private actor RewriteCacheStore {
    private struct CacheEntry: Codable {
        let key: String
        let value: String
        let createdAt: Date
    }

    private var entries: [String: CacheEntry] = [:]
    private var hasLoaded = false
    private var persistTask: Task<Void, Never>?
    private let maxEntries = 300
    private static let persistDelayNanoseconds: UInt64 = 350_000_000

    func lookup(for key: String) async -> String? {
        await loadIfNeeded()
        return entries[key]?.value
    }

    func store(value: String, for key: String) async {
        await loadIfNeeded()

        entries[key] = CacheEntry(key: key, value: value, createdAt: Date())
        if entries.count > maxEntries,
           let oldestKey = entries.min(by: { $0.value.createdAt < $1.value.createdAt })?.key {
            entries.removeValue(forKey: oldestKey)
        }

        schedulePersist()
    }

    private func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        guard let data = try? Data(contentsOf: fileURL(), options: [.mappedIfSafe]) else {
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let saved = try? decoder.decode([CacheEntry].self, from: data) {
            let newest = saved.sorted(by: { $0.createdAt > $1.createdAt }).prefix(maxEntries)
            entries = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0) })
        }
    }

    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.persistDelayNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.persist()
        }
    }

    private func persist() async {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(Array(entries.values)) else {
            return
        }

        do {
            let url = fileURL()
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try data.write(to: url, options: .atomic)
        } catch {
            AppLogger.shared.error("Failed to persist rewrite cache: \(error.localizedDescription)")
        }
    }

    private func fileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport
            .appendingPathComponent("ClipboardRefiner", isDirectory: true)
            .appendingPathComponent("rewrite-cache.json")
    }
}
