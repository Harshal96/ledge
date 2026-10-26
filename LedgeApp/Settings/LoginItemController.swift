import Foundation
import ServiceManagement
import SwiftUI

enum LoginItemState: String, Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

enum LoginItemError: LocalizedError, Equatable {
    case requiresApproval
    case unavailable
    case registrationFailed

    var errorDescription: String? {
        switch self {
        case .requiresApproval: "macOS requires approval in System Settings."
        case .unavailable: "Launch at Login is unavailable for this app build."
        case .registrationFailed: "Launch at Login could not be updated."
        }
    }
}

/// User-controlled launch-at-login integration. No helper executable is
/// installed; registration happens only after the toggle is changed.
@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var state: LoginItemState
    @Published private(set) var lastError: LoginItemError?

    private let service: SMAppService
    private let registerAction: () throws -> Void
    private let unregisterAction: () throws -> Void
    private let openSettingsAction: () -> Void

    init(
        service: SMAppService = .mainApp,
        register: (() throws -> Void)? = nil,
        unregister: (() throws -> Void)? = nil,
        openSettings: (() -> Void)? = nil
    ) {
        self.service = service
        self.registerAction = register ?? { try service.register() }
        self.unregisterAction = unregister ?? { try service.unregister() }
        self.openSettingsAction = openSettings ?? { SMAppService.openSystemSettingsLoginItems() }
        self.state = Self.map(service.status)
    }

    var isEnabled: Bool { state == .enabled }

    func refresh() {
        state = Self.map(service.status)
    }

    func setEnabled(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try registerAction()
            } else {
                try unregisterAction()
            }
            refresh()
            if enabled && state == .requiresApproval {
                lastError = .requiresApproval
                openSettingsAction()
            }
        } catch {
            state = enabled ? .requiresApproval : .unavailable
            lastError = service.status == .requiresApproval ? .requiresApproval : .registrationFailed
            if lastError == .requiresApproval { openSettingsAction() }
        }
    }

    func openSystemSettings() {
        openSettingsAction()
    }

    private static func map(_ status: SMAppService.Status) -> LoginItemState {
        switch status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered: .disabled
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }
}
