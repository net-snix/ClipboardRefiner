import Foundation

enum ProviderHTTP {
    static func perform(
        request: URLRequest,
        cancellable: URLSessionTaskCancellable,
        completion: @escaping (Result<(Data, HTTPURLResponse), LLMError>) -> Void
    ) {
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error as? URLError, error.code == .cancelled {
                completion(.failure(.cancelled))
                return
            }

            if let error {
                completion(.failure(.networkError(error)))
                return
            }

            guard let http = response as? HTTPURLResponse, let data else {
                completion(.failure(.invalidResponse))
                return
            }

            completion(.success((data, http)))
        }

        cancellable.setTask(task)
        task.resume()
    }

    static func performSSE(
        request: URLRequest,
        cancellable: TaskCancellable,
        eventHandler: @escaping (_ event: String?, _ data: String) -> Void,
        completion: @escaping (Result<Void, LLMError>) -> Void
    ) {
        let task = Task {
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse else {
                    deliverOnMain {
                        completion(.failure(.invalidResponse))
                    }
                    return
                }

                guard (200...299).contains(http.statusCode) else {
                    var data = Data()
                    for try await line in bytes.lines {
                        if let lineData = line.data(using: .utf8) {
                            data.append(lineData)
                            data.append(0x0A)
                            if data.count >= 32_768 {
                                break
                            }
                        }
                    }

                    let error: LLMError
                    if http.statusCode == 429 {
                        error = .rateLimited
                    } else {
                        error = .serverError(http.statusCode, serverMessage(from: data))
                    }

                    deliverOnMain {
                        completion(.failure(error))
                    }
                    return
                }

                var currentEvent: String?
                var dataLines: [String] = []

                func flushEvent() {
                    guard !dataLines.isEmpty else {
                        currentEvent = nil
                        return
                    }

                    let payload = dataLines.joined(separator: "\n")
                    eventHandler(currentEvent, payload)
                    currentEvent = nil
                    dataLines.removeAll(keepingCapacity: true)
                }

                for try await line in bytes.lines {
                    if Task.isCancelled {
                        throw CancellationError()
                    }

                    if line.isEmpty {
                        flushEvent()
                        continue
                    }

                    if line.hasPrefix(":") {
                        continue
                    }

                    if line.hasPrefix("event:") {
                        currentEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                        continue
                    }

                    if line.hasPrefix("data:") {
                        dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                    }
                }

                flushEvent()
                deliverOnMain {
                    completion(.success(()))
                }
            } catch let error as URLError where error.code == .cancelled {
                deliverOnMain {
                    completion(.failure(.cancelled))
                }
            } catch is CancellationError {
                deliverOnMain {
                    completion(.failure(.cancelled))
                }
            } catch {
                deliverOnMain {
                    completion(.failure(.networkError(error)))
                }
            }
        }

        cancellable.setTask(task)
    }

    static func decodeJSON(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func serverMessage(from data: Data) -> String? {
        guard let json = decodeJSON(data) else { return nil }

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }

        if let message = json["message"] as? String {
            return message
        }

        return nil
    }

    static func handleStatus(_ response: HTTPURLResponse, data: Data) -> LLMError? {
        if response.statusCode == 429 {
            return .rateLimited
        }

        guard (200...299).contains(response.statusCode) else {
            return .serverError(response.statusCode, serverMessage(from: data))
        }

        return nil
    }

    static func deliverOnMain(_ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async(execute: action)
        }
    }
}

final class OpenAIProvider: LLMProvider {
    let name = "OpenAI"
    let providerType = LLMProviderType.openai

    private let apiKey: String
    private let model: String
    private let reasoningEffort: OpenAIReasoningEffort
    private let endpoint = URL(string: "https://api.openai.com/v1/responses")!

    init(apiKey: String, model: String = "gpt-5.2", reasoningEffort: OpenAIReasoningEffort = .none) {
        self.apiKey = apiKey
        self.model = model
        self.reasoningEffort = reasoningEffort
    }

