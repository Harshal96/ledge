import Foundation
import Observation
import AutomationDomain

@MainActor @Observable public final class PluginActivityStore {
    public private(set) var presentations: [String: PluginPresentation] = [:]
    private var accepted: [String: [TimeInterval]] = [:]
    private var global: [TimeInterval] = []
    public init() {}
    public func acceptingRevision(_ revision: Int, instanceID: String) -> Bool { revision > (presentations[instanceID]?.revision ?? 0) }
    @discardableResult public func accept(_ value: PluginPresentation, instanceID: String, now: TimeInterval, visible: Bool) throws -> Bool {
        try value.validate(instanceID: instanceID)
        guard acceptingRevision(value.revision, instanceID: instanceID) else { return false }
        let recent = (accepted[instanceID] ?? []).filter { now - $0 < 1 }
        global = global.filter { now - $0 < 1 }
        guard recent.count < (visible ? 5 : 1), global.count < (visible ? 10 : 1) else { return false }
        accepted[instanceID] = recent + [now]; global.append(now); presentations[instanceID] = value; return true
    }
    public func remove(instanceID: String) { presentations.removeValue(forKey: instanceID); accepted.removeValue(forKey: instanceID) }
}
