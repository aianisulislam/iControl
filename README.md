<h1 align="center">
  <svg width="36px" height="36px" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
    <defs>
      <linearGradient
        id="g1"
        x2="1"
        gradientUnits="userSpaceOnUse"
        gradientTransform="matrix(0,764.852,-574.752,0,512.376,130)"
      >
        <stop offset="0" stop-color="#7e94b8" />
        <stop offset=".54" stop-color="#3c5789" />
        <stop offset="1" stop-color="#071b47" />
      </linearGradient>
    </defs>
    <path
      fill="url(#g1)"
      d="m797.82 681.96l-16.15 150.85c-9.35 39.1-49.72 62.04-96.46 62.04h-237.54c-16.15 0-31.45-1.7-40.37-12.75l-106.24-168.27c-13.59-16.57-11.04-38.67 5.53-52.69 21.25-18.28 56.52-15.73 73.94 5.52l40.79 49.72v-356.1c0-22.95 22.1-41.65 49.29-41.65 34.85 0 49.3 26.78 49.3 41.65l0.42 211.62 212.05 16.57c47.17 13.6 75.21 51.84 65.44 93.49zm-523.95-237.54c-26.77 0-48.87-19.13-48.87-42.07v-52.27c0-293.63 491.23-293.63 491.23 0v52.27c0 22.94-22.1 42.07-49.29 42.07-27.2 0-48.87-19.13-48.87-42.07v-52.27c0-167.85-294.91-167.85-294.91 0v52.27c0 22.94-22.1 42.07-49.29 42.07z"
    />
  </svg>
  iControl
</h1>

iControl is a wireless trackpad, keyboard and media remote for your Mac. No app to install — open a URL on your phone, it works.

- **Zero install** — any browser, any device, on your LAN
- **Under 1MB** — the entire app, server and client included
- **No account, no cloud, no telemetry** — physically cannot leave your network
- **PWA-ready** — add to Home Screen, it feels like a native app

Built out of spite for remote control apps that ask to track you across other apps for ad targeting, bloat your phone and sell you subscriptions for something that doesn't continuously cost them anything.

[Website & download](https://aianisulislam.github.io/iControl/) · MIT License

---

## Architecture

```
Browser (any device) ──WebSocket──▶ Swift HTTP/WS server ──▶ macOS APIs
                                        port 4040
```

The server is a native Swift menu bar app with no external dependencies. It serves a single self-contained `index.html` and maintains a WebSocket connection for receiving commands. Commands are executed via:

| Purpose | API |
|---|---|
| Mouse & keyboard input | `CGEvent` / HID pipeline |
| App management | `NSWorkspace` |
| Volume control | `CoreAudio` |
| Launch at login | `ServiceManagement` (`SMAppService`) |

Communication is one-way — the Mac executes commands and never sends sensitive data back to the client (only connection state and volume level).

---

## Project structure

```
iControl/
├── iControl.xcodeproj/
└── iControl/
    ├── App/
    │   └── iControlApp.swift      # App entry point, menu bar UI, QR code generation
    ├── Input/
    │   └── InputController.swift  # All input simulation (mouse, keyboard, media, volume)
    ├── Server/
    │   ├── HTTPServer.swift       # HTTP server — serves index.html on port 4040
    │   └── WebSocketServer.swift  # WebSocket server — receives and dispatches commands
    └── Resources/
        ├── index.html             # Entire client UI (single file, no build step)
        ├── manifest.json          # PWA manifest
        ├── sw.js                  # Service worker for offline/PWA support
        └── favicon*, *.png        # Icons
```

No package managers, no build steps, no external dependencies — on either the client or the server side.

---

## Building from source

**Requirements:** Xcode 15+, macOS 13 SDK or later.

```bash
git clone https://github.com/aianisulislam/iControl
cd iControl
open iControl.xcodeproj
```

Build and run (`Cmd+R`) in Xcode. The app will appear in the menu bar. On first run, macOS will prompt for Accessibility permissions — required for input simulation.

To build a release archive: **Product → Archive** in Xcode.

---

## Key entry points

### [iControlApp.swift](iControl/App/iControlApp.swift)
App entry point and menu bar UI. Owns the `AppController`, which starts the `HTTPServer`. Also handles:
- QR code generation from the local mDNS URL (`http://<hostname>.local:4040`)
- Launch-at-login toggle via `SMAppService`

The served URL is derived from `Host.current().localizedName` with spaces replaced by hyphens.

### [HTTPServer.swift](iControl/Server/HTTPServer.swift)
Listens on port 4040. Serves `index.html` for all HTTP requests and upgrades WebSocket connections.

### [WebSocketServer.swift](iControl/Server/WebSocketServer.swift)
Receives JSON command frames from the browser and dispatches them to `InputController`.

### [InputController.swift](iControl/Input/InputController.swift)
Implements all input simulation. Each command type maps to a macOS API call. This is where to add new input actions or modify existing behaviour.

### [index.html](iControl/Resources/index.html)
The entire client UI in one file — HTML, CSS, and JavaScript. No framework, no bundler. Edit directly; changes take effect on the next app build.

---

## Customisation

### Adding or changing input actions

1. Add a new command type in the WebSocket message handler in [WebSocketServer.swift](iControl/Server/WebSocketServer.swift).
2. Implement the action in [InputController.swift](iControl/Input/InputController.swift) using `CGEvent`, `NSWorkspace`, or the relevant macOS API.
3. Trigger it from [index.html](iControl/Resources/index.html) by sending a matching JSON frame over the WebSocket.

### WebSocket command format

Commands are JSON objects sent as text frames:

```json
{ "type": "mouse", "dx": 10, "dy": -5 }
{ "type": "key", "key": "space" }
{ "type": "app", "app": "Finder" }
{ "type": "url", "url": "https://example.com" }
{ "type": "volume", "level": 0.5 }
```

See [WebSocketServer.swift](iControl/Server/WebSocketServer.swift) for the full list of handled types.

### Customising the Apps tab

The app grid in [index.html](iControl/Resources/index.html) is a list of buttons with `data-command` attributes:

```html
<!-- Launch or focus an app -->
<button data-command='{"type":"app","app":"Finder"}'>Finder</button>

<!-- Open a URL in the default browser -->
<button data-command='{"type":"url","url":"https://example.com"}'>Example</button>
```

Edit the `apps` section in `index.html` to add, remove, or reorder entries. Apps can be referenced by display name or bundle ID.

### Changing the port

The port is hardcoded to `4040` in [iControlApp.swift](iControl/App/iControlApp.swift) (passed to `HTTPServer`) and in the URL construction in `controlURL()`. Change both if needed.

---

## Permissions

iControl requires **Accessibility access** to simulate input events. This is enforced by macOS for any app using `CGEvent` programmatically.

**System Settings → Privacy & Security → Accessibility → enable iControl**

No other permissions are required.

---

## Security model

- Accepts connections from the local network only (LAN-bound server socket)
- No cloud relay, no telemetry, no accounts
- Whitelisted command set — only recognised command types are executed
- One-way data flow — the client cannot read files or query system state

Auth modes (password / accept-once / open) are planned for a future release.

---

## License

MIT — do whatever you want with it.