    func rewrite(
        text: String,
        options: RewriteOptions,
        streamHandler: @escaping (String) -> Void,
        completion: @escaping (Result<String, LLMError>) -> Void
    ) -> Cancellable {
        guard !apiKey.isEmpty else {
            completion(.failure(.invalidAPIKey))
            return URLSessionTaskCancellable()
        }

        let wrappedSourceText = options.wrappedUserSourceText(text)
        var userContent: [[String: Any]] = [["type": "input_text", "text": wrappedSourceText]]
        userContent.append(contentsOf: options.imageAttachments.map {
            ["type": "input_image", "image_url": $0.dataURL]
        })

        var body: [String: Any] = [
            "model": model,
            "instructions": options.fullSystemPrompt,
            "input": [[
                "role": "user",
                "content": userContent
            ]],
            "stream": options.streaming,
            "max_output_tokens": 4096
        ]

        if SettingsManager.isOpenAIReasoningModel(model), reasoningEffort != .none {
            body["reasoning"] = ["effort": reasoningEffort.rawValue]
        } else {
            body["temperature"] = options.temperature
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if options.streaming {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(.networkError(error)))
            return URLSessionTaskCancellable()
        }

        if options.streaming {
            let cancellable = TaskCancellable()
            var accumulatedOutput = ""
            var streamErrorMessage: String?

            ProviderHTTP.performSSE(
                request: request,
                cancellable: cancellable,
                eventHandler: { event, data in
                    guard data != "[DONE]" else { return }
                    guard let payload = data.data(using: .utf8),
                          let json = ProviderHTTP.decodeJSON(payload) else {
                        return
                    }

                    if let streamError = Self.extractStreamError(from: json) {
                        streamErrorMessage = streamError
                    }

                    if let delta = Self.extractStreamDelta(event: event, from: json) {
                        Self.mergeStreamOutput(delta, into: &accumulatedOutput, streamHandler: streamHandler)
                    }

                    if let snapshot = Self.extractStreamSnapshot(event: event, from: json) {
                        Self.mergeStreamOutput(snapshot, into: &accumulatedOutput, streamHandler: streamHandler)
                    }
                },
                completion: { result in
                    switch result {
                    case .failure(let error):
                        completion(.failure(error))
                    case .success:
                        guard !accumulatedOutput.isEmpty else {
                            if let streamErrorMessage {
                                completion(.failure(.streamingError(streamErrorMessage)))
                            } else {
                                completion(.failure(.invalidResponse))
                            }
                            return
                        }
                        completion(.success(accumulatedOutput))
                    }
                }
            )

            return cancellable
        }

        let cancellable = URLSessionTaskCancellable()
        ProviderHTTP.perform(request: request, cancellable: cancellable) { result in
            switch result {
            case .failure(let error):
                ProviderHTTP.deliverOnMain {
                    completion(.failure(error))
                }
            case .success(let (data, response)):
                if let error = ProviderHTTP.handleStatus(response, data: data) {
                    ProviderHTTP.deliverOnMain {
                        completion(.failure(error))
                    }
                    return
                }

                guard let json = ProviderHTTP.decodeJSON(data),
                      let output = Self.extractOutputText(from: json),
                      !output.isEmpty else {
                    ProviderHTTP.deliverOnMain {
                        completion(.failure(.invalidResponse))
                    }
                    return
                }

                ProviderHTTP.deliverOnMain {
                    streamHandler(output)
                    completion(.success(output))
                }
            }
        }

        return cancellable
    }

    private static func extractStreamError(from json: [String: Any]) -> String? {
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return message
        }

        if let message = json["message"] as? String, !message.isEmpty {
            return message
        }

