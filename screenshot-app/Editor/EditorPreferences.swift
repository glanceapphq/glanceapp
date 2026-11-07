import Foundation

/// Editor styling remembered between screenshots.
struct EditorPreferences: Equatable {
    var padding: CGFloat = 48
    var cornerRadius: CGFloat = 8
    var background: CanvasBackground = .violet
    var annotationColor: AnnotationColor = .red

    static let defaults = EditorPreferences()

    private enum Key {
        static let padding = "editor.padding"
        static let cornerRadius = "editor.cornerRadius"
        static let background = "editor.background"
        static let annotationColor = "editor.annotationColor"
    }

    /// Reads saved preferences, falling back to defaults for missing or invalid values.
    static func load(from store: UserDefaults = .standard) -> EditorPreferences {
        var preferences = EditorPreferences()
        if let padding = store.object(forKey: Key.padding) as? Double {
            preferences.padding = CGFloat(padding).clamped(to: EditorModel.paddingRange)
        }
        if let cornerRadius = store.object(forKey: Key.cornerRadius) as? Double {
            preferences.cornerRadius = CGFloat(cornerRadius).clamped(to: EditorModel.cornerRadiusRange)
        }
        if let background = store.string(forKey: Key.background).flatMap(CanvasBackground.init) {
            preferences.background = background
        }
        if let color = store.string(forKey: Key.annotationColor).flatMap(AnnotationColor.init) {
            preferences.annotationColor = color
        }
        return preferences
    }

    func save(to store: UserDefaults = .standard) {
        store.set(Double(padding), forKey: Key.padding)
        store.set(Double(cornerRadius), forKey: Key.cornerRadius)
        store.set(background.rawValue, forKey: Key.background)
        store.set(annotationColor.rawValue, forKey: Key.annotationColor)
    }
}

extension Comparable {
    nonisolated func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
