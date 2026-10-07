import Common
import SwiftUI

public let diagnosticsWindowId = "\(appName).stateDiagnostics"

@MainActor public func diagnosticsWindow(model: DiagnosticsModel) -> some Scene {
    SwiftUI.Window("tile state diagnostics", id: diagnosticsWindowId) {
        DiagnosticsView(model: model)
            .onAppear {
                NSApp.setActivationPolicy(.accessory)
                NSApp.activate()
            }
    }
    .defaultSize(width: 900, height: 620)
    .windowResizability(.contentMinSize)
    .defaultLaunchBehavior(.suppressed)
    .restorationBehavior(.disabled)
}

struct OpenDiagnosticsButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open diagnostics…") {
            // Capture before opening our window changes the frontmost application.
            DiagnosticsModel.shared.capture()
            openWindow(id: diagnosticsWindowId)
        }
    }
}

private struct DiagnosticsView: View {
    let model: DiagnosticsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tile's current state").font(.headline)
                Spacer()
                if model.isCapturing {
                    ProgressView().controlSize(.small)
                    Text("Reading Accessibility…").foregroundStyle(.secondary)
                }
            }
            Text(
                "Capture this report when a window goes missing, before restarting Tile. Capture again takes a new snapshot."
            )
            .foregroundStyle(.secondary)
            ScrollView([.horizontal, .vertical]) {
                Text(model.report)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
            }
            .background(.background.secondary)
            HStack {
                Button("Capture again") { model.capture() }
                    .keyboardShortcut("r", modifiers: .command)
                Spacer()
                Button("Copy report") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.report, forType: .string)
                }
                Button("Save report…") { saveReport() }
            }
        }
        .padding(16)
        .frame(minWidth: 600, minHeight: 360)
        .onDisappear {
            model.cancelCapture()
            model.saveError = nil
        }
        .alert(
            "Could not save diagnostics",
            isPresented: Binding(
                get: { model.saveError != nil }, set: { if !$0 { model.saveError = nil } }
            )
        ) {
            Button("OK") { model.saveError = nil }
        } message: {
            Text(model.saveError ?? "")
        }
    }

    private func saveReport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "tile-diagnostics.txt"
        let report = model.report
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            do { try report.write(to: url, atomically: true, encoding: .utf8) } catch {
                model.saveError = error.localizedDescription
            }
        }
    }
}