        return nil
    }

    private static func extractStreamDelta(event: String?, from json: [String: Any]) -> String? {
        let type = event ?? (json["type"] as? String)
        guard type == "response.output_text.delta" || type == "response.output.delta" else {
            return nil
        }

        guard let delta = json["delta"] as? String, !delta.isEmpty else {
            return nil
        }
        return delta
    }

    private static func extractStreamSnapshot(event: String?, from json: [String: Any]) -> String? {
        let type = event ?? (json["type"] as? String)
        guard type == "response.output_text.done"
            || type == "response.completed"
            || type == "response.output_item.done"
            || type == "response.output_text.delta" else {
            return nil
        }

        if let outputText = json["output_text"] as? String, !outputText.isEmpty {
            return outputText
        }

        if let response = json["response"] as? [String: Any],
           let output = extractOutputText(from: response),
           !output.isEmpty {
            return output
        }

        if let output = extractOutputText(from: json), !output.isEmpty {
            return output
        }

        return nil
    }

    private static func mergeStreamOutput(
        _ candidate: String,
        into accumulated: inout String,
        streamHandler: @escaping (String) -> Void
    ) {
        guard !candidate.isEmpty else { return }

        let updatedValue: String
        if candidate.hasPrefix(accumulated) {
            guard candidate.count > accumulated.count else { return }
            updatedValue = candidate
        } else {
            updatedValue = accumulated + candidate
        }

        guard updatedValue != accumulated else { return }
        accumulated = updatedValue
        ProviderHTTP.deliverOnMain {
            streamHandler(updatedValue)
        }
    }

    private static func extractOutputText(from json: [String: Any]) -> String? {
        if let direct = json["output_text"] as? String, !direct.isEmpty {
            return direct
        }

        guard let outputItems = json["output"] as? [[String: Any]] else {
            return nil
        }

        var combined = ""
        for item in outputItems {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for part in content {
                if part["type"] as? String == "output_text", let text = part["text"] as? String {
                    combined += text
                }
            }
        }

        return combined.isEmpty ? nil : combined
    }
}

final class XAIProvider: LLMProvider {
    let name = "xAI"
    let providerType = LLMProviderType.xai

    private let apiKey: String
    private let model: String
    private let endpoint = URL(string: "https://api.x.ai/v1/chat/completions")!

