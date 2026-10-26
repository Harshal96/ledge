import Carbon.HIToolbox

public enum HotKeyRegistrationResult: Sendable, Equatable { case registered, conflict, unsupported }

public struct HotKeyChord: Sendable, Equatable, Hashable {
    public let keyCode: UInt32
    public let modifiers: UInt32
    public init(keyCode: UInt32, modifiers: UInt32) { self.keyCode = keyCode; self.modifiers = modifiers }
}

/// Maps the two registered Carbon IDs back to their configured chords. It has no access to other key events.
public struct HotKeyEventRouter: Sendable, Equatable {
    private let chords: [HotKeyChord]
    public init(chords: [HotKeyChord]) { self.chords = chords }
    public func chord(forRegistrationID id: UInt32) -> HotKeyChord? {
        guard id > 0, Int(id) <= chords.count else { return nil }
        return chords[Int(id - 1)]
    }

    @MainActor
    public func deliver(registrationID: UInt32, to sink: some HotKeyEventSink) {
        guard let chord = chord(forRegistrationID: registrationID) else { return }
        sink.deliver(chord)
    }
}

@MainActor
public protocol HotKeyEventSink: AnyObject {
    func deliver(_ chord: HotKeyChord)
}

@MainActor
public protocol HotKeyRegistering: AnyObject {
    func register(_ chords: [HotKeyChord], handler: @escaping @MainActor (HotKeyChord) -> Void) -> HotKeyRegistrationResult
    func unregisterAll()
}

@MainActor
private final class ClosureHotKeyEventSink: HotKeyEventSink {
    private let handler: @MainActor (HotKeyChord) -> Void
    init(handler: @escaping @MainActor (HotKeyChord) -> Void) { self.handler = handler }
    func deliver(_ chord: HotKeyChord) { handler(chord) }
}

@MainActor
public final class CarbonHotKeyRegistrar: HotKeyRegistering {
    private var references: [EventHotKeyRef] = []
    private var router = HotKeyEventRouter(chords: [])
    private var sink: (any HotKeyEventSink)?
    private var eventHandler: EventHandlerRef?

    public init() {}

    public func register(_ chords: [HotKeyChord], handler: @escaping @MainActor (HotKeyChord) -> Void) -> HotKeyRegistrationResult {
        register(chords, sink: ClosureHotKeyEventSink(handler: handler))
    }

    /// Injection point for app composition and tests. The same Carbon callback routes only the registered IDs to this sink.
    public func register(_ chords: [HotKeyChord], sink: some HotKeyEventSink) -> HotKeyRegistrationResult {
        unregisterAll()
        guard chords.count == 2 else { return .unsupported }
        router = HotKeyEventRouter(chords: chords)
        self.sink = sink
        guard installHandler() else { self.sink = nil; return .unsupported }
        for (index, chord) in chords.enumerated() {
            var reference: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x4C454447), id: UInt32(index + 1))
            let result = RegisterEventHotKey(chord.keyCode, chord.modifiers, id, GetApplicationEventTarget(), 0, &reference)
            guard result == noErr, let reference else {
                unregisterAll()
                return result == eventHotKeyExistsErr ? .conflict : .unsupported
            }
            references.append(reference)
        }
        return .registered
    }

    public func unregisterAll() {
        for reference in references { UnregisterEventHotKey(reference) }
        references.removeAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
        sink = nil
        router = HotKeyEventRouter(chords: [])
    }

    private func installHandler() -> Bool {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                let registrar = Unmanaged<CarbonHotKeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
                return MainActor.assumeIsolated {
                    registrar.route(event)
                    return noErr
                }
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        return status == noErr
    }

    private func route(_ event: EventRef) {
        var identifier = EventHotKeyID()
        let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
        guard status == noErr, let sink else { return }
        router.deliver(registrationID: identifier.id, to: sink)
    }

}
