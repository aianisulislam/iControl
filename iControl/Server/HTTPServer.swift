import Foundation
import Network
import CryptoKit

final class HTTPServer {
    private let port: UInt16
    private let inputController: InputController
    private let authContext: AuthContext
    private let queue = DispatchQueue(label: "iControl.HTTPServer")
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: ClientConnection] = [:]
    private var webSockets: [ObjectIdentifier: WebSocketServer] = [:]

    init(port: UInt16, inputController: InputController, authContext: AuthContext) {
        self.port = port
        self.inputController = inputController
        self.authContext = authContext
        self.inputController.onVolumeChanged = { [weak self] volume in
            self?.broadcastVolume(volume)
        }
    }

    func start() {
        guard listener == nil else {
            print("iControl: server already running on port \(port)")
            return
        }

        guard let listenerPort = NWEndpoint.Port(rawValue: port) else {
            print("iControl: invalid port \(port)")
            return
        }

        do {
            let listener = try NWListener(using: .tcp, on: listenerPort)
            listener.stateUpdateHandler = { [weak self] state in
                self?.handleListenerState(state)
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            self.listener = listener
            print("iControl: starting HTTP server on port \(port)")
            listener.start(queue: queue)
        } catch {
            print("iControl: failed to start server on port \(port): \(error)")
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let endpoint = listener?.port {
                print("iControl: server listening on 0.0.0.0:\(endpoint.rawValue)")
            } else {
                print("iControl: server listener ready")
            }
        case .failed(let error):
            print("iControl: listener failed: \(error)")
        case .cancelled:
            print("iControl: listener cancelled")
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        let identifier = ObjectIdentifier(connection)
        let client = ClientConnection(connection: connection)
        clients[identifier] = client

        print("iControl: client connected")

        connection.stateUpdateHandler = { [weak self] state in
            self?.handleConnectionState(state, id: identifier)
        }

        connection.start(queue: queue)
        receiveRequest(for: identifier)
    }

    private func handleConnectionState(_ state: NWConnection.State, id: ObjectIdentifier) {
        switch state {
        case .failed(let error):
            print("iControl: client connection failed: \(error)")
            removeConnection(id: id)
        case .cancelled:
            removeConnection(id: id)
        default:
            break
        }
    }

    private func receiveRequest(for id: ObjectIdentifier) {
        guard let client = clients[id] else { return }

        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                print("iControl: receive error: \(error)")
                self.removeConnection(id: id)
                return
            }

            if let data, !data.isEmpty {
                client.buffer.append(data)
            }

            if client.buffer.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.handleRequest(client.buffer, for: id)
                return
            }

            if isComplete {
                self.handleRequest(client.buffer, for: id)
                return
            }

            self.receiveRequest(for: id)
        }
    }

    private func handleRequest(_ data: Data, for id: ObjectIdentifier) {
        guard let client = clients[id] else { return }

        guard let request = String(data: data, encoding: .utf8) else {
            print("iControl: invalid request data")
            send(status: "400 Bad Request", body: "Bad Request", contentType: "text/plain", to: client.connection, closeAfterSend: true)
            return
        }

        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first, !requestLine.isEmpty else {
            print("iControl: missing request line")
            send(status: "400 Bad Request", body: "Bad Request", contentType: "text/plain", to: client.connection, closeAfterSend: true)
            return
        }

        print("iControl: HTTP request received: \(requestLine)")

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            send(status: "400 Bad Request", body: "Bad Request", contentType: "text/plain", to: client.connection, closeAfterSend: true)
            return
        }

        let method = String(parts[0])
        let rawPath = String(parts[1])
        let headers = parseHeaders(lines.dropFirst())

        if headers["upgrade"]?.lowercased() == "websocket" {
            print("iControl: WebSocket upgrade attempt")
            upgradeToWebSocket(headers: headers, connectionID: id)
            return
        }

        guard method == "GET" else {
            send(status: "404 Not Found", body: "Not Found", contentType: "text/plain", to: client.connection, closeAfterSend: true)
            return
        }

        let path = rawPath.components(separatedBy: "?").first ?? rawPath
        let filePath = (path == "/") ? "/index.html" : path

        guard !filePath.contains("..") else {
            send(status: "403 Forbidden", body: "Forbidden", contentType: "text/plain", to: client.connection, closeAfterSend: true)
            return
        }

        let relativePath = String(filePath.dropFirst())
        let url = URL(fileURLWithPath: relativePath)
        let fileName = url.deletingPathExtension().path
        let fileExtension = url.pathExtension

        guard let resourceURL = Bundle.main.url(forResource: fileName, withExtension: fileExtension.isEmpty ? nil : fileExtension),
              let fileData = try? Data(contentsOf: resourceURL) else {
            print("iControl: resource not found: \(relativePath)")
            send(status: "404 Not Found", body: "Not Found", contentType: "text/plain", to: client.connection, closeAfterSend: true)
            return
        }

        let contentType = mimeType(for: fileExtension)
        print("iControl: serving \(relativePath) (\(contentType))")
        send(status: "200 OK", data: fileData, contentType: contentType, to: client.connection, closeAfterSend: true)
    }

    private func mimeType(for extension: String) -> String {
        switch `extension`.lowercased() {
        case "html":        return "text/html; charset=utf-8"
        case "css":         return "text/css; charset=utf-8"
        case "js":          return "application/javascript; charset=utf-8"
        case "json":        return "application/json"
        case "png":         return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "svg":         return "image/svg+xml"
        case "ico":         return "image/x-icon"
        case "webp":        return "image/webp"
        case "woff":        return "font/woff"
        case "woff2":       return "font/woff2"
        case "webmanifest": return "application/manifest+json"
        default:            return "application/octet-stream"
        }
    }

    private func parseHeaders(_ lines: ArraySlice<String>) -> [String: String] {
        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            headers[String(parts[0]).lowercased()] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        return headers
    }

    private func upgradeToWebSocket(headers: [String: String], connectionID: ObjectIdentifier) {
        guard let client = clients[connectionID] else { return }

        guard let key = headers["sec-websocket-key"] else {
            send(status: "400 Bad Request", body: "Missing WebSocket Key", contentType: "text/plain", to: client.connection, closeAfterSend: true)
            return
        }

        let accept = websocketAccept(for: key)
        let response =
            "HTTP/1.1 101 Switching Protocols\r\n" +
            "Upgrade: websocket\r\n" +
            "Connection: Upgrade\r\n" +
            "Sec-WebSocket-Accept: \(accept)\r\n" +
            "\r\n"

        client.connection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] error in
            guard let self else { return }

            if let error {
                print("iControl: WebSocket upgrade failed: \(error)")
                self.removeConnection(id: connectionID)
                return
            }

            print("iControl: WebSocket upgrade succeeded")
            let socket = WebSocketServer(connection: client.connection, inputController: self.inputController, authContext: self.authContext)
            self.webSockets[connectionID] = socket
            socket.start()
        })
    }

    private func websocketAccept(for key: String) -> String {
        let magic = key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let hash = Insecure.SHA1.hash(data: Data(magic.utf8))
        return Data(hash).base64EncodedString()
    }

    private func send(status: String, body: String, contentType: String, to connection: NWConnection, closeAfterSend: Bool) {
        send(status: status, data: Data(body.utf8), contentType: contentType, to: connection, closeAfterSend: closeAfterSend)
    }

    private func send(status: String, data: Data, contentType: String, to connection: NWConnection, closeAfterSend: Bool) {
        let response =
            "HTTP/1.1 \(status)\r\n" +
            "Content-Type: \(contentType)\r\n" +
            "Content-Length: \(data.count)\r\n" +
            "Connection: \(closeAfterSend ? "close" : "keep-alive")\r\n" +
            "\r\n"

        var packet = Data(response.utf8)
        packet.append(data)

        connection.send(content: packet, completion: .contentProcessed { [weak self] error in
            if let error {
                print("iControl: send failed: \(error)")
            }
            if closeAfterSend {
                connection.cancel()
            }
            if closeAfterSend, let self {
                self.removeConnection(id: ObjectIdentifier(connection))
            }
        })
    }

    private func removeConnection(id: ObjectIdentifier) {
        clients[id] = nil
        webSockets[id] = nil
    }

    private func broadcastVolume(_ volume: Double) {
        queue.async { [weak self] in
            guard let self else { return }
            for socket in self.webSockets.values {
                socket.sendState(volume: volume)
            }
        }
    }
}

private final class ClientConnection {
    let connection: NWConnection
    var buffer = Data()

    init(connection: NWConnection) {
        self.connection = connection
    }
}