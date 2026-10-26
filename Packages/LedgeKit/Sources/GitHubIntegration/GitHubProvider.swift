import Foundation
import AutomationDomain
import IntegrationKit

public enum GitHubRequestPolicy {
    public static func path(operation: String, repository: String, allowedRepositories: [String], parameters: JSONValue) throws -> String {
        guard repository.range(of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil, allowedRepositories.contains(repository) else { throw PlatformError.denied("Repository is not granted to this automation") }
        let rawPage = parameters["page"].number ?? 1
        guard rawPage.isFinite, rawPage >= 1, rawPage <= 1_000_000, rawPage.rounded() == rawPage else { throw PlatformError.invalid("Expected a bounded positive page number") }
        let page = Int(rawPage)
        switch operation {
        case "github.issues.listUpdated":
            var components = URLComponents(); components.path = "/repos/\(repository)/issues"
            components.queryItems = [.init(name: "state", value: "all"), .init(name: "sort", value: "created"), .init(name: "direction", value: "asc"), .init(name: "per_page", value: "100"), .init(name: "page", value: String(page))]
            if let since = parameters["since"].string { components.queryItems?.append(.init(name: "since", value: since)) }
            return components.string!
        case "github.issues.getEvidence":
            guard let number = parameters["number"].number, number.isFinite, number > 0, number <= 2_147_483_647, number.rounded() == number else { throw PlatformError.invalid("Expected a bounded issue number") }
            return "/repos/\(repository)/issues/\(Int(number))"
        case "github.pullRequests.findOverlap": return "/repos/\(repository)/pulls?state=open&per_page=100&page=\(page)"
        default: throw PlatformError.denied("Unknown or non-read GitHub operation")
        }
    }
}

public actor GitHubProvider {
    private let credentials: CredentialStore
    private let session: URLSession
    private var tail: Task<Void, Never>?
    private var blockedUntil = Date.distantPast
    public init(credentials: CredentialStore) {
        self.credentials = credentials
        let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 30; config.httpCookieStorage = nil
        session = URLSession(configuration: config, delegate: NoGitHubRedirects(), delegateQueue: nil)
    }
    public func call(operation: String, parameters: JSONValue, account: String, repositories: [String]) async throws -> JSONValue {
        let repository = parameters["repository"].string ?? ""
        let path = try GitHubRequestPolicy.path(operation: operation, repository: repository, allowedRepositories: repositories, parameters: parameters)
        guard let data = try await credentials.read("github/\(account)"), let token = String(data: data, encoding: .utf8) else { throw PlatformError.denied("Connect GitHub account '\(account)' first") }
        let previous = tail
        let task = Task { [self] in
            await previous?.value
            guard Date() >= blockedUntil else { throw PlatformError.unavailable("GitHub rate limit: retry after \(blockedUntil.formatted())") }
            if operation == "github.issues.getEvidence" { return try await evidence(path: path, token: token) }
            return try await request(path: path, token: token)
        }
        tail = Task { _ = try? await task.value }
        return try await task.value
    }
    public func verify(token: String) async throws -> JSONValue { try await request(path: "/user", token: token)["data"] }

    private func request(path: String, token: String, body: JSONValue? = nil) async throws -> JSONValue {
        guard let url = URL(string: "https://api.github.com\(path)"), url.host == "api.github.com" else { throw PlatformError.denied("Invalid GitHub API destination") }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Ledge/1", forHTTPHeaderField: "User-Agent")
        if let body { request.httpMethod = "POST"; request.httpBody = try WireCoding.encoder().encode(body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (stream, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw PlatformError.unavailable("Invalid GitHub response") }
        if response.statusCode == 401 { throw PlatformError.denied("GitHub connection expired or revoked; reconnect") }
        if response.statusCode == 403 || response.statusCode == 429 {
            blockedUntil = Date().addingTimeInterval(Double(response.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60)
            if response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0", let reset = Double(response.value(forHTTPHeaderField: "X-RateLimit-Reset") ?? "") { blockedUntil = max(blockedUntil, Date(timeIntervalSince1970: reset)) }
            throw PlatformError.unavailable("GitHub access/rate limit; check connection permissions and retry later")
        }
        guard response.statusCode == 200 else { throw PlatformError.unavailable("GitHub returned HTTP \(response.statusCode); scan coverage is incomplete") }
        var bytes = Data()
        for try await byte in stream { bytes.append(byte); guard bytes.count <= 2_097_152 else { throw PlatformError.invalid("GitHub response too large") } }
        let data = try JSONDecoder().decode(JSONValue.self, from: bytes)
        return .object(["data": data, "hasNext": .bool((response.value(forHTTPHeaderField: "Link") ?? "").contains("rel=\"next\"")), "checkedAt": .string(ISO8601DateFormatter().string(from: Date()))])
    }
    private func evidence(path: String, token: String) async throws -> JSONValue {
        let issue = try await request(path: path, token: token)
        let comments = try await request(path: path + "/comments?per_page=100", token: token)
        let timeline = try await request(path: path + "/timeline?per_page=100", token: token)
        let pieces = path.split(separator: "/")
        let query = "query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){issue(number:$number){assignedActors(first:100){totalCount pageInfo{hasNextPage}} closedByPullRequestsReferences(first:100,includeClosedPrs:false,excludeUserLinked:false){nodes{number state url} pageInfo{hasNextPage}}}}}"
        let graph = try? await request(path: "/graphql", token: token, body: .object(["query": .string(query), "variables": .object(["owner": .string(String(pieces[1])), "name": .string(String(pieces[2])), "number": .number(Double(pieces[4]) ?? 0)])]))
        let graphIssue = graph?["data"]["data"]["repository"]["issue"] ?? .null
        let graphComplete = graph?["data"]["errors"] == .null && graphIssue["assignedActors"]["totalCount"].number != nil && graphIssue["closedByPullRequestsReferences"]["pageInfo"]["hasNextPage"].bool == false
        return .object(["issue": issue["data"], "comments": comments["data"], "timeline": timeline["data"], "assignedActors": graphIssue["assignedActors"], "closingPullRequests": graphIssue["closedByPullRequestsReferences"], "complete": .bool(comments["hasNext"].bool == false && timeline["hasNext"].bool == false && graphComplete), "checkedAt": issue["checkedAt"]])
    }
}

private final class NoGitHubRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
