import Foundation

enum LLMError: Error, LocalizedError {
    case invalidAPIKey
    case invalidEndpoint
    case networkError(Error)
    case invalidResponse
    case rateLimited
    case serverError(Int, String?)
    case cancelled
    case streamingError(String)
    case localModelUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid or missing API key. Please check your settings."
        case .invalidEndpoint:
            return "Invalid endpoint URL."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from the API."
        case .rateLimited:
            return "Rate limited. Please try again later."
        case .serverError(let code, let message):
            if let message {
                return "Server error (\(code)): \(message)"
            }
            return "Server error: \(code)"
        case .cancelled:
            return "Request was cancelled."
        case .streamingError(let message):
            return "Streaming error: \(message)"
        case .localModelUnavailable(let message):
            return "Local model unavailable: \(message)"
        }
    }
}

protocol LLMProvider {
    var name: String { get }
    var providerType: LLMProviderType { get }

    func rewrite(
        text: String,
        options: RewriteOptions,
        streamHandler: @escaping (String) -> Void,
        completion: @escaping (Result<String, LLMError>) -> Void
    ) -> Cancellable
}

protocol Cancellable {
    func cancel()
}

final class URLSessionTaskCancellable: Cancellable {
    private var task: URLSessionTask?
    private(set) var isCancelled = false

    init(task: URLSessionTask? = nil) {
        self.task = task
    }

    func setTask(_ task: URLSessionTask) {
        self.task = task
        if isCancelled {
            task.cancel()
        }
    }

    func cancel() {
        isCancelled = true
        task?.cancel()
    }
}