    init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.model = model
    }

    func rewrite(
        text: String,
        options: RewriteOptions,
        streamHandler: @escaping (String) -> Void,
        completion: @escaping (Result<String, LLMError>) -> Void
    ) -> Cancellable {
        guard !apiKey.isEmpty else {
            completion(.failure(.invalidAPIKey))
            return URLSessionTaskCancellable()
        }

        let wrappedSourceText = options.wrappedUserSourceText(text)
        let userContent: Any
        if options.imageAttachments.isEmpty {
            userContent = wrappedSourceText
        } else {
            var parts: [[String: Any]] = [["type": "text", "text": wrappedSourceText]]
            parts.append(contentsOf: options.imageAttachments.map {
                [
                    "type": "image_url",
                    "image_url": [
                        "url": $0.dataURL,
                        "detail": "auto"
                    ]
                ]
            })
            userContent = parts
        }

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": options.fullSystemPrompt],
                ["role": "user", "content": userContent]
            ],
            "temperature": options.temperature,
            "stream": options.streaming
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if options.streaming {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(.networkError(error)))
            return URLSessionTaskCancellable()
        }

        if options.streaming {
            let cancellable = TaskCancellable()
            var accumulatedOutput = ""
            var streamErrorMessage: String?

            ProviderHTTP.performSSE(
                request: request,
                cancellable: cancellable,
                eventHandler: { _, data in
                    guard data != "[DONE]" else { return }
                    guard let payload = data.data(using: .utf8),
                          let json = ProviderHTTP.decodeJSON(payload) else {
                        return
                    }

                    if let streamError = Self.extractStreamError(from: json) {
                        streamErrorMessage = streamError
                    }

                    if let delta = Self.extractStreamDelta(from: json) {
                        Self.mergeStreamOutput(delta, into: &accumulatedOutput, streamHandler: streamHandler)
                    }

                    if let snapshot = Self.extractStreamSnapshot(from: json) {
                        Self.mergeStreamOutput(snapshot, into: &accumulatedOutput, streamHandler: streamHandler)
                    }
                },
                completion: { result in
                    switch result {
                    case .failure(let error):
                        completion(.failure(error))
                    case .success:
                        guard !accumulatedOutput.isEmpty else {
                            if let streamErrorMessage {
                                completion(.failure(.streamingError(streamErrorMessage)))
                            } else {
                                completion(.failure(.invalidResponse))
                            }
                            return
                        }
                        completion(.success(accumulatedOutput))
                    }
                }
            )

            return cancellable
        }

        let cancellable = URLSessionTaskCancellable()
        ProviderHTTP.perform(request: request, cancellable: cancellable) { result in
            switch result {
            case .failure(let error):
                ProviderHTTP.deliverOnMain {
                    completion(.failure(error))
                }
            case .success(let (data, response)):
                if let error = ProviderHTTP.handleStatus(response, data: data) {
                    ProviderHTTP.deliverOnMain {
                        completion(.failure(error))
                    }
                    return
                }

                guard let json = ProviderHTTP.decodeJSON(data),
                      let text = Self.extractText(from: json),
                      !text.isEmpty else {
                    ProviderHTTP.deliverOnMain {
                        completion(.failure(.invalidResponse))
                    }
                    return
                }

                ProviderHTTP.deliverOnMain {
                    streamHandler(text)
                    completion(.success(text))
                }
            }
        }

        return cancellable
    }

    private static func extractText(from json: [String: Any]) -> String? {
        guard let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any] else {
            return nil
        }

        if let text = message["content"] as? String {
            return text
        }

        if let parts = message["content"] as? [[String: Any]] {
            let combined = parts.compactMap { $0["text"] as? String }.joined()
            return combined.isEmpty ? nil : combined
        }

        return nil
    }

    private static func extractStreamError(from json: [String: Any]) -> String? {
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return message
        }

        if let message = json["message"] as? String, !message.isEmpty {
            return message
        }

        return nil
    }

    private static func extractStreamDelta(from json: [String: Any]) -> String? {
        guard let choices = json["choices"] as? [[String: Any]], !choices.isEmpty else {
            return nil
        }

        for choice in choices {
            guard let delta = choice["delta"] as? [String: Any] else { continue }

            if let text = delta["content"] as? String, !text.isEmpty {
                return text
            }

            if let parts = delta["content"] as? [[String: Any]] {
                let joined = parts.compactMap { $0["text"] as? String }.joined()
                if !joined.isEmpty {
                    return joined
                }
            }
        }

        return nil
    }

    private static func extractStreamSnapshot(from json: [String: Any]) -> String? {
        extractText(from: json)
    }

    private static func mergeStreamOutput(
        _ candidate: String,
        into accumulated: inout String,
        streamHandler: @escaping (String) -> Void
    ) {
        guard !candidate.isEmpty else { return }

        let updatedValue: String
        if candidate.hasPrefix(accumulated) {
            guard candidate.count > accumulated.count else { return }
            updatedValue = candidate
        } else {
            updatedValue = accumulated + candidate
        }

        guard updatedValue != accumulated else { return }
        accumulated = updatedValue
        ProviderHTTP.deliverOnMain {
            streamHandler(updatedValue)
        }
    }
}

final class LocalModelProvider: LLMProvider {
    let name = "Local"
    let providerType = LLMProviderType.local

    private let modelName: String
    private let modelPath: String
    private static let worker = LocalModelWorker()

    init(modelName: String, modelPath: String) {
        self.modelName = modelName
        self.modelPath = modelPath
    }

    func rewrite(
        text: String,
        options: RewriteOptions,
        streamHandler: @escaping (String) -> Void,
        completion: @escaping (Result<String, LLMError>) -> Void
    ) -> Cancellable {
        let cancellable = ProcessCancellable()

        let trimmedPath = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            completion(.failure(.localModelUnavailable("Model path is empty.")))
            return cancellable
        }

        guard FileManager.default.fileExists(atPath: trimmedPath) else {
            completion(.failure(.localModelUnavailable("Model path does not exist: \(trimmedPath)")))
            return cancellable
        }

        guard options.imageAttachments.isEmpty else {
            completion(.failure(.localModelUnavailable("Local provider currently supports text-only prompts.")))
            return cancellable
        }

