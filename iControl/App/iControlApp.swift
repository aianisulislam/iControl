import AppKit
import SwiftUI

@MainActor
final class AppController {
    private let inputController = InputController()
    private let server: HTTPServer

    init() {
        server = HTTPServer(port: 4040, inputController: inputController)
    }

    func start() {
        server.start()
    }

    func openControlPage() {
        guard let url = URL(string: "http://localhost:4040") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("iControl: application did finish launching")
        controller.start()
    }

    func openControlPage() {
        controller.openControlPage()
    }

    func quit() {
        controller.quit()
    }
}

@main
struct iControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            Button("Open Control Page") {
                appDelegate.openControlPage()
            }

            Divider()

            Button("Quit") {
                appDelegate.quit()
            }
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.menu)
    }
}
