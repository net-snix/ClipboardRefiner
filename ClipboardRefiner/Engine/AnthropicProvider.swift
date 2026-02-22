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
        let cancellable = URLSessionTaskCancellable()

        guard !apiKey.isEmpty else {
            completion(.failure(.invalidAPIKey))
            return cancellable
        }

        var userContent: [[String: Any]] = [[
            "type": "text",
            "text": text
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
            "stream": false
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
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
}
