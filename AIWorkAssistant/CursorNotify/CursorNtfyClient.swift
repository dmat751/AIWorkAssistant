import Foundation

enum CursorNotifyConstants {
    static let placeholderTopic = "your-topic-name"
}

struct CursorNtfyConfiguration: Equatable {
    let topic: String?
    let isApproveEnabled: Bool

    init(envFileURL: URL) {
        guard let contents = try? String(contentsOf: envFileURL, encoding: .utf8) else {
            topic = nil
            isApproveEnabled = true
            return
        }
        let env = CursorNotifyEnvFile(contents: contents)
        topic = env.topic
        isApproveEnabled = env.isApproveEnabled
    }

    init(topic: String?, isApproveEnabled: Bool) {
        self.topic = topic
        self.isApproveEnabled = isApproveEnabled
    }

    var canSendApprovalPush: Bool {
        guard isApproveEnabled,
              let topic,
              !topic.isEmpty,
              topic != CursorNotifyConstants.placeholderTopic else {
            return false
        }
        return true
    }
}

protocol CursorNtfySending {
    func sendApprovalPush(title: String, body: String) async throws
}

enum CursorNtfyClientError: LocalizedError {
    case approvalDisabled
    case missingTopic
    case invalidResponse(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .approvalDisabled:
            return "Approval push notifications are disabled."
        case .missingTopic:
            return "Set an ntfy topic first."
        case .invalidResponse(let statusCode):
            return "Push failed with status \(statusCode)."
        }
    }
}

struct CursorNtfyClient: CursorNtfySending {
    private let configurationProvider: () -> CursorNtfyConfiguration
    private let session: URLSession
    private let baseURL: String

    init(
        envFileURL: URL,
        session: URLSession = .shared,
        baseURL: String = "https://ntfy.sh"
    ) {
        self.configurationProvider = { CursorNtfyConfiguration(envFileURL: envFileURL) }
        self.session = session
        self.baseURL = baseURL
    }

    init(
        configurationProvider: @escaping () -> CursorNtfyConfiguration,
        session: URLSession = .shared,
        baseURL: String = "https://ntfy.sh"
    ) {
        self.configurationProvider = configurationProvider
        self.session = session
        self.baseURL = baseURL
    }

    func sendApprovalPush(title: String, body: String) async throws {
        let configuration = configurationProvider()
        guard configuration.isApproveEnabled else {
            throw CursorNtfyClientError.approvalDisabled
        }
        guard let topic = configuration.topic,
              !topic.isEmpty,
              topic != CursorNotifySettings.placeholderTopic,
              let url = URL(string: "\(baseURL)/\(topic)") else {
            throw CursorNtfyClientError.missingTopic
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(title, forHTTPHeaderField: "Title")
        request.setValue("cursor,approval", forHTTPHeaderField: "Tags")
        request.setValue("high", forHTTPHeaderField: "Priority")
        request.httpBody = body.data(using: .utf8)

        let (_, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
            throw CursorNtfyClientError.invalidResponse(statusCode: http.statusCode)
        }
    }
}
