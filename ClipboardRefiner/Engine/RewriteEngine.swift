import Foundation
import Combine
import CryptoKit

final class RewriteEngine: ObservableObject {
    static let shared = RewriteEngine()

    @Published var isProcessing = false
    @Published var currentOutput = ""
    @Published var error: LLMError?

    private var currentCancellable: Cancellable?
    private var provider: LLMProvider?

    private let cacheStore = RewriteCacheStore()

    private init() {
        updateProvider()
    }

    func updateProvider() {
        let settings = SettingsManager.shared

        switch settings.selectedProvider {
        case .openai:
            guard let apiKey = settings.apiKey, !apiKey.isEmpty else {
                provider = nil
                return
            }
            provider = OpenAIProvider(
                apiKey: apiKey,
                model: settings.selectedModel,
                reasoningEffort: settings.openAIReasoningEffort
            )

        case .anthropic:
            guard let apiKey = settings.apiKey, !apiKey.isEmpty else {
                provider = nil
                return
            }
            provider = AnthropicProvider(apiKey: apiKey, model: settings.selectedModel)

        case .xai:
            guard let apiKey = settings.apiKey, !apiKey.isEmpty else {
                provider = nil
                return
            }
            provider = XAIProvider(apiKey: apiKey, model: settings.selectedModel)

        case .local:
            guard settings.isSelectedLocalModelConfigured else {
                provider = nil
                return
            }
            guard let modelPath = settings.selectedLocalModelPath else {
                provider = nil
                return
            }
            provider = LocalModelProvider(modelName: settings.selectedModel, modelPath: modelPath)
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

        let settings = SettingsManager.shared
        let cacheKey = makeCacheKey(
            text: text,
            options: options,
            providerName: providerOverride?.name ?? settings.selectedProvider.rawValue,
            model: settings.selectedModel
        )

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
                        await MainActor.run {
                            self.currentOutput = cached
                            streamHandler(cached)
                            completion(.success(cached))
                        }
                        return
                    }

                    await MainActor.run {
                        self.error = missingProviderError
                        completion(.failure(missingProviderError))
                    }
                }
                return
            }

            activeProvider = provider
        }

        isProcessing = true
        error = nil
        currentOutput = ""

        AppLogger.shared.info("Starting rewrite with style: \(options.style.rawValue)")

        currentCancellable = activeProvider.rewrite(
            text: text,
            options: options,
            streamHandler: { [weak self] output in
                self?.currentOutput = output
                streamHandler(output)
            },
            completion: { [weak self] result in
                guard let self else { return }

                self.isProcessing = false

                switch result {
                case .success(let output):
                    AppLogger.shared.info("Rewrite completed successfully")
                    self.currentOutput = output

                    if settings.historyEnabled {
                        let entry = HistoryEntry(
                            originalText: text,
                            rewrittenText: output,
                            style: options.style.rawValue,
                            provider: activeProvider.name
                        )
                        settings.addHistoryEntry(entry)
                    }

                    if settings.offlineCacheEnabled {
                        Task {
                            await self.cacheStore.store(value: output, for: cacheKey)
                        }
                    }

                    completion(.success(output))

                case .failure(let failure):
                    AppLogger.shared.error("Rewrite failed: \(failure.localizedDescription)")

                    Task {
                        if settings.offlineCacheEnabled,
                           let cached = await self.cacheStore.lookup(for: cacheKey) {
                            await MainActor.run {
                                self.currentOutput = cached
                                streamHandler(cached)
                                completion(.success(cached))
                            }
                            return
                        }

                        await MainActor.run {
                            self.error = failure
                            completion(.failure(failure))
                        }
                    }
                }
            }
        )
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
    }

    var hasValidProvider: Bool {
        updateProvider()
        return provider != nil
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
    private let maxEntries = 300

    func lookup(for key: String) async -> String? {
        await loadIfNeeded()
        return entries[key]?.value
    }

    func store(value: String, for key: String) async {
        await loadIfNeeded()

        entries[key] = CacheEntry(key: key, value: value, createdAt: Date())
        if entries.count > maxEntries {
            let sorted = entries.values.sorted(by: { $0.createdAt > $1.createdAt })
            entries = Dictionary(uniqueKeysWithValues: sorted.prefix(maxEntries).map { ($0.key, $0) })
        }

        await persist()
    }

    private func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        guard let data = try? Data(contentsOf: fileURL()) else {
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let saved = try? decoder.decode([CacheEntry].self, from: data) {
            entries = Dictionary(uniqueKeysWithValues: saved.map { ($0.key, $0) })
        }
    }

    private func persist() async {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let sortedEntries = entries.values.sorted(by: { $0.createdAt > $1.createdAt })
        guard let data = try? encoder.encode(sortedEntries) else {
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
