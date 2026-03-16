# iControl

**Control your Mac from any device. No app. No account. No subscription.**

iControl is a zero-install, LAN-only macOS remote control. Open the URL on any device with a browser and you're in control — no installation, no sign-up, no cloud, no trackers.

Built out of frustration with subscription-gated, ad-riddled remote control apps that charge recurring fees for something that doesn't continuously cost them anything.

---

## Features

- **Zero-install client** — any device, any OS, any browser. Phone, tablet, laptop — if it has a browser, it works.
- **Platform agnostic** — Android, iOS, Windows, Linux. No ecosystem lock-in.
- **LAN only** — your input never leaves your network. No relay servers, no cloud, no telemetry.
- **Native Swift backend** — pure Swift, zero external dependencies. Direct access to macOS APIs for native feel.
- **Native cursor acceleration** — pointer movement goes through the HID event pipeline, feels like real hardware.
- **PWA ready** — install to your home screen for a native app experience.

---

## What you can do

### Touchpad
- 1-finger move with native macOS cursor acceleration
- 2-finger scroll
- Tap to click, double tap, triple tap
- Adjustable movement and scroll sensitivity

### General
- Sticky modifier keys — Cmd, Opt, Shift, Ctrl
- Arrow keys, Tab, Return, Space, Escape, Backspace
- Home, End, Page Up, Page Down
- Modifier-aware — toggle Cmd then tap any key

### System
- Mission Control, Launchpad, App Exposé
- App Switcher (Cmd+Tab), Spotlight (Cmd+Space)
- Minimize, Fullscreen, Close (Cmd+Q)
- Select All, Copy, Cut, Paste
- Undo (Cmd+Z), Redo (Cmd+Shift+Z)
- New (Cmd+N), Open (Cmd+O)

### Media
- Play/Pause, Next, Previous track
- Volume Up/Down with system overlay
- Volume slider for precise control
- iPod wheel interface

### Type
- Full mobile keyboard intelligence, autocorrect, predictions, emoji, voice input
- Cursor pad — drag to reposition cursor
- Quick actions — Select All, Copy, Cut, Paste, Backspace
- Cross-platform clipboard bridge — copy on phone, paste on Mac

### Apps
- One-tap launch or focus for your most-used apps
- Open any URL directly in the default browser
- Custom app launcher by name or bundle ID
- Works as a cross-device URL opener — copy a link on your phone, open it on your Mac instantly

---

## How it works

iControl runs as a native Swift menu bar app on your Mac. It serves a single HTML file over HTTP and maintains a WebSocket connection with the client. Commands sent from the browser are validated and executed via macOS APIs — CGEvent for input simulation, NSWorkspace for app management, CoreAudio for volume control.

```
Phone browser → WebSocket → Swift server → macOS APIs → System input
```

One-way communication only. The Mac never sends sensitive data to the client.

---

## Getting started

### Requirements
- macOS 13 or later
- Any device with a modern browser on the same network

### Installation
1. Download the latest release
2. Open `iControl.app`
3. Scan the QR code in the menu bar icon to open in your phone
4. Grant Accessibility permissions when prompted (required for input simulation)

### Connecting
By default iControl is accessible at:
```
http://your-mac-hostname.local:4040
```

Your hostname is usually your Mac's name with spaces replaced by hyphens. You can find the exact URL in the iControl menu bar item.

### Optional: Install as PWA
On iOS — open in Safari, tap Share → Add to Home Screen
On Android — open in Chrome, tap menu → Add to Home Screen

---

## Permissions

iControl requires **Accessibility access** to simulate keyboard and mouse input. This is a macOS requirement for any app that controls input programmatically.

Go to: **System Settings → Privacy & Security → Accessibility** and enable iControl.

No other permissions are required. iControl does not access your files, contacts, camera, microphone, or any personal data.

---

## Security

- **LAN only** — iControl only accepts connections from your local network
- **No cloud** — no data ever leaves your device
- **No accounts** — nothing to sign up for, nothing to leak
- **One-way** — the client sends commands, the Mac executes them. No data flows back to the client except connection state and volume level.

> Auth modes (accept/password/none) are planned for a future release.

---

## Customizing the app grid

The Apps tab ships with default macOS apps. To customize it for your workflow, clone the repo and edit the buttons in the `apps` section of `index.html`. Each button is a single line:

```html
<button data-command='{"type":"app","app":"Your App Name"}'>
```

For URL shortcuts:
```html
<button data-command='{"type":"url","url":"https://example.com"}'>
```

---

## Building from source

```bash
git clone https://github.com/aianisulislam/iControl
cd iControl
open iControl.xcodeproj
```

Build and run in Xcode. No external dependencies, no package manager setup required.

---

## Philosophy

iControl does one thing: send input from your phone to your Mac. It does not read files, expose system state, sync clipboards, or phone home. The attack surface is intentionally minimal — a whitelisted command set, validated and executed on the host.

The client is a web page. The server is a Swift app. There are no frameworks, no package managers, no build steps on either side. The entire project is readable in an afternoon.

Fork it, skin it, make it yours. If you use it, that name still holds — **I control**.

---

## License

MIT — do whatever you want with it.

---

*Built with spite, refined on a couch.*