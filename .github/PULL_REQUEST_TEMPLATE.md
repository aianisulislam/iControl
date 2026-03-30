## What this does

<!-- One or two sentences. What changed and why? -->

## Related issue

<!-- Closes #??? / Fixes #??? — or "none" -->

## Type of change

- [ ] Bug fix
- [ ] New feature / enhancement
- [ ] Refactor (no behaviour change)
- [ ] Docs / comments only
- [ ] Other

## Areas touched

- [ ] `iControlApp.swift` — menu bar, QR code, auth mode, launch-at-login
- [ ] `HTTPServer.swift` — HTTP listener, WebSocket upgrade, static serving
- [ ] `WebSocketServer.swift` — frame codec, auth gate, command dispatch
- [ ] `InputController.swift` — mouse, keyboard, system actions, volume
- [ ] `index.html` — frontend UI, gesture engine, keyboard, auth flow
- [ ] `sw.js` — service worker, cache, version detection
- [ ] `manifest.json` / PWA assets
- [ ] `inject_version.sh` — build-phase version stamping
- [ ] Other

## Hard constraints checklist

- [ ] No external libraries added (Swift or JS)
- [ ] No network calls introduced outside LAN
- [ ] `index.html` remains a single self-contained file
- [ ] Total bundle stays under 1MB
- [ ] Protocol changes are backward compatible (new fields are optional)

## Sensitive areas

If you touched any of the following, explain what changed and why it is safe:

- [ ] `InputController.alphaNumericKeyCode()` — 100+ key mappings
- [ ] WebSocket frame parser in `WebSocketServer.swift` — manual RFC 6455
- [ ] Auth gate in `WebSocketServer.handleText` — `.pending` guard must remain first
- [ ] `authModePickerBinding` in `iControlApp.swift` — custom Binding, not `.onChange`
- [ ] `icontrol-denied` sessionStorage checks — all reconnect paths must check this
- [ ] `usleep(1500)` modifier timing in `InputController.swift`
- [ ] Service Worker cache key in `sw.js`
- [ ] `touchTracker` gesture state machine in `index.html`
- [ ] `inject_version.sh` / `<meta name="version">` tag pairing

<!-- Not applicable? Leave unchecked. -->

## Testing

<!-- How did you verify this? Which devices/browsers did you test on?
     There is no automated test suite — manual testing notes are the record. -->

## Screenshots / recordings

<!-- For UI changes, attach before/after. For input behaviour, a short screen recording helps. -->
