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
        let cancellable = URLSessionTaskCancellable()

        guard !apiKey.isEmpty else {
            completion(.failure(.invalidAPIKey))
            return cancellable
        }

        var userContent: [[String: Any]] = [["type": "input_text", "text": text]]
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
            "stream": false,
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

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(.networkError(error)))
            return cancellable
        }

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
        let cancellable = URLSessionTaskCancellable()

        guard !apiKey.isEmpty else {
            completion(.failure(.invalidAPIKey))
            return cancellable
        }

        let userContent: Any
        if options.imageAttachments.isEmpty {
            userContent = text
        } else {
            var parts: [[String: Any]] = [["type": "text", "text": text]]
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
            "stream": false
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(.networkError(error)))
            return cancellable
        }

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
}

final class LocalModelProvider: LLMProvider {
    let name = "Local"
    let providerType = LLMProviderType.local

    private let modelName: String
    private let modelPath: String

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

        let prompt = """
        System:
        \(options.fullSystemPrompt)

        User:
        \(text)

        Assistant:
        """

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            let stdin = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "python3",
                "-c",
                Self.localPythonScript,
                trimmedPath,
                String(options.temperature)
            ]
            process.standardOutput = stdout
            process.standardError = stderr
            process.standardInput = stdin

            process.terminationHandler = { _ in
                let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                let outputText = String(data: outputData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let errorText = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                DispatchQueue.main.async {
                    if cancellable.isCancelled {
                        completion(.failure(.cancelled))
                        return
                    }

                    guard process.terminationStatus == 0, !outputText.isEmpty else {
                        let message = errorText?.isEmpty == false
                            ? errorText!
                            : "Failed to run local model '\(self.modelName)'. Ensure python3 and mlx-lm are installed."
                        completion(.failure(.localModelUnavailable(message)))
                        return
                    }

                    streamHandler(outputText)
                    completion(.success(outputText))
                }
            }

            do {
                try process.run()
                cancellable.setProcess(process)

                let payload: [String: Any] = [
                    "prompt": prompt,
                    "max_tokens": 2048
                ]
                let payloadData = try JSONSerialization.data(withJSONObject: payload)
                try stdin.fileHandleForWriting.write(contentsOf: payloadData)
                stdin.fileHandleForWriting.closeFile()
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.localModelUnavailable("Failed to start local model process: \(error.localizedDescription)")))
                }
            }
        }

        return cancellable
    }

    private static let localPythonScript = #"""
import json
import sys

def fail(message, code=1):
    print(message, file=sys.stderr)
    sys.exit(code)

if len(sys.argv) < 3:
    fail("Missing model path or temperature argument.")

model_path = sys.argv[1]
try:
    temperature = float(sys.argv[2])
except Exception as exc:
    fail(f"Invalid temperature: {exc}")

try:
    payload = json.load(sys.stdin)
except Exception as exc:
    fail(f"Failed to parse prompt payload: {exc}")

prompt = payload.get("prompt", "")
if not prompt:
    fail("Prompt is empty.")

max_tokens = int(payload.get("max_tokens", 2048))

try:
    from mlx_lm import load, generate
except Exception as exc:
    fail(f"mlx_lm import failed: {exc}")

try:
    model, tokenizer = load(model_path)
    output = generate(
        model,
        tokenizer,
        prompt=prompt,
        temp=temperature,
        max_tokens=max_tokens,
        verbose=False,
    )
except Exception as exc:
    fail(f"Local generation failed: {exc}")

sys.stdout.write((output or "").strip())
"""#

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

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let stderr = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", "-c", preloadPythonScript, trimmedPath]
            process.standardError = stderr

            do {
                try process.run()
                process.waitUntilExit()

                let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                let errorText = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if process.terminationStatus == 0 {
                    completion(.success(()))
                } else {
                    let fallback = "Failed to load local model '\(modelName)'."
                    completion(.failure(.localModelUnavailable(errorText?.isEmpty == false ? errorText! : fallback)))
                }
            } catch {
                completion(.failure(.localModelUnavailable("Failed to start load process: \(error.localizedDescription)")))
            }
        }
    }

    static func unloadFromMemory(completion: @escaping (Result<Void, LLMError>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", "-c", unloadPythonScript]
            process.standardOutput = stdout
            process.standardError = stderr

            do {
                try process.run()
                process.waitUntilExit()

                let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                let errorText = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if process.terminationStatus == 0 {
                    completion(.success(()))
                } else {
                    let fallback = "Failed to unload local model from memory."
                    completion(.failure(.localModelUnavailable(errorText?.isEmpty == false ? errorText! : fallback)))
                }
            } catch {
                completion(.failure(.localModelUnavailable("Failed to start unload process: \(error.localizedDescription)")))
            }
        }
    }

    private static let unloadPythonScript = #"""
import gc

try:
    import mlx.core as mx
    if hasattr(mx, "metal") and hasattr(mx.metal, "clear_cache"):
        mx.metal.clear_cache()
    if hasattr(mx, "clear_cache"):
        mx.clear_cache()
except Exception:
    # Best effort cleanup.
    pass

gc.collect()
"""#

    private static let preloadPythonScript = #"""
import sys

if len(sys.argv) < 2:
    print("Missing model path.", file=sys.stderr)
    sys.exit(1)

model_path = sys.argv[1]

try:
    from mlx_lm import load
except Exception as exc:
    print(f"mlx_lm import failed: {exc}", file=sys.stderr)
    sys.exit(1)

try:
    model, tokenizer = load(model_path)
except Exception as exc:
    print(f"Local model load failed: {exc}", file=sys.stderr)
    sys.exit(1)
"""#
}

final class ProcessCancellable: Cancellable {
    private var process: Process?
    private(set) var isCancelled = false

    func setProcess(_ process: Process) {
        self.process = process
        if isCancelled, process.isRunning {
            process.terminate()
        }
    }

    func cancel() {
        isCancelled = true
        if process?.isRunning == true {
            process?.terminate()
        }
    }
}
