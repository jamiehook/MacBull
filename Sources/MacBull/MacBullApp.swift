import SwiftUI
import AppKit

@main
struct MacBullApp: App {
    @StateObject private var controller = CaffeinateController()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: controller)
        } label: {
            // Raging bull (snorting) while awake; sleeping bull (with a "z")
            // while sleep is allowed.
            if let icon = Self.statusIcon(active: controller.isActive) {
                Image(nsImage: icon).renderingMode(.template)
            } else {
                Image(systemName: controller.isActive ? "bolt.fill" : "moon.zzz")
            }
        }
        .menuBarExtraStyle(.menu)
    }

    /// Bundled bull template image for the given state, sized for the menu bar.
    /// Returns nil if the resource isn't found (e.g. running the bare binary
    /// outside the .app bundle), so the label can fall back to a system symbol.
    private static func statusIcon(active: Bool) -> NSImage? {
        let name = active ? "menubar-awake" : "menubar-asleep"
        guard let image = NSImage(named: name) else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }
}
