import AppKit
import SwiftUI
import CoreImage
import ServiceManagement
import SystemConfiguration
import LocalAuthentication

// MARK: - AuthContext

final class AuthContext {
    var mode: String
    var persistentToken: String
    var approvedSessions: Set<String> = []

    static let tokenChars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    init(mode: String, token: String) {
        self.mode = mode
        self.persistentToken = token
    }

    func isTokenValid(_ token: String) -> Bool {
        token == persistentToken || approvedSessions.contains(token)
    }

    func isWellFormed(_ token: String) -> Bool {
        guard token.count == 4 else { return false }
        let validChars = CharacterSet.uppercaseLetters.union(.decimalDigits)
        return token.unicodeScalars.allSatisfy { validChars.contains($0) }
    }

    static func generateToken() -> String {
        String((0..<4).map { _ in tokenChars[Int.random(in: 0..<tokenChars.count)] })
    }
}

// MARK: - App

@main
struct iControlApp: App {
    private let server: HTTPServer
    private let authContext: AuthContext
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("authMode") private var authMode = "secure"
    @AppStorage("authToken") private var authToken = ""
    @State private var showSecuritySubmenu = false

    init() {
        // Sync saved config
        _launchAtLogin = AppStorage(wrappedValue: SMAppService.mainApp.status == .enabled, "launchAtLogin")

        // Initialize auth token if not present
        let existingToken = UserDefaults.standard.string(forKey: "authToken") ?? ""
        let token: String
        if existingToken.isEmpty {
            token = AuthContext.generateToken()
            UserDefaults.standard.set(token, forKey: "authToken")
        } else {
            token = existingToken
        }

        // Default to secure mode on first launch
        if UserDefaults.standard.object(forKey: "authMode") == nil {
            UserDefaults.standard.set("secure", forKey: "authMode")
        }
        let mode = UserDefaults.standard.string(forKey: "authMode") ?? "secure"

        let ctx = AuthContext(mode: mode, token: token)
        authContext = ctx

        // Start the web server
        let inputController = InputController()
        server = HTTPServer(port: 4040, inputController: inputController, authContext: ctx)
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
                    let qrURL = Self.buildURL(
                        base: Self.hostnameURL() ?? Self.ipURL() ?? "http://localhost:4040",
                        token: authMode == "secure" ? authToken : nil
                    )

                    if let qrImage = Self.generateQRCode(from: qrURL) {
                        Image(nsImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .aspectRatio(1, contentMode: .fit)
                            .frame(width: 160, height: 160)
                    }

                    if let base = Self.hostnameURL() {
                        let url = Self.buildURL(base: base, token: authMode == "secure" ? authToken : nil)
                        Text(url)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let base = Self.ipURL() {
                        let url = Self.buildURL(base: base, token: authMode == "secure" ? authToken : nil)
                        Text(url)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if authMode == "secure" {
                      Text("Token: \(authToken)")
                              .font(.system(size: 11))
                              .foregroundColor(.secondary)
                              .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                // Connection Security submenu row
                Button(action: { withAnimation(.easeInOut(duration: 0.18)) { showSecuritySubmenu.toggle() } }) {
                    HStack(spacing: 4) {
                        Text("Connection Security")
                            .font(.system(size: 13))
                        Spacer()
                        Text(authMode == "secure" ? "Secure" : "Open")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(showSecuritySubmenu ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                if showSecuritySubmenu {
                    VStack(spacing: 0) {
                        Button(action: {
                            showSecuritySubmenu = false
                            authModePickerBinding.wrappedValue = "secure"
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .opacity(authMode == "secure" ? 1 : 0)
                                Text("Secure")
                                    .font(.system(size: 13))
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 24)
                        .padding(.trailing, 12)
                        .padding(.vertical, 6)

                        Button(action: {
                            showSecuritySubmenu = false
                            authModePickerBinding.wrappedValue = "open"
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .opacity(authMode == "open" ? 1 : 0)
                                Text("Open")
                                    .font(.system(size: 13))
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 24)
                        .padding(.trailing, 12)
                        .padding(.vertical, 6)
                    }
                }

                if authMode == "secure" {
                    Button("Regenerate Token") {
                        let newToken = AuthContext.generateToken()
                        authToken = newToken
                        authContext.persistentToken = newToken
                        authContext.approvedSessions = []
                        UserDefaults.standard.set(newToken, forKey: "authToken")
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }

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
            .frame(width: 240)
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.window)
    }

    // MARK: - Auth mode helpers

    /// Custom binding so the picker setter only fires on real user interaction,
    /// never during SwiftUI's re-render cycle (which would re-trigger LA auth
    /// every time the MenuBarExtra window is opened while mode == "open").
    private var authModePickerBinding: Binding<String> {
        Binding(
            get: { authMode },
            set: { newValue in
                guard newValue != authMode else { return }
                if newValue == "open" {
                    switchToOpenMode()
                } else {
                    setAuthMode("secure")
                }
            }
        )
    }

    private func setAuthMode(_ mode: String) {
        authMode = mode
        authContext.mode = mode
        UserDefaults.standard.set(mode, forKey: "authMode")
        if mode == "secure" {
            let newToken = AuthContext.generateToken()
            authToken = newToken
            authContext.persistentToken = newToken
            authContext.approvedSessions = []
            UserDefaults.standard.set(newToken, forKey: "authToken")
        }
    }

    private func switchToOpenMode() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            actuallySetOpenMode()
            return
        }
        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "disable security connection. Allowing this will allow any device in the same network to connect to your Mac via iControl."
        ) { success, _ in
            DispatchQueue.main.async {
                if success { self.actuallySetOpenMode() }
            }
        }
    }

    private func actuallySetOpenMode() {
        authMode = "open"
        authContext.mode = "open"
        UserDefaults.standard.set("open", forKey: "authMode")
    }

    // MARK: - URL helpers

    static func buildURL(base: String, token: String?) -> String {
        guard let token, !token.isEmpty else { return base }
        return "\(base)?token=\(token)"
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
