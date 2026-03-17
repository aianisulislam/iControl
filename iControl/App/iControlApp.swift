import AppKit
import SwiftUI
import CoreImage
import ServiceManagement

@main
struct iControlApp: App {
    private let server: HTTPServer
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    init() {
        // Sync saved config
        _launchAtLogin = AppStorage(wrappedValue: SMAppService.mainApp.status == .enabled, "launchAtLogin")

        // Start the web server
        let inputController = InputController()
        server = HTTPServer(port: 4040, inputController: inputController)
        server.start()

    }

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

                Button(action: {
                    launchAtLogin.toggle()
                    do {
                        if launchAtLogin {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        print("iControl: failed to update launch at login: \(error)")
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

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
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

        guard let outputImage = filter.outputImage else { return nil }

        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let rep = NSCIImageRep(ciImage: scaled)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }
}
