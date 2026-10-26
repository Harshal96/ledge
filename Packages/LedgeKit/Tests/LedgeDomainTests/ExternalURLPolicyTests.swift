import Testing
@testable import LedgeDomain

@Test("External URL policy rejects malformed inputs")
func externalURLPolicyRejectsMalformedInputs() {
    let policy = ExternalURLPolicy(maximumUTF8Bytes: 32)

    #expect(policy.validate("https://example.com/%zz").isFailure)
    #expect(policy.validate("https://example..com").isFailure)
    #expect(policy.validate("https://example.com/\n").isFailure)
    #expect(policy.validate("https://example.com/this-is-too-long").isFailure)
}