        let wrappedSourceText = options.wrappedUserSourceText(text)
        let prompt = """
        System:
        \(options.fullSystemPrompt)

        User:
        \(wrappedSourceText)

        Assistant:
        """

        let requestID = UUID()
        let task = Task(priority: .userInitiated) { [modelName] in
            do {
                let outputText = try await Self.worker.generate(
                    prompt: prompt,
                    modelPath: trimmedPath,
                    temperature: options.temperature,
                    maxTokens: 2048,
                    requestID: requestID
                ).trimmingCharacters(in: .whitespacesAndNewlines)

                await MainActor.run {
                    if cancellable.isCancelled {
                        completion(.failure(.cancelled))
                        return
                    }

                    guard !outputText.isEmpty else {
                        completion(.failure(.invalidResponse))
                        return
                    }

                    streamHandler(outputText)
                    completion(.success(outputText))
                }
            } catch let error as LLMError {
                await MainActor.run {
                    completion(.failure(error))
                }
            } catch is CancellationError {
                await MainActor.run {
                    completion(.failure(.cancelled))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(.localModelUnavailable("Failed to run local model '\(modelName)': \(error.localizedDescription)")))
                }
            }
        }
        cancellable.setTask(task)
        cancellable.setCancelHandler {
            await Self.worker.cancel(requestID: requestID)
        }

        return cancellable
    }

    static func preloadToMemory(
        modelName: String,
        modelPath: String,
        completion: @escaping (Result<Void, LLMError>) -> Void
    ) {
        let trimmedPath = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            completion(.failure(.localModelUnavailable("Model path is empty.")))
            return
        }

        guard FileManager.default.fileExists(atPath: trimmedPath) else {
            completion(.failure(.localModelUnavailable("Model path does not exist: \(trimmedPath)")))
            return
        }

        Task(priority: .userInitiated) {
            do {
                try await Self.worker.preload(modelPath: trimmedPath)
                completion(.success(()))
            } catch let error as LLMError {
                completion(.failure(error))
            } catch {
                completion(.failure(.localModelUnavailable("Failed to load local model '\(modelName)': \(error.localizedDescription)")))
            }
        }
    }

    static func unloadFromMemory(completion: @escaping (Result<Void, LLMError>) -> Void) {
        Task(priority: .utility) {
            await Self.worker.unload()
            completion(.success(()))
        }
    }
}

