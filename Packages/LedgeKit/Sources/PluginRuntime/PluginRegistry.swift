import Foundation
import CryptoKit
import AutomationDomain

public struct InstalledPlugin: Codable, Sendable {
    public let manifest: PluginManifest
    public let directory: URL
    public let executable: String
    public let arguments: [String]
    public let digest: String
}

public actor PluginRegistry {
    private let root: URL
    public init(root: URL) throws { self.root = root; try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
    public func install(directory: URL, trustLocalCode: Bool, interpreter: String? = nil) throws -> InstalledPlugin {
        guard trustLocalCode else { throw PlatformError.denied("Local plugins run with your user permissions. Review the code and install with explicit trust.") }
        let source = directory.standardizedFileURL.resolvingSymlinksInPath()
        let manifest = try ManifestValidator.validate(data: Data(contentsOf: source.appendingPathComponent("ledge-plugin.json")))
        _ = try fingerprint(source)
        let destination = root.appendingPathComponent("\(manifest.id)@\(manifest.version)", isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw PlatformError.invalid("Version already installed; change the version to install an update") }
        try FileManager.default.copyItem(at: source, to: destination)
        do {
            let entry = destination.appendingPathComponent(manifest.runtime.entry)
            let executable: String
            let arguments: [String]
            if let requested = interpreter ?? manifest.runtime.interpreter {
                executable = try Self.resolveExecutable(requested); arguments = [entry.path]
            } else { executable = try Self.resolveExecutable(entry.path); arguments = [] }
            let plugin = InstalledPlugin(manifest: manifest, directory: destination, executable: executable, arguments: arguments, digest: try fingerprint(destination))
            try WireCoding.encoder().encode(plugin).write(to: root.appendingPathComponent("\(manifest.id)@\(manifest.version).json"), options: .atomic)
            return plugin
        } catch { try? FileManager.default.removeItem(at: destination); throw error }
    }
    public func resolve(_ reference: String) throws -> InstalledPlugin {
        guard reference.split(separator: "@").count == 2, !reference.contains("/"), !reference.contains("\\") else { throw PlatformError.invalid("Use a plugin ID@version") }
        let plugin = try WireCoding.decoder().decode(InstalledPlugin.self, from: Data(contentsOf: root.appendingPathComponent(reference + ".json")))
        guard try fingerprint(plugin.directory) == plugin.digest else { throw PlatformError.denied("Plugin contents changed after trust was granted; install a new version") }
        return plugin
    }
    public func list() throws -> [InstalledPlugin] {
        try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }.map { try WireCoding.decoder().decode(InstalledPlugin.self, from: Data(contentsOf: $0)) }
    }
    private static func resolveExecutable(_ requested: String) throws -> String {
        let paths = requested.hasPrefix("/") ? [requested] : ["/opt/homebrew/bin/", "/usr/local/bin/", "/usr/bin/", "/bin/"].map { $0 + requested }
        guard let path = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw PlatformError.unavailable("Interpreter not found: \(requested). Supply an absolute interpreter path.") }; return path
    }
    private func fingerprint(_ directory: URL) throws -> String {
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]
        guard let items = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: Array(keys)) else { throw PlatformError.invalid("Cannot enumerate plugin") }
        var files: [URL] = []; var size = 0
        for case let item as URL in items {
            let properties = try item.resourceValues(forKeys: keys)
            guard properties.isSymbolicLink != true else { throw PlatformError.invalid("Plugin package cannot contain symbolic links") }
            if properties.isRegularFile == true { size += properties.fileSize ?? 0; files.append(item) }
            guard files.count <= 1000, size <= 16 * 1024 * 1024 else { throw PlatformError.invalid("Plugin package exceeds 1000 files/16 MiB; exclude dependencies and build artifacts") }
        }
        var hash = SHA256()
        for file in files.sorted(by: { $0.path < $1.path }) {
            let relative = String(file.path.dropFirst(directory.path.count)); hash.update(data: Data(relative.utf8)); hash.update(data: try Data(contentsOf: file))
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
