import Foundation
import Combine

/// A visible editor owns its draft. Consuming or cancelling its identity is irreversible.
final class CameraEditSession: ObservableObject {
    let id = UUID()
    let control: CameraControl
    @Published var draft: CameraSettings
    fileprivate var finished = false
    init(control: CameraControl, settings: CameraSettings) { self.control = control; draft = settings }
}

/// Main-thread ownership; a late disappearance/SET from an old editor cannot affect a newer one.
final class CameraEditorRegistry {
    struct Commit { let control: CameraControl; let draft: CameraSettings }
    private var active: CameraEditSession?
    func register(_ session: CameraEditSession) {
        guard !session.finished else { return }
        if active?.id != session.id { active?.finished = true }
        active = session
    }
    @discardableResult func cancel(_ id: UUID? = nil) -> Bool {
        guard let session = active, id == nil || session.id == id else { return false }
        session.finished = true; active = nil
        return true
    }
    func take(_ id: UUID? = nil) -> Commit? {
        guard let session = active, !session.finished, id == nil || session.id == id else { return nil }
        let commit = Commit(control: session.control, draft: session.draft)
        cancel(session.id)
        return commit
    }
}
