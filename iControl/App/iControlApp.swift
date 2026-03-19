import AppKit
import SwiftUI
import CoreImage
import ServiceManagement
import SystemConfiguration

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
                HStack {
                    Text("iControl ")
                        .font(.system(size: 13, weight: .bold))
                    Text("v\(Self.appVersion)")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
                
                Text("Scan the QR code or open the URL on any device on the same network:")
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)

                VStack(alignment: .center, spacing: 8) {
                    let qrURL = Self.hostnameURL() ?? Self.ipURL() ?? "http://localhost:4040"
                    if let qrImage = Self.generateQRCode(from: qrURL) {
                        Image(nsImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .aspectRatio(1, contentMode: .fit)
                            .frame(width: 160, height: 160)
                    }

                    if let url = Self.hostnameURL() {
                        Text(url)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    if let url = Self.ipURL() {
                        Text(url)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
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

    static func hostnameURL() -> String? {
        guard let hostname = SCDynamicStoreCopyLocalHostName(nil) as String? else { return nil }
        return "http://\(hostname).local:4040"
    }

    static func ipURL() -> String? {
        guard let ip = localIPAddress() else { return nil }
        return "http://\(ip):4040"
    }

    private static func localIPAddress() -> String? {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 80
        addr.sin_addr.s_addr = inet_addr("8.8.8.8")

        let sock = socket(AF_INET, SOCK_DGRAM, 0)
        guard sock != -1 else { return nil }
        defer { close(sock) }

        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { return nil }

        var local = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(sock, $0, &len)
            }
        }
        guard named == 0 else { return nil }

        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &local.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN))
        return String(cString: buffer)
    }
    
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
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
