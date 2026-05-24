
# Functional Specification & High-Level Architecture

**Project Title:** MindCorder (Zero-Friction Thought Capture & AI Summary App)  
**Target Platform:** Pebble Time 2 (Emery) / Pebble Round 2 (Gabbro) & Android Companion App  
**Document Version:** 3.0 (Alloy SDK, PebbleKit Android 2, Titles-on-Watch, Android-Only)


## 1. Executive Summary & Core Value Proposition

MindCorder is an ambient, zero-friction audio memo capture tool designed specifically for the unique physical advantages of the new Pebble watches (Time 2 and Round 2). Unlike modern smartwatches that suffer from "battery anxiety," the Pebble's 2-week battery life and high-density, low-power e-paper screen allow users to offload unstructured audio logging and ambient thoughts directly from the wrist without constant screen wake or charging management.

The software utilizes a dual-device pipeline: low-overhead voice capture on-wrist via the Pebble Dictation API (Alloy SDK / JavaScript), paired with robust, local-first machine learning synthesis on an Android smartphone. The watch acts as an input/output terminal — storing only note titles and metadata — while the phone serves as the central engine for AI processing, full-text storage, and detailed reading.

**iOS support is deferred to a post-MVP track.** Phase 1-3 targets Android only.


## 2. User Experience & Core Workflows

### Phase 1: Local-First Workflow

```
[Wrist Action]                     [Dictation UI]               [Haptic Pulse]
Button press  --------------->   "Listening..." (Capture) ---> Processing (Vibe)
|
[Title List on Watch]              [Phone Processing]                  v
Select Title --> Fetch Body <--   Gemini Nano / Cloud AI <-- Send Text via AppMessage
```

