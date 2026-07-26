import AppKit

/// Shared drop-off point for files handed to the app from outside SwiftUI's
/// own view hierarchy — specifically, files dragged onto the Dock icon (or
/// onto the app via Finder's "Open With"), which macOS routes to
/// `NSApplicationDelegate.application(_:open:)` rather than through any
/// view's `.onDrop`. ContentView observes this and imports whatever lands
/// here, the same way it handles a drop onto the window itself.
final class DropCoordinator: ObservableObject {
    static let shared = DropCoordinator()
    @Published var incomingURLs: [URL] = []
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        DropCoordinator.shared.incomingURLs.append(contentsOf: urls)
    }
}
