# Dev

A macOS menu-bar kit for developer tools. Fast, native, no dock icon.

The first tool is **Dictate**: hold a hotkey, speak, release, and the transcript is pasted into the frontmost app. It streams to [Muse Voice Transcribe](https://ai.developer.meta.com/docs/speech-to-text) over the realtime WebSocket. Other speech providers can be added later without rewriting the capture or overlay.

## Use it

1. Open `Dev.xcodeproj` (or `make open`) and run the `Dev` scheme.
2. Click the waveform in the menu bar → **Settings…**
3. Paste a Meta Model API key from [ai.developer.meta.com](https://ai.developer.meta.com/).
4. From the repo run `make run`. That installs `/Applications/Dev.app`.
5. Grant **Microphone**, **Input Monitoring**, and **Accessibility** for that app (add it with + if needed). Quit and reopen once.
6. Hold **⌃⌥**, speak, release. Esc cancels. You can also open the menu-bar popover,
   click **Start Dictation**, speak, then click **Stop & Insert**.

Default shortcut is Control + Option. Change it in Settings. If paste is blocked, the transcript is copied instead.

`make run` signs Dev with a local cert and installs `/Applications/Dev.app`. Add **that** copy once in Input Monitoring and Accessibility. Rebuilds keep the same signature, so macOS will not ask again.

## Adding another transcription provider

The dictation loop talks to one protocol:

```swift
protocol TranscriptionProvider {
    var id: String { get }
    var displayName: String { get }
    var sampleRate: Int { get }
    func connect(apiKey: String, options: TranscriptionOptions) async throws -> any TranscriptionStream
}
```

1. Add a type next to `MuseProvider`.
2. Register it in `ProviderRegistry.all`.
3. It shows up in Settings.

Do not introduce a plugin system until a second provider exists.

## Layout

```
Dev/                  menu bar app, settings, permissions
Dev/Dictation/        hotkey, mic, overlay, paste
Dev/Dictation/Transcription/Muse/   Muse WebSocket client
```

More tools should land as sibling folders of `Dictation`, wired from the menu bar. Keep each tool small.

## Muse notes

- Endpoint: `wss://api.meta.ai/v1/asr/realtime`
- Handshake JSON carries `authorization.accessToken` (`Bearer …`). The HTTP `Authorization` header is ignored.
- Audio is raw PCM: signed 16-bit little-endian, mono, 24 kHz, ~80 ms frames.
- Mode is `PUSH_TO_TALK`. Release sends `{"type":"endStream"}` and waits for `final: true`.
