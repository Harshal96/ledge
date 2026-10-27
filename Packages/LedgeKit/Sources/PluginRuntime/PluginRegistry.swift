import Foundation
import CryptoKit
import AutomationDomain

public struct InstalledPlugin: Codable, Sendable {
    public let manifest: PluginManifest
    public let directory: URL
    public let executable: String
    public let arguments: [String]
    public let digest: String
    public let integrityVersion: Int?
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
            let plugin = InstalledPlugin(manifest: manifest, directory: destination, executable: executable, arguments: arguments, digest: try fingerprint(destination), integrityVersion: 2)
            try WireCoding.encoder().encode(plugin).write(to: root.appendingPathComponent("\(manifest.id)@\(manifest.version).json"), options: .atomic)
            return plugin
        } catch { try? FileManager.default.removeItem(at: destination); throw error }
    }
    public func resolve(_ reference: String) throws -> InstalledPlugin {
        guard reference.split(separator: "@").count == 2, !reference.contains("/"), !reference.contains("\\") else { throw PlatformError.invalid("Use a plugin ID@version") }
        let plugin = try WireCoding.decoder().decode(InstalledPlugin.self, from: Data(contentsOf: root.appendingPathComponent(reference + ".json")))
        guard plugin.integrityVersion == 2 else { throw PlatformError.denied("Legacy package integrity needs renewed review. Install a reviewed new version; existing state is retained.") }
        guard try fingerprint(plugin.directory) == plugin.digest else { throw PlatformError.denied("Plugin contents changed after trust was granted; install a new version") }
        return plugin
    }
    public func list() throws -> [InstalledPlugin] {
        try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }.map { try WireCoding.decoder().decode(InstalledPlugin.self, from: Data(contentsOf: $0)) }
    }
    public func installApp(directory: URL, trustLocalCode: Bool, interpreter: String? = nil) throws -> PluginInstallation {
        guard trustLocalCode else { throw PlatformError.denied("Review this app's code: local programs run with your user permissions") }
        let source = directory.standardizedFileURL.resolvingSymlinksInPath()
        let before = try fingerprint(source)
        let manifest = try PluginManifestV2.validated(Data(contentsOf: source.appendingPathComponent("ledge-plugin.json")))
        let packages = root.appendingPathComponent("Apps", isDirectory: true)
        try FileManager.default.createDirectory(at: packages, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let destination = packages.appendingPathComponent("\(manifest.id)@\(manifest.version)-\(before.prefix(12))", isDirectory: true)
        if !FileManager.default.fileExists(atPath: destination.path) {
            let staging = packages.appendingPathComponent(".stage-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: staging) }
            try FileManager.default.copyItem(at: source, to: staging)
            guard try fingerprint(staging) == before else { throw PlatformError.denied("Package changed while being copied") }
            try FileManager.default.moveItem(at: staging, to: destination)
        }
        let entry = destination.appendingPathComponent(manifest.runtime.entry)
        guard FileManager.default.fileExists(atPath: entry.path) else { throw PlatformError.invalid("App entry file is missing") }
        let executable = try Self.resolveExecutable(interpreter ?? manifest.runtime.interpreter ?? entry.path)
        let arguments = interpreter != nil || manifest.runtime.interpreter != nil ? [entry.path] : []
        return .init(manifest: manifest, directory: destination, executable: executable, arguments: arguments, digest: before, source: source.path, grants: manifest.capabilities)
    }
    public func verifyApp(_ installation: PluginInstallation) throws {
        guard try fingerprint(installation.directory) == installation.digest else { throw PlatformError.denied("App changed after installation; review and reinstall it") }
    }
    private static func resolveExecutable(_ requested: String) throws -> String {
        let paths = requested.hasPrefix("/") ? [requested] : ["/opt/homebrew/bin/", "/usr/local/bin/", "/usr/bin/", "/bin/"].map { $0 + requested }
        guard let path = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw PlatformError.unavailable("Interpreter not found: \(requested). Supply an absolute interpreter path.") }; return path
    }
    private func fingerprint(_ requestedDirectory: URL) throws -> String {
        let directory = requestedDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey]
        guard let items = FileManager.default.enumerator(atPath: directory.path) else { throw PlatformError.invalid("Cannot enumerate plugin") }
        var files: [String] = []; var size = 0
        for case let relative as String in items {
            let item = directory.appendingPathComponent(relative)
            let properties = try item.resourceValues(forKeys: keys)
            guard properties.isSymbolicLink != true else { throw PlatformError.invalid("Plugin package cannot contain symbolic links") }
            guard properties.isRegularFile == true || properties.isDirectory == true else { throw PlatformError.invalid("Plugin package cannot contain special files") }
            if properties.isRegularFile == true { size += properties.fileSize ?? 0; files.append(relative) }
            guard files.count <= 1000, size <= 16 * 1024 * 1024 else { throw PlatformError.invalid("Plugin package exceeds 1000 files/16 MiB; exclude dependencies and build artifacts") }
        }
        var hash = SHA256()
        hash.update(data: Data("Ledge package integrity v2\0".utf8))
        for relative in files.sorted() {
            let name = Data(relative.utf8)
            let contents = try Data(contentsOf: directory.appendingPathComponent(relative))
            for field in [name, contents] {
                var length = UInt64(field.count).bigEndian
                withUnsafeBytes(of: &length) { hash.update(data: Data($0)) }
                hash.update(data: field)
            }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
