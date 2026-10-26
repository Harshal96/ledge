import Foundation
import Testing
@testable import AutomationDomain

@Test func pluginConfigurationSchemaEnforcesRequiredTypesAndRepositoryShape() throws {
    let schema = try StrictJSON.decode(Data(#"{"type":"object","required":["repositories"],"additionalProperties":false,"properties":{"repositories":{"type":"array","minItems":1,"items":{"type":"string","pattern":"^[a-z]+/[a-z]+$"}}}}"#.utf8))
    try PluginConfigSchema.validate(.object(["repositories": .array([.string("owner/repo")])]), schema: schema)
    #expect(throws: (any Error).self) { try PluginConfigSchema.validate(.empty, schema: schema) }
    #expect(throws: (any Error).self) { try PluginConfigSchema.validate(.object(["repositories": .array([.string("../file")])]), schema: schema) }
}
