import AppKit
import CoreGraphics
import EventKit
import Foundation
import LedgeDomain
import ShellFeature
import SwiftUI

enum PermissionKind: String, CaseIterable, Identifiable {
    case calendar
    case screenCapture
    case pasteboard

    var id: String { rawValue }

    var feature: FeatureID {
        switch self {
        case .calendar: .meetings
        case .screenCapture: .screenshot
        case .pasteboard: .clipboard
        }
    }

    var title: String {
        switch self {
        case .calendar: "Calendar"
        case .screenCapture: "Screen Recording"
        case .pasteboard: "Clipboard"
        }
    }
}

/// Owns permission presentation without prompting during app startup.
/// The request closures are injected so tests can cover denial and recovery
/// without invoking macOS consent sheets.
@MainActor
final class PermissionCenter: ObservableObject {
    @Published private(set) var capabilities: AppCapabilityState
    @Published private(set) var onboardingComplete: Bool
    @Published private(set) var lastError: String?

    private let defaults: UserDefaults
    private let requestCalendar: () async -> CapabilityPermission
    private let requestScreenCapture: () async -> CapabilityPermission
    private let requestPasteboard: () async -> CapabilityPermission
    private let openSettingsAction: (PermissionKind) -> Void

    init(
        capabilities: AppCapabilityState = AppCapabilityState(),
        defaults: UserDefaults = .standard,
        requestCalendar: (() async -> CapabilityPermission)? = nil,
        requestScreenCapture: (() async -> CapabilityPermission)? = nil,
        requestPasteboard: (() async -> CapabilityPermission)? = nil,
        openSettings: ((PermissionKind) -> Void)? = nil
    ) {
        self.capabilities = capabilities
        self.defaults = defaults
        self.onboardingComplete = defaults.object(forKey: Self.onboardingKey) as? Bool ?? false
        self.requestCalendar = requestCalendar ?? Self.requestCalendarAccess
        self.requestScreenCapture = requestScreenCapture ?? Self.requestScreenCaptureAccess
        self.requestPasteboard = requestPasteboard ?? { .allowed }
        self.openSettingsAction = openSettings ?? Self.openSystemSettings
    }

    private static let onboardingKey = "ledge.onboarding.completed"

    func completeOnboarding() {
        defaults.set(true, forKey: Self.onboardingKey)
        onboardingComplete = true
    }

    func resetOnboarding() {
        defaults.removeObject(forKey: Self.onboardingKey)
        onboardingComplete = false
    }

    func request(_ kind: PermissionKind) async -> CapabilityPermission {
        let result: CapabilityPermission
        switch kind {
        case .calendar: result = await requestCalendar()
        case .screenCapture: result = await requestScreenCapture()
        case .pasteboard: result = await requestPasteboard()
        }
        capabilities = updated(capabilities, kind: kind, value: result)
        return result
    }

    func openSystemSettings(for kind: PermissionKind) {
        openSettingsAction(kind)
    }

    func permission(for kind: PermissionKind) -> CapabilityPermission {
        switch kind {
        case .calendar: capabilities.calendar
        case .screenCapture: capabilities.screenCapture
        case .pasteboard: capabilities.pasteboard
        }
    }

    private func updated(_ state: AppCapabilityState, kind: PermissionKind, value: CapabilityPermission) -> AppCapabilityState {
        switch kind {
        case .calendar:
            AppCapabilityState(calendar: value, screenCapture: state.screenCapture, pasteboard: state.pasteboard, audio: state.audio)
        case .screenCapture:
            AppCapabilityState(calendar: state.calendar, screenCapture: value, pasteboard: state.pasteboard, audio: state.audio)
        case .pasteboard:
            AppCapabilityState(calendar: state.calendar, screenCapture: state.screenCapture, pasteboard: value, audio: state.audio)
        }
    }

    private static func requestCalendarAccess() async -> CapabilityPermission {
        let store = EKEventStore()
        return (try? await store.requestFullAccessToEvents()) == true ? .authorized : .denied
    }

    private static func requestScreenCaptureAccess() async -> CapabilityPermission {
        CGRequestScreenCaptureAccess() ? .authorized : .denied
    }

    private static func openSystemSettings(_ kind: PermissionKind) {
        let pane: String
        switch kind {
        case .calendar: pane = "Privacy_Calendars"
        case .screenCapture: pane = "Privacy_ScreenCapture"
        case .pasteboard: pane = "Privacy"
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}
