import Foundation
import Network

struct RemoteCommand: Decodable {
    let type: String
    let key: String?
    let url: String?
    let value: CommandValue?
    let button: String?
    let action: String?
    let app: String?
    let dx: Double?
    let dy: Double?
}

enum CommandValue: Decodable {
    case string(String)
    case number(Double)

    var stringValue: String? {
        if case let .string(value) = self {
            return value
        }
        return nil
    }

    var numberValue: Double? {
        if case let .number(value) = self {
            return value
        }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let string = try? container.decode(String.self) {
            self = .string(string)
            return
        }

        self = .number(try container.decode(Double.self))
    }
}

final class WebSocketServer {
    private let connection: NWConnection
    private let inputController: InputController

    init(connection: NWConnection, inputController: InputController) {
        self.connection = connection
        self.inputController = inputController
    }

    func start() {
        sendInitialState()
        receiveFrame()
    }

    func sendState(volume: Double) {
        let roundedVolume = Int(volume.rounded())
        let payload = #"{"type":"state","volume":\#(roundedVolume)}"#
        sendFrame(opcode: 0x1, payload: Data(payload.utf8))
    }

    private func receiveFrame() {
        connection.receive(minimumIncompleteLength: 2, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else {
                return
            }

            if let data, !data.isEmpty {
                self.handleFrame(data)
            }

            if error == nil && !isComplete {
                self.receiveFrame()
            }
        }
    }

    private func handleFrame(_ data: Data) {
        guard let frame = decodeFrame(data) else {
            return
        }

        switch frame.opcode {
        case 0x1:
            handleText(frame.payload)
        case 0x8:
            connection.cancel()
        case 0x9:
            sendFrame(opcode: 0xA, payload: frame.payload)
        default:
            break
        }
    }

    private func handleText(_ payload: Data) {
        if let rawPayload = String(data: payload, encoding: .utf8) {
            print("iControl: WebSocket payload received: \(rawPayload)")
        } else {
            print("iControl: WebSocket payload received (\(payload.count) bytes)")
        }

        guard let command = try? JSONDecoder().decode(RemoteCommand.self, from: payload) else {
            print("iControl: failed to decode WebSocket payload")
            return
        }

        switch command.type {
        case "key":
            if let key = command.key {
                inputController.pressKey(key: key)
            }
        case "text":
            if let value = command.value?.stringValue {
                inputController.typeText(string: value)
            }
        case "click":
            inputController.mouseClick(button: command.button ?? "left")
        case "doubleClick":
            inputController.doubleClick(button: command.button ?? "left")
        case "tripleClick":
            inputController.tripleClick(button: command.button ?? "left")
        case "mouseDown":
            inputController.mouseDown(button: command.button ?? "left")
        case "mouseUp":
            inputController.mouseUp(button: command.button ?? "left")
        case "dragMove":
            inputController.dragMouse(dx: command.dx ?? 0, dy: command.dy ?? 0)
        case "move":
            inputController.moveMouse(dx: command.dx ?? 0, dy: command.dy ?? 0)
        case "scroll":
            inputController.scroll(dx: command.dx ?? 0, dy: command.dy ?? 0)
        case "system":
            if let action = command.action {
                inputController.performSystemAction(action, value: command.value?.numberValue)
            }
        case "app":
            if let app = command.app {
                inputController.launchApp(app)
            }
        case "url":
            if let url = command.url {
                inputController.openURL(url)
            }
        default:
            break
        }
    }

    private func sendFrame(opcode: UInt8, payload: Data) {
        var frame = Data()
        frame.append(0x80 | opcode)

        if payload.count < 126 {
            frame.append(UInt8(payload.count))
        } else if payload.count <= 65_535 {
            frame.append(126)
            frame.append(UInt8((payload.count >> 8) & 0xFF))
            frame.append(UInt8(payload.count & 0xFF))
        } else {
            frame.append(127)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((UInt64(payload.count) >> UInt64(shift)) & 0xFF))
            }
        }

        frame.append(payload)
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func sendInitialState() {
        guard let volume = inputController.currentVolumePercentage() else {
            return
        }

        sendState(volume: volume)
    }

    private func decodeFrame(_ data: Data) -> (opcode: UInt8, payload: Data)? {
        guard data.count >= 2 else {
            return nil
        }

        let opcode = data[0] & 0x0F
        let masked = (data[1] & 0x80) != 0
        var payloadLength = Int(data[1] & 0x7F)
        var offset = 2

        if payloadLength == 126 {
            guard data.count >= 4 else {
                return nil
            }

            payloadLength = Int(data[2]) << 8 | Int(data[3])
            offset = 4
        } else if payloadLength == 127 {
            guard data.count >= 10 else {
                return nil
            }

            payloadLength = 0
            for index in 2..<10 {
                payloadLength = (payloadLength << 8) | Int(data[index])
            }
            offset = 10
        }

        var maskKey = [UInt8]()
        if masked {
            guard data.count >= offset + 4 else {
                return nil
            }

            maskKey = Array(data[offset..<(offset + 4)])
            offset += 4
        }

        guard data.count >= offset + payloadLength else {
            return nil
        }

        let payload = Data(data[offset..<(offset + payloadLength)])
        guard masked else {
            return (opcode, payload)
        }

        let unmasked = Data(payload.enumerated().map { index, byte in
            byte ^ maskKey[index % 4]
        })

        return (opcode, unmasked)
    }
}
