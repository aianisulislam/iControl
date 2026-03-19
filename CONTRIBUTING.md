# Contributing to iControl

Bug reports, fixes, and focused feature additions are welcome.

---

## Before opening a PR

- Open an issue first for anything non-trivial. This avoids wasted effort if the direction doesn't fit the project's goals.
- Keep the scope tight. iControl is intentionally minimal — proposals that add dependencies, require accounts, or phone home will be declined.
- One concern per PR.

---

## Building locally

Requires macOS 13+ and Xcode 15+. No package manager, no external dependencies.

1. Clone the repo.
2. Open `iControl.xcodeproj` in Xcode.
3. Select the **iControl** scheme and run (`⌘R`).
4. Grant Accessibility access when prompted (**System Settings → Privacy & Security → Accessibility**).
5. The menu bar icon appears; open `http://hostname.local:4040` on any device on your LAN.

---

## Project layout

```
iControl/
├── App/            Swift app entry point & menu bar logic
├── Server/         HTTP + WebSocket server
├── Input/          CGEvent / HID input handlers
└── Resources/      index.html  (entire frontend — one self-contained file)
```

There is intentionally no build step for the frontend. Edit `index.html` directly.

---

## Guidelines

**Swift**
- Follow the existing style — no forced unwraps, no third-party packages.
- New command types belong in `WebSocketServer.swift` following the existing `switch` pattern.
- Test on a real device, not just the simulator.

**Frontend (`index.html`)**
- The entire UI lives in one file. Keep it that way.
- No frameworks, no bundlers, no npm.
- Verify touch behaviour on an actual phone — the emulator misses gesture edge cases.

**General**
- Match the surrounding code style.
- Don't add comments that restate what the code does; only comment the *why* when it's non-obvious.
- Prefer deleting code over adding it where possible.

---

## Submitting

1. Fork and create a branch off `main`.
2. Make your change.
3. Open a pull request with a short description of *what* and *why*.

There's no formal test suite. Describe how you verified the change works in the PR body.
