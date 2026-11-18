import Foundation

extension MusicVideoStudio {
    /// Snapshot undo/redo. The project is a small value type, so a snapshot is
    /// cheap and every edit is perfectly reversible.
    struct UndoHistory<State: Equatable> {
        private(set) var undoStack: [State] = []
        private(set) var redoStack: [State] = []
        let limit: Int

        init(limit: Int = 100) { self.limit = max(1, limit) }

        var canUndo: Bool { !undoStack.isEmpty }
        var canRedo: Bool { !redoStack.isEmpty }

        /// Call BEFORE changing `state`. Consecutive identical checkpoints are ignored.
        mutating func checkpoint(_ state: State) {
            if undoStack.last == state { return }
            undoStack.append(state)
            if undoStack.count > limit { undoStack.removeFirst(undoStack.count - limit) }
            redoStack.removeAll()
        }

        mutating func undo(current: State) -> State? {
            guard let previous = undoStack.popLast() else { return nil }
            redoStack.append(current)
            return previous
        }

        mutating func redo(current: State) -> State? {
            guard let next = redoStack.popLast() else { return nil }
            undoStack.append(current)
            return next
        }

        mutating func clear() {
            undoStack.removeAll()
            redoStack.removeAll()
        }
    }
}
