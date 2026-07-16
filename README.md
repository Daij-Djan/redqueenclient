<p align="center">
  <img src="RedQueen/Resources/Assets.xcassets/BotAvatar.imageset/BotAvatar.png" width="120" alt="Red Queen" />
</p>

<h1 align="center">Red Queen</h1>

<p align="center">
  A personal, AI-first Matrix client for iOS — built to talk to the Hermes agent
  on <code>matrix.roesrath-kleineichen.de</code>, styled after the Red Queen from Resident Evil.
</p>

---

## What it is

Red Queen is a native SwiftUI Matrix client with the UX of an AI chat app
(ChatGPT/Gemini) rather than a general-purpose messenger. It talks to a
self-hosted Matrix homeserver where an AI agent ("Red Queen", Matrix user
`@hermes`) participates as a chat partner.

- **Cold start** lands on a centered composer — type or record, and a new
  conversation (a fresh Matrix room, agent invited) starts immediately.
- **Conversations are Matrix rooms**: one room per chat, ChatGPT-style history
  list, auto-titled from the first message. Swipe to delete (leave + forget).
- **Chat view** renders the agent full-width with avatar, your messages as
  bubbles, markdown, typing indicator ("thinking" dots), streamed message
  edits, read receipts, and back-pagination.
- **Voice messages** (MSC3245): record AAC voice notes with a live-metered
  waveform from the chat composer or the home screen; playable audio bubbles
  for both sides.
- **Voice calls** via Element Call embedded in a WKWebView, driven by the
  Matrix Rust SDK widget driver (Element X architecture). LiveKit backend is
  discovered from the homeserver's `.well-known`.
- **Hardware keyboards**: Enter sends, Shift+Enter inserts a newline.
- **Theme**: black-green "Umbrella control room" palette with glowing teal
  glass panels and a laser-red accent.

## Stack

| Layer | Choice |
|---|---|
| UI | SwiftUI, iOS 17+, forced dark |
| Matrix | [`matrix-rust-components-swift`](https://github.com/matrix-org/matrix-rust-components-swift) (`MatrixRustSDK`, pinned exact version) |
| Sync | Simplified sliding sync (native, MSC4186) |
| Calls | Element Call widget in WKWebView + MatrixRTC/LiveKit |
| Project | [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `project.yml` is the source of truth |

The app is written mac-ready (no UIKit imports outside `#if os(iOS)`,
portable Keychain/file paths); a native macOS target is a planned follow-up.

## Building

```sh
brew install xcodegen
xcodegen generate
open RedQueen.xcodeproj   # or:
xcodebuild -scheme RedQueen -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Simulator builds need no signing. Device installs require a development team
in `project.yml` (`DEVELOPMENT_TEAM`).

Tests: `xcodebuild -scheme RedQueen -destination '…' test`.

## Configuration

Defaults live in `RedQueen/Support/AppConfig.swift`:

- **Homeserver**: `https://matrix.roesrath-kleineichen.de` (login screen is
  pre-filled; the server's true `server_name` is `matrix.roesrath-kleineichen.de`).
- **Agent**: defaults to `@hermes:` + your own homeserver domain; override in
  Settings.
- **Element Call**: defaults to `https://call.element.io`; override in
  Settings (e.g. for a self-hosted deployment).
- New agent rooms are created **unencrypted** (`encryptNewConversations`)
  until the agent's E2EE support is confirmed.

## Server-side expectations

- Synapse with simplified sliding sync (any recent version).
- The agent must **auto-accept room invites**, or new chats stay unanswered.
- Typing indicators from the agent power the "thinking" animation — the agent
  should send (and refresh) `m.typing` while it works.
- For calls: `.well-known` advertises the LiveKit RTC focus
  (`org.matrix.msc4143.rtc_foci`), and the agent must join the MatrixRTC
  session for two-way audio.

## Project layout

```
RedQueen/
├── App/            # entry point, session lifecycle, navigation shell
├── Auth/           # login, keychain session persistence
├── Conversations/  # home composer, room list, new-chat service
├── Chat/           # timeline, bubbles, composer, voice recorder/player
├── Call/           # Element Call widget (model, webview bridge, screen)
├── Settings/
└── Support/        # AppConfig, theme
```

## Roadmap

- Push notifications (Sygnal + Notification Service Extension)
- Native macOS target
- Agent-side niceties: transcript-based titles for voice-started chats
