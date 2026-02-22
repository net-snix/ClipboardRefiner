import Foundation

final class AnthropicProvider: LLMProvider {
    let name = "Anthropic"
    let providerType = LLMProviderType.anthropic

    private let apiKey: String
    private let model: String
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let apiVersion = "2025-01-01"

    init(apiKey: String, model: String = "claude-sonnet-4-6") {
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
        var userContent: [[String: Any]] = [[
            "type": "text",
            "text": wrappedSourceText
        ]]

        userContent.append(contentsOf: options.imageAttachments.map { image in
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": image.mimeType,
                    "data": image.dataBase64
                ]
            ]
        })

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": options.fullSystemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": userContent
                ]
            ],
            "stream": options.streaming
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
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
            var streamStopReason: String?

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
                    if let stopReason = Self.extractStreamStopReason(from: json) {
                        streamStopReason = stopReason
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
                            if let streamStopReason {
                                switch streamStopReason {
                                case "refusal":
                                    completion(.failure(.serverError(400, "Anthropic returned refusal for this request.")))
                                case "model_context_window_exceeded":
                                    completion(.failure(.serverError(400, "Model context window exceeded. Shorten input or attachments.")))
                                default:
                                    completion(.failure(.invalidResponse))
                                }
                            } else if let streamErrorMessage {
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
                      let content = json["content"] as? [[String: Any]] else {
                    ProviderHTTP.deliverOnMain {
                        completion(.failure(.invalidResponse))
                    }
                    return
                }

                let text = content
                    .filter { ($0["type"] as? String) == "text" }
                    .compactMap { $0["text"] as? String }
                    .joined()

                if !text.isEmpty {
                    ProviderHTTP.deliverOnMain {
                        streamHandler(text)
                        completion(.success(text))
                    }
                    return
                }

                let stopReason = json["stop_reason"] as? String
                let mappedError: LLMError
                switch stopReason {
                case "refusal":
                    mappedError = .serverError(400, "Anthropic returned refusal for this request.")
                case "model_context_window_exceeded":
                    mappedError = .serverError(400, "Model context window exceeded. Shorten input or attachments.")
                default:
                    mappedError = .invalidResponse
                }

                ProviderHTTP.deliverOnMain {
                    completion(.failure(mappedError))
                }
            }
        }

        return cancellable
    }

    private static func extractStreamDelta(from json: [String: Any]) -> String? {
        guard let delta = json["delta"] as? [String: Any] else { return nil }

        if let text = delta["text"] as? String, !text.isEmpty {
            return text
        }

        if let textDelta = delta["delta"] as? String, !textDelta.isEmpty {
            return textDelta
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

    private static func extractStreamStopReason(from json: [String: Any]) -> String? {
        if let stopReason = json["stop_reason"] as? String, !stopReason.isEmpty {
            return stopReason
        }

        if let delta = json["delta"] as? [String: Any],
           let stopReason = delta["stop_reason"] as? String,
           !stopReason.isEmpty {
            return stopReason
        }

        return nil
    }

    private static func extractStreamSnapshot(from json: [String: Any]) -> String? {
        guard let content = json["content"] as? [[String: Any]] else {
            return nil
        }

        let text = content
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined()

        return text.isEmpty ? nil : text
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
