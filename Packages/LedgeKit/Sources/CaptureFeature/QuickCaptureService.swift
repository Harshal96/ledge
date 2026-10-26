import Foundation
import LedgeDomain
import ShellFeature

@MainActor
public final class QuickCaptureService {
    private let source: any SourceContextProviding
    private let sourcePolicy: CaptureSourcePolicy
    private let panel: any ShellPanelControlling
    private let repository: any ShelfRepository
    public private(set) var frozenSource: SourceContext?

    public init(source: any SourceContextProviding, sourcePolicy: CaptureSourcePolicy = .attachApplication, panel: any ShellPanelControlling, repository: any ShelfRepository) {
        self.source = source; self.sourcePolicy = sourcePolicy; self.panel = panel; self.repository = repository
    }

    public func beginCapture(at date: Date = .now, screenID: String? = nil) async throws {
        frozenSource = sourcePolicy == .attachApplication ? await source.snapshot(at: date) : nil
        panel.reveal(.quickCapture, reason: .userAction, screenID: screenID)
    }

    public func save(_ draft: CaptureDraft, now: Date = .now) async throws -> ShelfItem {
        let source = draft.source ?? (draft.allowsFrozenSourceAttachment ? frozenSource : nil)
        let frozenDraft = CaptureDraft(type: draft.type, text: draft.text, source: source, allowsFrozenSourceAttachment: draft.allowsFrozenSourceAttachment)
        let item = try await repository.insert(try frozenDraft.shelfItemDraft(now: now))
        panel.dismiss(reason: .actionCompleted)
        return item
    }

    public func cancel() { panel.dismiss(reason: .escape) }
}
