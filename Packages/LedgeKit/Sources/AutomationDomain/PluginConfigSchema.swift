import Foundation

/// Deliberately bounded JSON Schema subset used by the native form/CLI. Unsupported
/// schema constructs fail explicitly instead of silently accepting invalid config.
public enum PluginConfigSchema {
    public static func validate(_ value: JSONValue, schema: JSONValue, path: String = "config", depth: Int = 0) throws {
        guard depth < 32, let object = schema.object else { throw PlatformError.invalid("Invalid schema at \(path)") }
        let allowed: Set<String> = ["$schema", "$id", "title", "description", "default", "type", "enum", "properties", "required", "additionalProperties", "items", "minItems", "maxItems", "minimum", "maximum", "minLength", "maxLength", "pattern"]
        guard Set(object.keys).isSubset(of: allowed) else { throw PlatformError.invalid("Unsupported schema keyword at \(path); use the supported schema subset") }
        let types = schema["type"].string.map { [$0] } ?? schema["type"].array?.compactMap(\.string) ?? []
        let actual: String
        switch value { case .object: actual = "object"; case .array: actual = "array"; case .string: actual = "string"; case .number: actual = "number"; case .bool: actual = "boolean"; case .null: actual = "null" }
        if !types.isEmpty && !types.contains(actual) {
            guard actual == "number", types.contains("integer"), value.number?.rounded() == value.number else { throw PlatformError.invalid("\(path) must be \(types.joined(separator: " or "))") }
        }
        if let options = schema["enum"].array, !options.contains(value) { throw PlatformError.invalid("\(path) is not an allowed value") }
        switch value {
        case let .object(fields):
            let properties = schema["properties"].object ?? [:]
            for key in schema["required"].array?.compactMap(\.string) ?? [] where fields[key] == nil { throw PlatformError.invalid("\(path).\(key) is required") }
            if schema["additionalProperties"].bool == false, !Set(fields.keys).isSubset(of: Set(properties.keys)) { throw PlatformError.invalid("Unexpected field in \(path)") }
            for (key, child) in fields { if let rule = properties[key] { try validate(child, schema: rule, path: path + "." + key, depth: depth + 1) } }
        case let .array(items):
            if let minimum = schema["minItems"].number, Double(items.count) < minimum { throw PlatformError.invalid("Too few items at \(path)") }
            if let maximum = schema["maxItems"].number, Double(items.count) > maximum { throw PlatformError.invalid("Too many items at \(path)") }
            if schema["items"] != .null { for item in items { try validate(item, schema: schema["items"], path: path + "[]", depth: depth + 1) } }
        case let .number(number):
            if let minimum = schema["minimum"].number, number < minimum { throw PlatformError.invalid("Value below minimum at \(path)") }
            if let maximum = schema["maximum"].number, number > maximum { throw PlatformError.invalid("Value above maximum at \(path)") }
        case let .string(text):
            if let minimum = schema["minLength"].number, Double(text.count) < minimum { throw PlatformError.invalid("Text too short at \(path)") }
            if let maximum = schema["maxLength"].number, Double(text.count) > maximum { throw PlatformError.invalid("Text too long at \(path)") }
            if let pattern = schema["pattern"].string {
                let expression = try NSRegularExpression(pattern: pattern)
                guard expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil else { throw PlatformError.invalid("Invalid format at \(path)") }
            }
        default: break
        }
    }
}
