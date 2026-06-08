import SwiftUI
import AppKit

/// The contents of the menu-bar dropdown. Rendered with `.menu` style, so each
/// view maps to a native menu item (Toggles get checkmarks, Pickers get radios).
struct MenuContent: View {
    @ObservedObject var controller: CaffeinateController

    var body: some View {
        Text(controller.statusText)

        Divider()

        Button(controller.isActive ? "Turn Off" : "Turn On Now") {
            controller.toggleActive()
        }
        .keyboardShortcut("t", modifiers: .command)

        Divider()

        Toggle("Prevent display sleep (-d)",        isOn: $controller.preventDisplaySleep)
        Toggle("Prevent idle sleep (-i)",           isOn: $controller.preventIdleSleep)
        Toggle("Prevent disk idle sleep (-m)",      isOn: $controller.preventDiskSleep)
        Toggle("Prevent system sleep on AC (-s)",   isOn: $controller.preventSystemSleep)
        Toggle("Keep display awake (-u)",           isOn: $controller.declareUserActive)

        Divider()

        Menu("Duration: \(controller.durationLabel)") {
            Picker("Duration", selection: $controller.durationSeconds) {
                Text("Until I turn it off").tag(0)
                Text("15 minutes").tag(900)
                Text("30 minutes").tag(1800)
                Text("1 hour").tag(3600)
                Text("2 hours").tag(7200)
                Text("4 hours").tag(14400)
                Text("8 hours").tag(28800)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }

        Divider()

        Toggle("Launch at login", isOn: $controller.launchAtLogin)

        Button("Quit MacBull") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
