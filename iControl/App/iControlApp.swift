import AppKit
import SwiftUI
import CoreImage
import ServiceManagement

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

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    func enableLaunchAtLogin() {
        do {
            try SMAppService.mainApp.register()
        } catch {
            print("Failed to register for launch at login: \(error)")
        }
    }

    func disableLaunchAtLogin() {
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            print("Failed to unregister for launch at login: \(error)")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("iControl: application did finish launching")
        controller.start()
        // Check launch at login status
        let isEnabled = SMAppService.mainApp.status == .enabled
        UserDefaults.standard.set(isEnabled, forKey: "launchAtLogin")
    }

    func enableLaunchAtLogin() {
        controller.enableLaunchAtLogin()
    }

    func disableLaunchAtLogin() {
        controller.disableLaunchAtLogin()
    }

    func quit() {
        controller.quit()
    }
}

@main
struct iControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var launchAtLogin: Bool = UserDefaults.standard.bool(forKey: "launchAtLogin")

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 0) {
                Text("Scan the QR code or open the URL on any device on the same network:")
                      .font(.system(size: 12))
                      .foregroundColor(.primary)
                      .fixedSize(horizontal: false, vertical: true)
                      .padding(.horizontal, 12)
                      .padding(.top, 12)
                      .padding(.bottom, 4)
                      
                // QR Code section
                VStack(alignment: .center, spacing: 8) {

                    if let qrImage = Self.generateQRCode(from: Self.controlURL()) {
                        Image(nsImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .aspectRatio(1, contentMode: .fit)
                            .frame(width: 160, height: 160)
                    }

                    Text(Self.controlURL())
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                // Open at login
                Button(action: {
                    launchAtLogin.toggle()
                    UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
                    if launchAtLogin {
                        appDelegate.enableLaunchAtLogin()
                    } else {
                        appDelegate.disableLaunchAtLogin()
                    }
                }) {
                    HStack {
                        Text("Open at Login")
                            .font(.system(size: 13))
                        Spacer()
                        if launchAtLogin {
                            Text("✓")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                // Quit
                Button("Quit") {
                    appDelegate.quit()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(width: 184)
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.window)
    }

    static func controlURL() -> String {
        let hostname = Host.current().localizedName?
            .replacingOccurrences(of: " ", with: "-") ?? "localhost"
        return "http://\(hostname).local:4040"
    }

    static func generateQRCode(from string: String) -> NSImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }

        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else {
            return nil
        }

        let scale = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: scale)

        let rep = NSCIImageRep(ciImage: scaledImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }
}