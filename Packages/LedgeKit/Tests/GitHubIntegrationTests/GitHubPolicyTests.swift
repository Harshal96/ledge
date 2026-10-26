import Testing
import AutomationDomain
@testable import GitHubIntegration

@Test func brokerCannotRequestAnotherRepositoryOrMutation() throws {
    #expect(throws: (any Error).self) { try GitHubRequestPolicy.path(operation: "github.issues.listUpdated", repository: "other/private", allowedRepositories: ["owner/repo"], parameters: .empty) }
    #expect(throws: (any Error).self) { try GitHubRequestPolicy.path(operation: "github.issues.create", repository: "owner/repo", allowedRepositories: ["owner/repo"], parameters: .empty) }
    let path = try GitHubRequestPolicy.path(operation: "github.issues.listUpdated", repository: "owner/repo", allowedRepositories: ["owner/repo"], parameters: .empty)
    #expect(path.hasPrefix("/repos/owner/repo/issues?"))
}

@Test func numericParametersFailClosedWithoutIntegerTrapsOrPageClamping() throws {
    for parameter in ["page", "number"] {
        #expect(throws: (any Error).self) {
            try GitHubRequestPolicy.path(operation: "github.issues.getEvidence", repository: "owner/repo", allowedRepositories: ["owner/repo"], parameters: .object([parameter: .number(1e100)]))
        }
    }
    let path = try GitHubRequestPolicy.path(operation: "github.issues.listUpdated", repository: "owner/repo", allowedRepositories: ["owner/repo"], parameters: .object(["page": .number(101)]))
    #expect(path.contains("page=101"))
}