1. **Initiation:** The user presses the **Select** hardware button on the watch to launch the app directly into voice capture.
2. **Capture:** The watch activates the microphone using the Alloy Dictation API. The screen shows a low-energy recording graphic. The user speaks unfiltered, unstructured stream-of-consciousness thoughts (~30–60 seconds per session, enforced by Pebble's server-side transcription limits).
3. **Transmission:** The converted text block streams automatically over Bluetooth to the smartphone companion app using AppMessage (via PebbleKit Android 2 — no PKJS).
4. **Local Synthesis:** The companion app processes the text on-device using Android AICore (Gemini Nano) or falls back to cloud AI if unavailable.
5. **Feedback Loop:** Once synthesized, the phone pushes the structured summary back to the watch. The watch emits a double haptic pulse to alert the user without requiring them to look down.
6. **Review:** The user glances at the 200 DPI circular display to read clean bullet points formatted from their raw rambling. Note titles are cached on the watch for offline browsing; full content is fetched from the phone on demand.

### Phase 2: Power User Expansion (BYOK)

Adds a settings screen inside the mobile companion app:
* **Model Router:** Toggle from "On-Device (Free / Gemini Nano)" to "Cloud API (Custom Key)". Users paste an API key for Anthropic, OpenAI, OpenRouter, Google Gemini Cloud, or OpenCode (Zen/Go). This unlocks massive context windows, deep reasoning, multi-language translation formatting, and custom system instruction templates.
* **Cloud Fallback:** When Gemini Nano is unavailable (older Android devices), the app automatically routes to the configured cloud provider.


## 3. High-Level System Architecture

The architecture enforces strict separation of concerns: the watch functions as an input/output terminal, while the phone acts as the central engine.

**Critical constraint:** Per Pebble documentation, *"PebbleKit JS cannot be used in conjunction with PebbleKit Android or PebbleKit iOS."* Therefore, the watch app has **no PKJS** — messages route directly to the companion app via PebbleKit Android 2.

```

+-----------------------------------------------------------------------------------+
|                     PEBBLE TIME 2 / ROUND 2 (Wrist App)                           |
|                                                                                   |
|  +---------------------+      +---------------------+      +-------------------+  |
|  |   Dictation API     | ---> |   AppMessage API    | ---> |  Poco Canvas UI   |  |
|  |  (Alloy / JS)       |      |  (no PKJS)          |      |  (260x260 Circular)| |
|  +---------------------+      +---------------------+      +-------------------+  |
|         |                                                              |          |
|         v                                                              v          |
|  +---------------------+                                      +----------------+  |
|  |  File Storage       |                                      |  Title Cache   |  |
|  |  (note metadata)    |                                      |  (offline nav) |  |
|  +---------------------+                                      +----------------+  |
+------------------------------------------|----------------------------------------+
| Bluetooth (AppMessage → PebbleKit Android 2 → MethodChannel)
v
+-----------------------------------------------------------------------------------+
|                        SMARTPHONE COMPANION (Flutter App)                         |
|                                                                                   |
|     +-----------------------------------------------------------------------+     |
|     |              PebbleKit Android 2 (Bound Service IPC)                  |     |
|     |  BasePebbleListenerService → MethodChannel → CommunicationService   |     |
|     +-----------------------------------------------------------------------+     |
|                                |                                                  |
|                                v                                                  |
|     +-----------------------------------------------------------------------+     |
|     |                         AI Orchestration Router                       |     |
|     +-----------------------------------------------------------------------+     |
|                                |                                 |                |
|               (Phase 1)        v               (Phase 2 Toggle)  v                |
|        +-------------------------------+       +--------------------------------+ |
|        |      On-Device Inference      |       |        Cloud AI Pipeline       | |
|        | ----------------------------- |       | ------------------------------ | |
|        | - Android: AICore/Gemini Nano |       | - User-Supplied Keys (BYOK)    | |
|        |   (gemini_nano_android pkg)   |       | - OpenAI / Anthropic / Gemini  | |
|        |   behind AIService interface  |       | - OpenCode (Zen / Go)          | |
|        +-------------------------------+       +--------------------------------+ |
|                                |                                 |                |
|                                +---------------+-----------------+                |
|                                                |                                  |
|                                                v                                  |
|                                   +--------------------------+                    |
|                                   |  Markdown Output Parser  |                    |
|                                   |  (JSON → title + body)   |                    |
|                                   |  (strip MD for watch)    |                    |
|                                   +--------------------------+                    |
|                                                |                                  |
|                                                v                                  |
|                                   +--------------------------+                    |
|                                   |  Drift SQLite Database   |                    |
|                                   |  (full notes storage)    |                    |
|                                   +--------------------------+                    |
+-----------------------------------------------------------------------------------+


### Component Breakdown

#### A. Watch Layer (Alloy SDK / JavaScript)
* **Dictation API**: Native C bridge (`src/c/dictation.c`) wrapping Pebble OS dictation (`dictation_session` C API), exposed to JS via an XS native module. The JS wrapper (`src/embeddedjs/dictation.js`) provides the same class-based API: `new Dictation({onReadable, onError})` with `.start()` and `.read()`. Requires user confirmation on-screen (via physical Select button) per native Pebble dictation constraints. Practical session timeout is ~30-60 seconds.
* **Vibes API**: Native C bridge (`src/c/vibes.c`) wrapping Pebble OS vibration (`vibes_double_pulse`, etc.), exposed to JS as a static class: `Vibes.doublePulse()`, `.shortPulse()`, `.longPulse()`.
* **AppMessage (no PKJS)**: Alloy's `Message` class handles watch-phone communication. Watch `package.json` includes `companionApp.android` section so Pebble routes messages directly to the companion app. **No `src/pkjs/index.js` is present.**
* **Title-Only Storage**: The watch stores note metadata (ID, title, timestamp, pin/archive flags) as JSON files via Pebble's `embedded:storage/files` module (the `"device"` alias is not available on Pebble; use the underlying module path directly). Full note content lives on the phone. When a user selects a note title on the watch, the watch sends the note ID to the phone, which responds with the full pre-formatted plain text body. The most-recently-viewed note body is cached locally for offline access.
* **Poco Canvas UI**: Procedural canvas-based UI using `commodetto/Poco`. Handles circular layout manually with custom calculations for 260×260 round displays (Gabbro). Supports touchscreen input on Emery and Gabbro.
* **Markdown**: The watch does NOT parse Markdown. The phone strips Markdown to plain text before sending. The watch receives pre-formatted text with explicit line breaks and bullet characters.

#### B. Mobile Orchestration Layer (Flutter — Android)
* **Communication Interface**: Receives incoming text from the watch via PebbleKit Android 2 (`BasePebbleListenerService` → MethodChannel). Sends summaries back to the watch via `DefaultPebbleSender`. Bound Service IPC keeps the app awake while the watch app is running.
* **Inference Pipeline (Phase 1 - Local-First):**
  * **Android**: Uses `gemini_nano_android` package (wraps AICore via ML Kit) behind an abstract `AIService` interface for easy swapping. Feeds raw dictation payload into Gemini Nano alongside a static system prompt.
* **Inference Pipeline (Phase 2 - Cloud BYOK):**
  * Reads API key + provider config from `flutter_secure_storage`.
  * Supports: OpenAI-compatible endpoint (OpenRouter, OpenAI, OpenCode Zen/Go), Anthropic (separate schema), Google Gemini Cloud, Custom (user-defined base URL + model ID).
  * System prompt returns JSON with `title` and `body` fields. Parser validates and falls back gracefully if model returns non-JSON.
* **Data Layer**: Drift (SQLite) with code generation via `build_runner`. Type-safe queries for note CRUD operations. Schema versioning from day one.

#### C. PebbleKit Android 2 Bridge
* **What it is**: A modern Kotlin library (`io.rebble.pebblekit2:client:1.1.0`) from the official Pebble project (`pebble-dev` org). Apache-2.0 license. Actively maintained (64 commits, latest Apr 2026).
* **How it works**:
  - **Receiving**: `BasePebbleListenerService` (a Bound Service) receives AppMessages from the watch. Overrides `onMessageReceived()` to parse `PebbleDictionary` and forward to Flutter via MethodChannel. Sends ACK to Pebble to prevent timeouts.
  - **Sending**: `DefaultPebbleSender` sends data to the watch via `sendDataToPebble()` (suspending function, called from coroutines).
  - **IPC**: Uses Bound Services (not Broadcast Intents) — the Pebble app binds to the companion app's service, keeping it awake while the watch app is running. Solves Android's background processing restrictions.
  - **Watch-side config**: `package.json` includes `companionApp.android` with the companion app's package name. Pebble routes messages to the first matching installed package.
* **Embedded in Flutter**: Kotlin code lives in the Flutter plugin's `android/` directory. Dart communicates via MethodChannel (outgoing) and EventChannel (incoming stream).


## 4. Technical Constraints & Mitigations

| Hardware / SDK Reality | App Strategy / Mitigation |
| :--- | :--- |
| **Dictation Timeout Window**<br>The Pebble Dictation engine cuts off automatically after several seconds of silence and sends audio to Pebble's servers for transcription. Practical limit is ~30–60 seconds per session. | The mobile app processes each chunk immediately when the session terminates. Users can immediately trigger an "append session" via a single button tap to continue dictation. |
| **AppMessage Payload Limits**<br>Bluetooth buffers have explicit limits. While Emery/Gabbro support larger buffers, the watch's JS heap is highly constrained. Maximum chunk size is limited to 2KB (2048 bytes) to prevent watch-side heap fragmentation and OOM crashes. | Large text sent from phone to watch is split into numbered chunks of max 2KB by the companion app. The watch reassembles segments as raw bytes (using an ArrayBuffer) before converting to string. Timeout of 10 seconds between chunks prevents hung transfers. `CHUNK_RESET` command aborts failed transfers. |
| **Alloy SDK Limited to Emery/Gabbro**<br>Alloy (JavaScript SDK) only supports Pebble Time 2 and Round 2. Older Pebbles (Classic, Time, Time Round) cannot run Alloy apps. | Target only Emery and Gabbro. Development and testing uses emulators (`pebble install --emulator emery` / `--emulator gabbro`) until physical devices are available. |
| **PebbleKit JS and PebbleKit Android are mutually exclusive**<br>Per Pebble docs: "PebbleKit JS cannot be used in conjunction with PebbleKit Android or PebbleKit iOS." | Watch app has no `src/pkjs/index.js`. Messages route directly to companion app via PebbleKit Android 2. |
| **Gemini Nano Android-Only**<br>AICore / Gemini Nano is only available on select Android devices (Pixel 8+, some Samsung). iOS has no equivalent on-device model. | iOS deferred to post-MVP. Android checks for AICore availability at startup; if unavailable, routes to cloud providers. |
| **No Native Background Local LLM on Old Phones**<br>Older Android devices don't have AICore or Gemini Nano hardware enablement. | The companion app checks for system hardware features during first run. If local models are absent, the app routes to cloud providers (Phase 2 functionality). |
| **Watch Storage Constraints**<br>While Alloy's file system removes the 256-byte C SDK persist limit, watch storage is still finite. | Store only titles + metadata on watch. Full content lives on phone. Cache only the most-recently-viewed note body; evict older cached bodies. |
| **Bluetooth Message Duplication**<br>AppMessage can deliver the same message twice due to ACK/NACK ambiguity. | Monotonic `MSG_ID` counter on every message. Both watch and phone track last processed ID and silently drop duplicates. |
| **Dictation & Vibes Not in Moddable Pebble Platform**<br>The Pebble Moddable platform does not include JS wrappers for dictation or vibes. The standard `import ... from "pebble/dictation"` pattern fails with "import default not found." | Implement native C bridges (`src/c/dictation.c`, `src/c/vibes.c`) following the pattern of the existing `pebble/button` module in the SDK. C code wraps Pebble OS APIs; JS wrappers provide the standard class-based API surface. |
| **File I/O Module Path**<br>The `"device"` module alias (common in standard Moddable projects) is not available on Pebble. The `import device from "device"` pattern fails. | Import directly from the underlying module: `import files from "embedded:storage/files"` for file I/O. Use `embedded:storage/key-value` for key-value storage if needed. |


## 5. Message Protocol

### Handshake & Session Sync
To avoid deadlock or duplicate lockout on reboots/reinstalls, the watch and companion app perform a startup handshake using **COMMAND=0**.
- **SESSION_ID**: Epoch timestamp (`Date.now()`) of session start. Both devices track the active `SESSION_ID`. If a new session ID is received, expected message counters are reset to synchronize states.

### Watch → Phone

| COMMAND | Fields | Description |
|---------|--------|-------------|
| 0 | `SESSION_ID`, `MSG_ID` | Handshake sync initiation |
| 1 | `RAW_TEXT`, `NOTE_ID`, `MSG_ID`, `SESSION_ID` | New dictation result |
| 2 | `NOTE_ID`, `MSG_ID`, `SESSION_ID` | Fetch note body by ID |

### Phone → Watch

| COMMAND | Fields | Description |
|---------|--------|-------------|
| 0 | `SESSION_ID`, `MSG_ID` | Handshake sync ACK |
| 10 | `TITLE`, `MSG_ID`, `SESSION_ID` | Summary title (sent when processing starts) |
| 11 | `SUMMARY_CHUNK`, `CHUNK_INDEX`, `CHUNK_TOTAL`, `MSG_ID`, `SESSION_ID` | Summary body chunk (max 2KB) |
| 12 | `COMPLETE`, `MSG_ID`, `SESSION_ID` | Transfer complete |
| 13 | `CHUNK_RESET`, `SESSION_ID` | Abort current transfer |
| 14 | `TITLE`, `BODY`, `MSG_ID`, `SESSION_ID` | Full note response (single message, fits in 2KB) |

### Deduplication & Synchronization

- Every message includes `MSG_ID` (monotonic counter) and `SESSION_ID`.
- Receiver tracks the last processed `SESSION_ID` and `lastIncomingMsgId`.
- If the incoming message has a *newer* `SESSION_ID`, the receiver updates its tracked `SESSION_ID`, resets its `lastIncomingMsgId` baseline, and processes the message.
- If the incoming message has the *same* `SESSION_ID` but `MSG_ID <= lastIncomingMsgId`, it is dropped as a duplicate.
- Phone tracks `lastProcessedNoteId` to drop duplicate `RAW_TEXT` uploads with the same `NOTE_ID`.