private actor LocalModelWorker {
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?
    private var processGeneration = UUID()
    private var activeModelPath: String?
    private var pendingRequestID: UUID?
    private var pendingContinuation: CheckedContinuation<[String: Any], Error>?
    private var stderrTail: [String] = []
    private var lastProtocolError: String?

    func preload(modelPath: String) async throws {
        try await ensureProcess(for: modelPath)
    }

    func generate(
        prompt: String,
        modelPath: String,
        temperature: Double,
        maxTokens: Int,
        requestID: UUID
    ) async throws -> String {
        try await ensureProcess(for: modelPath)
        let response = try await sendAndAwaitResponse(
            payload: [
                "command": "generate",
                "prompt": prompt,
                "temperature": temperature,
                "max_tokens": maxTokens
            ],
            requestID: requestID
        )

        let status = response["status"] as? String ?? "error"
        guard status == "ok" else {
            let message = response["message"] as? String
                ?? fallbackErrorMessage(defaultMessage: "Local generation failed.")
            throw LLMError.localModelUnavailable(message)
        }

        return response["output"] as? String ?? ""
    }

    func cancel(requestID: UUID) {
        guard pendingRequestID == requestID else { return }
        resumePending(with: .failure(LLMError.cancelled))
        terminateProcess()
    }

    func unload() {
        if pendingContinuation != nil {
            resumePending(with: .failure(LLMError.cancelled))
        }

        do {
            try send(payload: ["command": "shutdown"])
        } catch {
            // Best effort shutdown.
        }

        terminateProcess()
    }

    private func ensureProcess(for modelPath: String) async throws {
        if process?.isRunning == true, activeModelPath == modelPath {
            return
        }

        terminateProcess()

        do {
            try startProcess(modelPath: modelPath)
            let pingResponse = try await sendAndAwaitResponse(
                payload: ["command": "ping"],
                requestID: nil
            )

            guard (pingResponse["status"] as? String) == "ok" else {
                let message = pingResponse["message"] as? String
                    ?? fallbackErrorMessage(defaultMessage: "Failed to initialize local model worker.")
                throw LLMError.localModelUnavailable(message)
            }
        } catch let error as LLMError {
            throw error
        } catch {
            throw LLMError.localModelUnavailable("Failed to start local model worker: \(error.localizedDescription)")
        }
    }

    private func startProcess(modelPath: String) throws {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()
        let generation = UUID()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3",
            "-u",
            "-c",
            Self.workerPythonScript,
            modelPath
        ]
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = stdin
        processGeneration = generation
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task {
                await self?.handleTermination(status: status, generation: generation)
            }
        }

        do {
            try process.run()
        } catch {
            processGeneration = UUID()
            throw error
        }

        self.process = process
        self.stdinHandle = stdin.fileHandleForWriting
        self.activeModelPath = modelPath
        self.stderrTail.removeAll(keepingCapacity: true)
        self.lastProtocolError = nil
        startReaders(stdout: stdout.fileHandleForReading, stderr: stderr.fileHandleForReading)
    }

    private func startReaders(stdout: FileHandle, stderr: FileHandle) {
        stdoutTask?.cancel()
        stderrTask?.cancel()

        stdoutTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                for try await line in stdout.bytes.lines {
                    await self?.handleStdoutLine(line)
                }
            } catch {
                await self?.appendStderr("Failed to read local worker stdout: \(error.localizedDescription)")
            }
        }

        stderrTask = Task.detached(priority: .utility) { [weak self] in
            do {
                for try await line in stderr.bytes.lines {
                    await self?.appendStderr(line)
                }
            } catch {
                await self?.appendStderr("Failed to read local worker stderr: \(error.localizedDescription)")
            }
        }
    }

    private func appendStderr(_ line: String) {
        guard !line.isEmpty else { return }
        stderrTail.append(line)
        if stderrTail.count > 20 {
            stderrTail.removeFirst(stderrTail.count - 20)
        }
    }

    private func handleStdoutLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            if pendingContinuation != nil {
                resumePending(with: .failure(LLMError.localModelUnavailable("Invalid response from local model worker.")))
            } else if !line.isEmpty {
                lastProtocolError = line
            }
            return
        }

        if pendingContinuation != nil {
            resumePending(with: .success(json))
            return
        }

        if (json["status"] as? String) == "error",
           let message = json["message"] as? String {
            lastProtocolError = message
        }
    }

    private func handleTermination(status: Int32, generation: UUID) {
        guard generation == processGeneration else { return }

        if pendingContinuation != nil {
            let message = fallbackErrorMessage(
                defaultMessage: status == 0
                    ? "Local model worker exited unexpectedly."
                    : "Local model worker exited with status \(status)."
            )
            resumePending(with: .failure(LLMError.localModelUnavailable(message)))
        }

        clearProcessState()
    }

    private func sendAndAwaitResponse(
        payload: [String: Any],
        requestID: UUID?
    ) async throws -> [String: Any] {
        guard pendingContinuation == nil else {
            throw LLMError.localModelUnavailable("Local model worker is busy.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingContinuation = continuation
            pendingRequestID = requestID

            do {
                try send(payload: payload)
            } catch {
                pendingContinuation = nil
                pendingRequestID = nil
                continuation.resume(throwing: LLMError.localModelUnavailable(
                    "Failed to send request to local model worker: \(error.localizedDescription)"
                ))
            }
        }
    }

    private func send(payload: [String: Any]) throws {
        guard let stdinHandle else {
            throw LLMError.localModelUnavailable(
                fallbackErrorMessage(defaultMessage: "Local model worker is not running.")
            )
        }

        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        try stdinHandle.write(contentsOf: payloadData)
        try stdinHandle.write(contentsOf: Data([0x0A]))
    }

    private func resumePending(with result: Result<[String: Any], Error>) {
        guard let continuation = pendingContinuation else { return }
        pendingContinuation = nil
        pendingRequestID = nil
        continuation.resume(with: result)
    }

    private func terminateProcess() {
        if process?.isRunning == true {
            process?.terminate()
        }
        clearProcessState()
    }

    private func clearProcessState() {
        process = nil
        stdinHandle = nil
        processGeneration = UUID()
        activeModelPath = nil
        stdoutTask?.cancel()
        stdoutTask = nil
        stderrTask?.cancel()
        stderrTask = nil
    }

    private func fallbackErrorMessage(defaultMessage: String) -> String {
        if let lastProtocolError, !lastProtocolError.isEmpty {
            return lastProtocolError
        }
        if let stderr = stderrTail.last, !stderr.isEmpty {
            return stderr
        }
        return defaultMessage
    }

    private static let workerPythonScript = #"""
import json
import sys

def emit(payload):
    sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
    sys.stdout.flush()

if len(sys.argv) < 2:
    emit({"status": "error", "message": "Missing model path."})
    sys.exit(1)

model_path = sys.argv[1]

try:
    from mlx_lm import load, generate
except Exception as exc:
    emit({"status": "error", "message": f"mlx_lm import failed: {exc}"})
    sys.exit(1)

try:
    model, tokenizer = load(model_path)
except Exception as exc:
    emit({"status": "error", "message": f"Local model load failed: {exc}"})
    sys.exit(1)

for raw in sys.stdin:
    line = raw.strip()
    if not line:
        continue

    try:
        payload = json.loads(line)
    except Exception as exc:
        emit({"status": "error", "message": f"Invalid JSON payload: {exc}"})
        continue

    command = payload.get("command", "generate")

    if command == "ping":
        emit({"status": "ok", "message": "ready"})
        continue

    if command == "shutdown":
        emit({"status": "ok", "message": "bye"})
        break

    if command != "generate":
        emit({"status": "error", "message": f"Unknown command: {command}"})
        continue

    prompt = payload.get("prompt", "")
    if not prompt:
        emit({"status": "error", "message": "Prompt is empty."})
        continue

    try:
        temperature = float(payload.get("temperature", 0.3))
    except Exception as exc:
        emit({"status": "error", "message": f"Invalid temperature: {exc}"})
        continue

    try:
        max_tokens = int(payload.get("max_tokens", 2048))
    except Exception as exc:
        emit({"status": "error", "message": f"Invalid max_tokens: {exc}"})
        continue

    try:
        output = generate(
            model,
            tokenizer,
            prompt=prompt,
            temp=temperature,
            max_tokens=max_tokens,
            verbose=False,
        )
        emit({"status": "ok", "output": (output or "").strip()})
    except Exception as exc:
        emit({"status": "error", "message": f"Local generation failed: {exc}"})
"""#
}

final class ProcessCancellable: Cancellable {
    private var process: Process?
    private var task: Task<Void, Never>?
    private var cancelHandler: (() async -> Void)?
    private let lock = NSLock()
    private(set) var isCancelled = false

    func setProcess(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldCancel = isCancelled
        lock.unlock()

        if shouldCancel, process.isRunning {
            process.terminate()
        }
    }

    func setTask(_ task: Task<Void, Never>) {
        lock.lock()
        self.task = task
        let shouldCancel = isCancelled
        lock.unlock()

        if shouldCancel {
            task.cancel()
        }
    }

    func setCancelHandler(_ handler: @escaping () async -> Void) {
        lock.lock()
        if isCancelled {
            lock.unlock()
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                await handler()
                semaphore.signal()
            }
            semaphore.wait()
            return
        }
        cancelHandler = handler
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        if isCancelled {
            lock.unlock()
            return
        }
        isCancelled = true
        let process = self.process
        let task = self.task
        let handler = cancelHandler
        lock.unlock()

        task?.cancel()
        if process?.isRunning == true {
            process?.terminate()
        }
        if let handler {
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                await handler()
                semaphore.signal()
            }
            semaphore.wait()
        }
    }
}
