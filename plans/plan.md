# MindCorder — Implementation Plan (Alloy SDK + PebbleKit Android 2)

## Architecture Overview

**Watch app:** JavaScript via Alloy SDK (Moddable/XS engine), targeting Emery (Pebble Time 2) and Gabbro (Pebble Round 2). Uses Piu UI framework, file-based storage, and the `Message` API for watch-phone communication. **No PKJS** — messages route directly to the companion app via PebbleKit Android 2.

**Companion app:** Flutter (Android only), local-first with Drift SQLite DB. AI summarization via Gemini Nano (on-device, Android only) with cloud BYOK fallback. Communicates with the watch through **PebbleKit Android 2** embedded in a Flutter plugin (Kotlin native code).

**Key design decision:** The watch stores only note titles + metadata (ID, timestamp, pin/archive flags). Full note content lives on the phone. When a user selects a note on the watch, the watch sends the note ID to the phone, which responds with the full pre-formatted text body. The most-recently-viewed note is cached locally on the watch for offline access.

**Communication model:** Per Pebble documentation, *"PebbleKit JS cannot be used in conjunction with PebbleKit Android or PebbleKit iOS."* Therefore:
- Watch app has **no** `src/pkjs/index.js` (or the file is absent)
- Watch `package.json` includes a `companionApp.android` section with the Flutter app's package name
- Messages route directly: Watch → Pebble Bluetooth → PebbleKit Android 2 → Flutter (via MethodChannel)
- PebbleKit Android 2 uses Bound Services for IPC, keeping the companion app awake while the watch app is running

---

## Phase 1: Pebble Watch App (Alloy / JavaScript)

**Goal:** A watch app that captures dictation, sends text over AppMessage to the companion app, receives and displays pre-formatted summaries, and caches note titles locally. Testable with a mock data layer (simulated phone responses).

### 1.1 Project Scaffolding
- [x] Initialize Alloy project with `pebble new-project --alloy mindcorder`
  - Project auto-generated at `mindcorder/` then moved to `watch/`
- [x] Configure `package.json` with UUID `E2ECDBEB-2D2B-412F-AD1D-9059180EBC47`
- [x] Updated `messageKeys` and `companionApp.android` section
- [x] Set `watchapp.watchface` to `false`
- [x] `targetPlatforms`: `["emery", "gabbro"]`
- [x] Project structure (actual):
  ```
  watch/
    src/
      embeddedjs/
        main.js              # App entry point (Poco rendering)
        manifest.json        # Module declarations
        state.js             # State machine
        dictation.js         # Dictation session management
        messages.js          # Message sending/receiving
        storage.js           # Note title file storage
        chunk.js             # Chunk reassembly logic
    package.json             # App manifest
    wscript                  # Pebble C build (modified — no PKJS)
  ```
- [x] **No `src/pkjs/index.js`** — removed during scaffold
- [x] **No `ui/` directory** — Poco renders directly in `main.js` (see Piu incompatibility below)
- [x] Build toolchain verified: `pebble build` passes for emery and gabbro

**Key architectural decision:** Piu UI framework **cannot be used** with Pebble's mod build. The `manifest_piu.json` include pulls in native C modules (e.g., `piuColumn.c`, `piuDie.c`) that the Pebble mod build system rejects with "mod cannot contain native code." **Poco** (`commodetto/Poco`) is used instead for all rendering. Screen rendering is procedural in `main.js` rather than separate Piu container modules.

### 1.2 AppMessage Communication Layer
- [ ] **Watch side** (`embeddedjs/messages.js`):
  - Import `Message` from `pebble/message`
  - Create `Message` instance with all keys from `package.json`
  - Register callbacks:
    - `onWritable()`: connection ready, can send messages
    - `onSuspend()`: connection lost, set internal `connected = false` flag
    - `onReadable()`: process incoming messages from companion app
  - Maintain a monotonic `outgoingMsgId` counter — attach `MSG_ID` and `SESSION_ID` to every outgoing message.
  - **Handshake Protocol:** Implement startup handshake using `COMMAND=0` (Handshake). On startup, the watch sends its active `SESSION_ID` and `lastIncomingMsgId`. The companion app responds with a Handshake ACK containing the current `SESSION_ID`. If the session ID matches, expected counters are aligned. If a newer `SESSION_ID` is received (due to app reinstall), Baselines are synchronized.
  - Track `lastIncomingMsgId` — silently drop duplicate messages where `MSG_ID <= lastIncomingMsgId` under the same `SESSION_ID`.
- [ ] **Message protocol** (watch → phone):
  - `COMMAND=0` + `SESSION_ID` + `MSG_ID` + `LAST_INCOMING_MSG_ID`: Handshake sync
  - `COMMAND=1` + `RAW_TEXT` + `NOTE_ID` + `MSG_ID` + `SESSION_ID`: New dictation result
  - `COMMAND=2` + `NOTE_ID` + `MSG_ID` + `SESSION_ID`: Fetch note body by ID
- [ ] **Message protocol** (phone → watch):
  - `COMMAND=0` + `SESSION_ID` + `MSG_ID`: Handshake sync ACK
  - `COMMAND=10` + `TITLE` + `MSG_ID` + `SESSION_ID`: Summary title (sent immediately when phone starts processing)
  - `COMMAND=11` + `SUMMARY_CHUNK` + `CHUNK_INDEX` + `CHUNK_TOTAL` + `MSG_ID` + `SESSION_ID`: Summary body chunk (max 2KB)
  - `COMMAND=12` + `COMPLETE` + `MSG_ID` + `SESSION_ID`: Transfer complete
  - `COMMAND=13` + `CHUNK_RESET` + `SESSION_ID`: Abort current transfer, clear reassembly buffer
  - `COMMAND=14` + `TITLE` + `BODY` + `MSG_ID` + `SESSION_ID`: Full note response (for FETCH_NOTE, when body fits in single 2KB message)
- [ ] **Chunk reassembly** (`embeddedjs/chunk.js`):
  - Maintain reassembly state: `{ chunks: [], expectedTotal: null, nextIndex: 0, msgId: null, sessionId: null }`
  - On receive chunk: validate `CHUNK_INDEX === nextIndex`, reject duplicates, store in byte array. **Note:** On starting a new reassembly, make sure `main.js` registers a timeout callback using `chunk.setOnTimeoutCallback` so the UI transitions to the `ERROR` state rather than hanging.
  - To prevent Heap Fragmentation and OOM, store chunks as raw bytes (`Uint8Array`) inside a pre-allocated 8KB `ArrayBuffer` and use `.set()` to copy chunk bytes. Only convert to JS String once using `String.fromArrayBuffer()` upon complete transfer.
  - On receive `CHUNK_TOTAL`: validate it matches expected total, reject if inconsistent
  - On receive `CHUNK_RESET`: clear all state, return to idle
  - On receive `COMPLETE`: verify all chunks received, convert array buffer to full string, clear state
  - Timeout: 10 seconds between chunks — on timeout, clear state, call the registered timeout callback which transitions the app state to `ERROR` state with message "Transfer failed — tap to retry"
  - Maximum total payload: guard against buffer overflow — if `CHUNK_TOTAL * 2048 > 8192` bytes, reject and request reset

### 1.3 Dictation Session
- [x] **Alloy dictation API verified** (see `DEV_NOTES.md` for full details). Source: [hellodictation example](https://github.com/Moddable-OpenSource/pebble-examples/tree/main/hellodictation).
  - `import Dictation from "pebble/dictation"` — native Alloy module, no C SDK fallback needed
  - Constructor: `new Dictation({ onReadable() { this.read() }, onError(e) { ... } })`
  - `this.read()` returns transcribed text string
  - `dt.start()` begins dictation session
  - ⚠️ **Confirmation dialog**: Alloy API does NOT expose `enable_confirmation()` — user must press Select to confirm each transcription. UX designed around this (adds one button press per session).
  - ⚠️ **Error dialogs**: Unknown if Alloy supports disabling these. Handle in our UI regardless.
  - ⚠️ **Error codes**: `onError(e)` receives an error value, but code names/values are unknown. Discover during testing.
  - ⚠️ **Buffer size**: Alloy constructor takes only a config object — buffer size handled internally (likely unlimited).
- [ ] Create dictation session on app launch (or lazily on first button press)
- [ ] Callback: on `onReadable()`, generate unique `NOTE_ID` (timestamp-based: `Date.now()`), send `COMMAND=1` + `RAW_TEXT` + `NOTE_ID` + `MSG_ID` via `message.write()`
- [ ] Handle callbacks:
  - `onReadable()` → transcription success → send text to phone, transition to `PROCESSING`
  - `onError(e)` → show error message based on error value, transition to `IDLE`
    - No speech detected → "No speech detected"
    - Connectivity error → "Phone not connected"
    - System aborted → "Try again"
    - Internal error / recognizer error → "Error, try again"
    - Transcription rejected → silently return to `IDLE`

### 1.4 State Machine
- [ ] States and transitions (`embeddedjs/state.js`):
  ```
  IDLE
    → Select press → LISTENING (start dictation)
    → Up/Down press → NOTELIST (browse cached titles)

  LISTENING
    → Dictation success → PROCESSING (send text, wait for phone)
    → Dictation error → IDLE (show error message)
    → Long-press Select → IDLE (user cancel)

  PROCESSING
    → Title received (COMMAND=10) → PROCESSING (update UI with title)
    → Chunks received → PROCESSING (reassemble)
    → Complete received (COMMAND=12) → SUMMARY_READY (display summary, cache title)
    → Chunk timeout → ERROR ("Transfer failed — tap to retry")
    → Phone disconnected → ERROR ("Phone disconnected")
    → Long-press Select → IDLE (user cancel, abort processing)

  SUMMARY_READY
    → Select press → IDLE (ready for next note)
    → Up/Down press → NOTELIST (browse other notes)

  NOTELIST
    → Title selected → FETCHING (send FETCH_NOTE to phone)
    → Back press → IDLE

  FETCHING
    → Note body received (COMMAND=14 or chunks) → SUMMARY_READY (display cached body)
    → Timeout (10s no response) → ERROR ("Phone not responding")
    → Phone disconnected → SUMMARY_READY (show cached body if available, else ERROR)

  ERROR
    → Select press → IDLE (dismiss error)
    → Long-press Select → IDLE (dismiss error)
  ```
- [ ] Visual feedback per state:
  - `IDLE`: "Tap to record" with app icon
  - `LISTENING`: "Listening..." with animated recording indicator
  - `PROCESSING`: "Processing..." with spinner; show title when received
  - `SUMMARY_READY`: Title at top, body text below
  - `NOTELIST`: Scrollable list of titles with timestamps
  - `FETCHING`: "Loading..." with spinner
  - `ERROR`: Error message with "Tap to dismiss"

### 1.5 UI with Poco Framework
- [ ] Render UI screens procedurally in `main.js` (and optionally sub-modules) using `commodetto/Poco` canvas drawing.
- [ ] Implement screen rendering functions:
  - **Idle screen**: Centered text "MindCorder" (Leco font), subtitle "Tap to record", and connection status dot (green if connected, gray if disconnected).
  - **Listening screen**: Red indicator shape that flashes/pulses (using a `Timer.repeat` animation loop), and "Listening..." text.
  - **Processing screen**: "Processing..." text and the summary title (bold font) once received from the companion app.
  - **Summary screen**: Note title bolded at the top, followed by multi-line body text. Since there's no Markdown parsing on-watch, render plain text with explicit line breaks and bullet points.
  - **Note list screen**: Scrollable list of titles with date/timestamp, responding to Up/Down hardware button presses.
- [ ] Circular-aware layout: Calculate coordinates manually with padding (e.g. `PADDING = 20`) to keep all text and shapes safe inside the Gabbro circular boundary (260×260).
- [ ] Touch support: Support touchscreen scroll/tap actions on Emery and Gabbro.
- [ ] On summary receipt: Call `Vibes.doublePulse()` (imported from `pebble/vibes`).
- [ ] **Markdown handling:** The companion app on the phone strips Markdown to plain text before sending. The watch receives pre-formatted text with explicit line breaks and bullet characters (•). The watch does NOT parse Markdown.

### 1.6 Note Title Storage (File-Based)
- [ ] Import file system API (`device.files`)
- [ ] Store note metadata as JSON files:
  ```
  /notes/
    index.json           // { "noteIds": [1700000003, 1700000002, 1700000001], "version": 1 }
    1700000003.meta.json // { "id": 1700000003, "title": "Meeting notes", "timestamp": 1700000003, "isPinned": false, "isArchived": false }
    1700000003.body.txt  // Cached body text (plain text, pre-formatted) — only for most-recently-viewed note
  ```
- [ ] `index.json` maintains ordered list of note IDs (most recent first)
- [ ] On startup: read `index.json`, populate in-memory list for navigation
- [ ] On new summary received:
  - Write/update `<note_id>.meta.json` with title, timestamp, flags
  - Add ID to `index.json` (prepend to front, maintain order)
  - Write body to `<note_id>.body.txt` (this is the summary just received)
- [ ] On note title selected (FETCH_NOTE flow):
  - Check if `<note_id>.body.txt` exists locally → display immediately (offline)
  - If not cached: send `COMMAND=2` + `NOTE_ID` to phone → wait for response → cache body → display
- [ ] Cache eviction: when a new note body is cached, delete the previous cached body file. Only one body file exists at a time.
- [ ] Note ID generation: watch generates IDs using `Date.now()` (millisecond timestamp). This is deterministic, collision-resistant (assuming one note per ms), and survives app reinstalls. Phone stores this as `watch_id` in Drift DB.

### 1.7 Connection Status Handling
- [ ] Import `watch` from `pebble/watch` for connection monitoring
- [ ] Listen for `watch.connected` events:
  - `watch.connected.app`: Pebble mobile app connected
  - `watch.connected.pebblekit`: Companion app ready for messaging (this is the key flag — true when PebbleKit Android 2 service is bound)
- [ ] Show connection status in idle screen (small indicator: green dot = connected, gray dot = disconnected)
- [ ] When disconnected during `PROCESSING` or `FETCHING`: transition to `ERROR` state
- [ ] When `onSuspend` fires: set `connected = false`, update UI indicator
- [ ] When reconnected after disconnection: check for queued outgoing messages, send them

### 1.8 Testing (Watch App Only)

**See the simplified testing strategy in the [Test Automation Strategy](#test-automation-strategy) section.**

Phase 1 tests cover:
- [ ] **Core Logic Unit Tests** (Node.js): `state.js`, `chunk.js`, `dictation.js` error mapping. We focus unit testing on the core logic and sequence, avoiding complex rendering mocks of `Poco` or other native layers.
- [ ] **Emulator Smoke Tests** (Manual + Logs): Build and install on the emery and gabbro emulators. Verify screens, layout, state transitions, and connection indicators using Pebble console logs (`pebble logs`).

Run commands:
```bash
# Run logic unit tests
node watch/test/logic_runner.js

# Install on emulator
pebble install --emulator emery
pebble install --emulator gabbro
```

**Exit criteria:**
- **Unit gate:** All ~55 unit tests pass on Node.js runner and XS engine (mcrun)
- **Emulator gate:** Watch app UI renders correctly on both emery and gabbro emulators. State machine handles all transitions. Chunk reassembly passes all test cases. Note title storage works (read/write/cache eviction). Dictation error mapping covers all known error types.
- **Real-device gate (can be deferred to Phase 3):** Watch connects to phone via PebbleKit Android 2. Dictation text reaches companion app. Summary returns and displays. Note titles cache and navigate offline.

**Files to create:**
- `watch/test/runner.js` — test runner entry point
- `watch/test/utils.js` — assertion helpers
- `watch/test/mocks/*.js` — mock Pebble API implementations (8 mocks)
- `watch/test/unit/*.test.js` — unit test files (5 modules)

---

## Phase 2: Flutter Companion App — Foundation + AI Pipeline

**Goal:** A Flutter app with local DB, AI summarization (Gemini Nano or BYOK), and full UI. Testable entirely without the watch — feed text manually.

### 2.1 Project Setup
- [ ] `flutter create mindcorder_companion --org com.mindcorder`
- [ ] Dependencies:
  ```yaml
  dependencies:
    flutter:
      sdk: flutter
    drift: ^2.33.0
    drift_flutter: ^0.3.1-wip
    sqlite3_flutter_libs: ^0.5.18
    flutter_secure_storage: ^9.2.2
    http: ^1.3.0
    flutter_markdown: ^0.7.0
    gemini_nano_android: ^1.1.3  # On-device AI (Android only)
    provider: ^6.1.2             # State management
    go_router: ^14.3.0           # Navigation

  dev_dependencies:
    flutter_test:
      sdk: flutter
    flutter_lints: ^5.0.0
    drift_dev: ^2.33.0
    build_runner: ^2.15.0
  ```
- [ ] Platform setup:
  - Android: `minSdk 26` (required for AICore), Kotlin enabled
  - Add PebbleKit Android 2 dependency to `android/app/build.gradle.kts`:
    ```kotlin
    implementation("io.rebble.pebblekit2:client:1.1.0")
    implementation("io.rebble.pebblekit2:client-ui:1.1.0") // optional, for permission dialog
    ```
- [ ] Run `dart run build_runner build` to generate Drift code

### 2.2 Data Model (Drift)
- [ ] Table `Notes` defined using Drift Dart DSL:
  ```dart
  class Notes extends Table {
    IntColumn get id => integer().autoIncrement()();
    IntColumn get watchId => integer().nullable()(); // Matches watch-side note ID (timestamp)
    DateTimeColumn get createdAt => dateTime()();
    TextColumn get rawText => text()();
    TextColumn get summaryTitle => text().nullable()(); // Null until AI processes
    TextColumn get summaryBody => text().nullable()(); // Null until AI processes
    TextColumn get bodyPlainText => text().nullable()(); // Pre-formatted plain text for watch
    BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
    BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
    TextColumn get aiProvider => text().nullable()(); // nano, openai, anthropic, etc.
    TextColumn get processingStatus => text().withDefault(const Constant('pending'))(); // pending, processing, completed, failed
  }
  ```
- [ ] Schema versioning: start with `schemaVersion: 1`, include `migration` strategy from the start. When schema changes in future phases, use Drift's `onUpgrade` callback.
- [ ] DAO queries:
  - `allNotes()`: SELECT all, ordered by `created_at DESC`, `is_pinned` first
  - `insertNote()`: INSERT, return generated `id`
  - `updateSummary()`: UPDATE `summary_title`, `summary_body`, `body_plain_text`, `ai_provider`, `processing_status` by `id`
  - `archiveNote()`: UPDATE `is_archived` by `id`
  - `pinNote()`: UPDATE `is_pinned` by `id`
  - `getNoteById()`: SELECT by `id`
  - `getNoteByWatchId()`: SELECT by `watch_id`
  - `getPendingNotes()`: SELECT where `processing_status = 'pending'`
- [ ] Use Drift's code generation (`@DriftDatabase` annotation + `build_runner`)

### 2.3 AI Orchestration Router
- [ ] **Abstract `AIService` interface** (mitigates `gemini_nano_android` package risk):
  ```dart
  abstract class AIService {
    Future<SummaryResult> summarize(String rawText);
    Future<bool> isAvailable();
  }
  ```
  - `GeminiNanoService` implements `AIService` (wraps `gemini_nano_android`)
  - `CloudAIService` implements `AIService` (wraps HTTP calls to cloud providers)
  - Swapping implementations is trivial if the package is abandoned
- [ ] **Capability detection:** On startup:
  - Check `gemini_nano_android.isAvailable()` for Gemini Nano.
  - Model on-device AI state as an explicit three-state enum: `unavailable`, `downloading`, or `ready`. If available but downloading, handle downloading progress gracefully and route early requests to cloud fallback.
  - Read user preference from settings (prefer nano vs. prefer cloud)
- [ ] **Router decision tree:**
  ```
  1. Is user preference set to "cloud only"? → cloudSummarize()
  2. Is Gemini Nano available AND model downloaded (ready)? → nanoSummarize()
     → Set a strict timeout on Gemini Nano processing (e.g. 8 seconds) to prevent freezes.
     → On Nano failure (OOM, context exceeded, timeout) → retry with cloudSummarize()
  3. Nano unavailable or not downloaded (downloading/unavailable) → cloudSummarize()
     → Check if API key is configured
     → If no key → store raw text, set status 'failed', show "Configure API key" prompt
     → If key exists → send request
     → On cloud failure (network, invalid key) → store raw text, set status 'failed'
  4. Both paths fail → queue for retry when connectivity/API key is restored
  ```
- [ ] **Nano path (Android only):**
  - Use `gemini_nano_android` package (wraps AICore via ML Kit)
  - Feed raw text + system prompt → parse response → extract title + body
- [ ] **Cloud fallback (BYOK):**
  - Read API key + provider config from `flutter_secure_storage`
  - Provider implementations:
    - **OpenAI-compatible** (single implementation, configurable base URL): covers OpenRouter, OpenAI, OpenCode Zen, OpenCode Go
    - **Anthropic** (separate handler — different request/response schema)
    - **Google Gemini Cloud** (separate handler)
    - **Custom** (user-defined base URL + model ID, uses OpenAI-compatible schema)
  - System prompt → parse JSON response → extract title + body

### 2.4 System Prompt & Response Parsing
- [ ] Fixed prompt (embedded constant):
  ```
  Format the following messy transcript into a clean, concise summary.
  Return ONLY a valid JSON object wrapped inside <output_json>...</output_json> XML tags with exactly two fields:
  "title": a short descriptive title for the note (max 8 words),
  "body": structured bullet points in Markdown (max 5 bullets, remove filler words, organize key points logically).
  Transcript: """<raw_text>"""
  ```
- [ ] **Robust JSON extractor & parser with validation and fallback:**
  - Standard LLMs (especially Gemini Nano) may wrap JSON in Markdown code fences (e.g., ` ```json ... ``` `) or add conversation prose. Use a regex-based extractor to isolate the content within the outermost curly braces `{ ... }` or within `<output_json>` tags.
  - If model returns valid JSON with `title` and `body` fields → use directly
  - If model returns non-JSON → treat entire response as body, generate title from first sentence or use "Untitled"
  - If JSON is valid but missing `title` → use "Untitled"
  - If JSON is valid but missing `body` → use "No summary generated"
- [ ] **Plain text conversion for watch:**
  - Strip Markdown syntax from `body` before sending to watch
  - Convert `**bold**` → plain text, `*italic*` → plain text
  - Convert `- ` or `* ` bullet markers → `• ` (Unicode bullet character)
  - Convert `# headers` → uppercase text
  - Preserve line breaks
  - Store result in `body_plain_text` column
  - Send `body_plain_text` to watch, not raw Markdown

### 2.5 BYOK Settings UI
- [ ] Preset dropdown: OpenRouter / OpenAI / Anthropic / Google Gemini / OpenCode / Custom
- [ ] Each preset stores: display name, base URL, default model ID
  - OpenRouter: `https://openrouter.ai/api/v1/chat/completions`, model `anthropic/claude-sonnet-4-20250514` (or user's choice)
  - OpenAI: `https://api.openai.com/v1/chat/completions`, model `gpt-4o-mini`
  - Anthropic: `https://api.anthropic.com/v1/messages`, model `claude-sonnet-4-20250514`
  - Google Gemini: `https://generativelanguage.googleapis.com/v1beta/models/`, model `gemini-2.0-flash`
  - OpenCode Zen: base URL + model ID for Zen
  - OpenCode Go: base URL + model ID for Go
  - Custom: user-defined base URL + model ID
- [ ] Key field (masked, with show/hide toggle)
- [ ] "Test Connection" button: sends a short test prompt, shows success/failure with details
- [ ] `flutter_secure_storage` for key + config persistence
- [ ] Advanced toggle: reveal model ID field, custom base URL for "Custom" preset only
- [ ] AI mode toggle: "On-Device (Free)" / "Cloud API" / "Auto (On-Device → Cloud fallback)"

### 2.6 Main UI — Note List
- [ ] ListView sorted by `created_at DESC`, pinned notes first
- [ ] Each row: AI-generated title (or "Untitled — [date]" if not yet summarized), timestamp, processing status indicator
- [ ] Swipe-to-archive
- [ ] Pull-to-refresh
- [ ] FAB for "Add test note manually" (dev-only, or keep for text input alternative)
- [ ] Connection status indicator (watch connected/disconnected)
- [ ] Processing status badges: "Pending", "Processing", "Completed", "Failed"

### 2.7 Note Detail View
- [ ] Title at top in large text
- [ ] Full Markdown body rendered via `flutter_markdown`
- [ ] Metadata: raw transcript collapsed by default (expandable), created_at, AI provider used
- [ ] Actions: archive, pin, delete, retry (if failed)

### 2.8 PebbleKit Android 2 Integration (Embedded Native Bridge)
- [ ] Embed PebbleKit Android 2 and the MethodChannel bridge directly into the companion app's native Android source folder to avoid multi-package plugin complexity:
  ```
  mindcorder_companion/
    android/app/src/main/kotlin/com/mindcorder/app/
      MainActivity.kt            # Registers MethodChannel & EventChannel
      PebbleListenerService.kt   # BasePebbleListenerService implementation
      PebbleMessageHandler.kt    # Translates and processes Pebble dictionaries
    lib/
      src/pebble/
        pebble_bridge.dart         # Dart side of the MethodChannel/EventChannel
        pebble_service.dart        # High-level Pebble communication and queue service
  ```
- [ ] **Kotlin side** (`PebbleListenerService.kt`):
  - Extend `BasePebbleListenerService` from PebbleKit Android 2
  - Override `onMessageReceived(watchappUUID, data, watch)`:
    - Parse `PebbleDictionary` into key-value pairs
    - Forward to Flutter via MethodChannel/EventChannel (`mindcorder/pebble`)
    - Send ACK to Pebble via `PebbleKit.sendAckToPebble()` (required to prevent timeouts)
  - Override `onAppOpened` / `onAppClosed`: forward to Flutter for connection state updates
- [ ] **Kotlin side** (`MainActivity.kt`):
  - Configure the FlutterEngine
  - Register MethodChannel and EventChannel: `mindcorder/pebble`
  - Handle method calls from Dart:
    - `sendToWatch`: receives dictionary data (Map), calls `DefaultPebbleSender().sendDataToPebble()`
    - `startAppOnWatch`: calls `sender.startAppOnTheWatch()`
    - `stopAppOnWatch`: calls `sender.stopAppOnTheWatch()`
    - `isWatchConnected`: returns connection status
- [ ] **Dart side** (`pebble_bridge.dart`):
  - MethodChannel wrapper with typed methods:
    - `sendToWatch(Map<int, dynamic> data)`: sends AppMessage to watch
    - `startAppOnWatch()`: launches watch app from phone
    - `isWatchConnected()`: returns `Future<bool>`
  - EventChannel for incoming messages from Kotlin (stream of AppMessage events)
- [ ] **AndroidManifest.xml** additions:
  ```xml
  <service android:name=".PebbleListenerService"
           android:exported="true"
           tools:ignore="ExportedService">
    <intent-filter>
      <action android:name="io.rebble.pebblekit2.RECEIVE_DATA_FROM_WATCH"/>
    </intent-filter>
  </service>
  ```
- [ ] **Connection management:**
  - `DefaultPebbleSender` lifecycle: create on app start, close on app destroy
  - Bound Service keeps the app awake while watch app is running
  - Handle app backgrounding: sender can remain active via Bound Service

### 2.9 Testing (Companion App Only)

**See full test automation strategy in the [Test Automation Strategy](#test-automation-strategy) section.**

Phase 2 tests cover:

- [ ] **Unit tests** (Dart): AI response parsing, plain text converter, Drift DB operations, AI service orchestration, provider config, settings, queue manager, communication protocol — ~65 tests total
- [ ] **Widget tests** (Flutter): Note list, note detail, settings page, BYOK form — ~15 tests
- [ ] **Kotlin unit tests** (JUnit): PebbleBridgePlugin MethodChannel, PebbleListenerService message parsing, PebbleMessageHandler routing
- [ ] **Manual tests**: Type/paste raw text → "Summarize" → verify title + body → stored → appears in list

Run commands:
```bash
# Dart unit tests
flutter test test/unit/

# Widget tests
flutter test test/widget/

# Kotlin unit tests
./gradlew test
```

**Exit criteria:**
- [ ] All unit tests pass (Dart ~65 tests, Kotlin ~8 tests)
- [ ] All widget tests pass (~15 tests)
- [ ] AI response parser handles all edge cases (valid JSON, non-JSON, missing fields)
- [ ] Plain text converter covers all Markdown patterns
- [ ] Drift DAO tests pass with in-memory SQLite
- [ ] PebbleKit plugin MethodChannel verified (Dart ↔ Kotlin round-trip)
- [ ] Communication protocol tests pass with mocked watch responses

---

## Phase 3: Watch↔Phone Integration (Android Only)

**Goal:** Connect the Phase 1 watch app to the Phase 2 Flutter app via PebbleKit Android 2. Real AppMessage flow end-to-end.

### 3.1 Watch App Configuration
- [ ] Ensure watch app `package.json` has correct `companionApp.android` section with Flutter app package name
- [ ] Ensure watch app has **no** `src/pkjs/index.js` (messages route to companion app)
- [ ] Verify message keys match between watch `package.json` and Kotlin `PebbleMessageHandler`

### 3.2 Message Flow Implementation
- [ ] **Watch → Phone (dictation):**
  1. User dictates on watch → `RAW_TEXT` + `NOTE_ID` + `MSG_ID` sent via AppMessage
  2. Pebble Bluetooth delivers to Pebble mobile app
  3. Pebble mobile app routes to MindCorder companion app (matching UUID + package name)
  4. `PebbleListenerService.onMessageReceived()` fires
  5. Kotlin parses dictionary, forwards to Flutter via EventChannel
  6. Flutter `CommunicationService` receives text:
     - Creates note in Drift DB (`watch_id`, `raw_text`, `processing_status = 'pending'`)
     - Triggers AI summarization
- [ ] **Phone → Watch (summary title):**
  1. AI starts processing → Flutter sends `COMMAND=10` + `TITLE` + `MSG_ID` to watch
  2. Kotlin calls `DefaultPebbleSender().sendDataToPebble()` with the dictionary
  3. Watch receives title, updates processing UI
- [ ] **Phone → Watch (summary body):**
  1. AI completes → Flutter has `title` + `body` + `body_plain_text`
  2. Flutter updates Drift DB (`processing_status = 'completed'`)
  3. **Chunk splitting logic** (Dart/Flutter side):
     - Measure `body_plain_text` length against max AppMessage size (~8KB for modern SDK)
     - If fits in single message: send `COMMAND=14` + `TITLE` + `BODY` + `MSG_ID` over the MethodChannel to Kotlin, which sends it to the watch
     - If too large: split into chunks, and send `COMMAND=11` + `SUMMARY_CHUNK` + `CHUNK_INDEX` + `CHUNK_TOTAL` + `MSG_ID` for each chunk, followed by `COMMAND=12` + `COMPLETE` + `MSG_ID` as separate MethodChannel calls. This keeps the Kotlin layer thin and completely stateless.
     - Include `MSG_ID` in each chunk for deduplication on watch side
  4. Watch reassembles chunks (Phase 1 chunk.js logic), displays summary, caches title
- [ ] **Watch → Phone (FETCH_NOTE):**
  1. User selects note title on watch → sends `COMMAND=2` + `NOTE_ID` + `MSG_ID`
  2. Kotlin forwards to Flutter
  3. Flutter looks up note by `watch_id` in Drift DB
  4. Flutter sends `COMMAND=14` + `TITLE` + `BODY` (plain text) + `MSG_ID` back to watch
  5. Watch caches body, displays summary

### 3.3 Flutter Communication Service
- [ ] `CommunicationService` singleton:
  - Listens for incoming AppMessage events from EventChannel (Kotlin → Dart)
  - Routes messages by `COMMAND` value:
    - `COMMAND=1` (RAW_TEXT): create note, trigger AI
    - `COMMAND=2` (FETCH_NOTE): look up note, send body back
  - After AI completion: calls `sendSummaryToWatch()` → routes to `PebbleBridge.sendToWatch()`
- [ ] **Queue management:**
  - If watch is not connected (`isWatchConnected() == false`): queue outgoing messages
  - On reconnection: flush queue
  - Queue persists across app restarts (store in Drift or SharedPreferences)
- [ ] **State management:**
  - Expose connection state: `PebbleConnectionState` (connected, disconnected, connecting)
  - Use `provider` or `Riverpod` to expose state to UI
  - Show connection status in note list header

### 3.4 Deduplication & Reliability
- [ ] **Watch side:**
  - Track `lastIncomingMsgId` — drop messages where `MSG_ID <= lastIncomingMsgId`
  - On chunk receive: validate `CHUNK_INDEX` sequence, reject out-of-order or duplicate chunks
  - On `CHUNK_RESET`: clear reassembly buffer, return to idle
- [ ] **Phone side:**
  - Track `lastProcessedNoteId` — drop duplicate `RAW_TEXT` messages with same `NOTE_ID`
  - Send ACK to Pebble immediately on message receive (required by PebbleKit Android 2)
- [ ] **Retry logic:**
  - AppMessage NACK: retry up to 3 times with exponential backoff (1s, 2s, 4s)
  - After 3 failures: cache message locally, retry when reconnected

### 3.5 Integration Testing

**See full test automation strategy in the [Test Automation Strategy](#test-automation-strategy) section.**

- [ ] **End-to-end tests** (on real Android device + Pebble): Full flow from button press → dictation → AI summary → watch display — ~15 scenarios
- [ ] **Disconnection tests**: Phone offline during dictation, phone offline during summary push, reconnect recovery
- [ ] **Deduplication tests**: Duplicate NOTE_ID, duplicate MSG_ID, out-of-order chunks
- [ ] **Offline tests**: Cached note body displayed without phone connection
- [ ] **Error recovery**: Chunk timeout, CHUNK_RESET, AI failure, transfer failure

### 3.6 End-to-End Flow Verification
- [ ] Button press on watch → dictation → text on phone → AI summarizes → title pushes to watch → body chunks push to watch → watch displays + vibrates
- [ ] Watch-side: note titles cached and navigable, select title → fetch body from phone → display
- [ ] Phone-side list: verify note appears with title, detail view shows full Markdown body
- [ ] Offline test: view cached note body on watch with phone disconnected
- [ ] Queue test: dictate with phone offline → reconnect → verify note processes and summary returns

**Exit criteria:** Complete end-to-end flow works on Android with a real Emery/Gabbro device. Note titles stored on watch, full content fetched from phone on demand. Deduplication prevents duplicate notes. Chunk reassembly handles large summaries. Queue survives disconnection.

---

## Phase 4: Polish, Edge Cases & Testing

### 4.1 Error Recovery & UX
- [ ] Graceful handling of all failure modes:
  - [ ] Dictation timeout (no speech detected) → gentle haptic + message "Tap Select to try again"
  - [ ] AppMessage NACK → retry up to 3 times, then cache locally until phone reconnects
  - [ ] AI summarization failure → store raw text, show "Summarization failed — tap to retry"
  - [ ] API key invalid / expired → Settings badge + notification
  - [ ] Phone disconnected when fetching note → show cached body if available, or "Phone not connected"
  - [ ] Gemini Nano fails mid-generation → automatic retry with cloud provider
  - [ ] Chunk transfer timeout → "Transfer failed — tap to retry", clear reassembly buffer
- [ ] Loading states: spinner on watch during summarization, skeleton loader on phone list
- [ ] Graceful degradation: if AI is completely unavailable (no Nano, no API key), store raw text and show "AI unavailable — raw text saved"

### 4.2 Performance & Battery
- [ ] Minimize AppMessage traffic (batch multiple notes if queued)
- [ ] Watch: debounce button presses to prevent accidental double-starts
- [ ] Phone: limit concurrent AI calls to 1 (queue successive notes)
- [ ] Monitor battery impact on both devices
- [ ] Watch: stop sensors when app is backgrounded
- [ ] Watch: use lowest accelerometer sample rate if used (not currently planned)

### 4.3 Testing Suite

**See full test automation strategy in the [Test Automation Strategy](#test-automation-strategy) section.**

Phase 4 testing consolidates and expands:

- [ ] **Full regression suite**: Run all ~140+ tests (Phase 1 + 2 + 3) as a single CI pipeline
- [ ] **Edge case tests**: 100+ notes on watch, 10K+ char dictation, rapid connect/disconnect, Bluetooth interruption recovery, app upgrade migration, multi-watch isolation, low-battery safe mode
- [ ] **Performance profiling**: Memory leak detection after 100+ state transitions, battery impact measurement
- [ ] **Manual QA checklist**: All cloud providers, Nano fallback, emulator vs real-device parity, schema migration verification

### 4.4 Platform Verification
- [ ] Android device matrix: Pixel 8 (Nano), older Android (cloud fallback), Samsung, different screen sizes
- [ ] Emulator testing: `emery` and `gabbro` emulators for UI verification
- [ ] Build and release configuration (signing, versioning)
- [ ] Schema migration test: verify Drift migrations work correctly when schema changes

---

## Test Automation Strategy

This section defines the complete test automation strategy for all project phases. Each phase grows the test suite incrementally, with tests written alongside (or before) production code. The strategy is designed to run fast in local development and comprehensively in CI.

### Test Philosophy

1. **Tests are a deliverable** — exit criteria for each phase include passing tests
2. **No testable code left behind** — every module, function, and UI screen has at least one automated test
3. **Mocks over emulators** for speed during development; **real/emulator** tests for gate checks
4. **Same test sources for both runtimes** where possible — write tests once, run on Node.js for dev speed, run on XS engine for CI validation

### Test Architecture Overview

```
watch/
├── src/embeddedjs/          # Production code (already exists)
├── test/
│   ├── unit/                # Pure-logic unit tests (no Pebble deps)
│   │   ├── state.test.js
│   │   ├── chunk.test.js
│   │   ├── dictation.test.js
│   │   └── messages.test.js
│   ├── mocks/               # Mock Pebble API implementations
│   │   ├── pebble-poco.js
│   │   ├── pebble-timer.js
│   │   ├── pebble-button.js
│   │   ├── pebble-vibes.js
│   │   ├── pebble-dictation.js
│   │   ├── pebble-message.js
│   │   ├── pebble-device.js
│   │   └── pebble-screen.js
│   ├── utils.js             # Test helpers, assertions
│   └── runner.js            # Test runner entry point
│
companion/
├── test/
│   ├── unit/                # Dart unit tests
│   │   ├── ai/
│   │   │   ├── prompt_parser_test.dart
│   │   │   ├── plain_text_converter_test.dart
│   │   │   └── service_test.dart
│   │   ├── db/
│   │   │   └── notes_dao_test.dart
│   │   ├── services/
│   │   │   ├── communication_service_test.dart
│   │   │   └── queue_manager_test.dart
│   │   └── settings/
│   │       └── provider_config_test.dart
│   ├── widget/              # Flutter widget tests
│   │   ├── note_list_test.dart
│   │   ├── note_detail_test.dart
│   │   └── settings_test.dart
│   └── integration/         # End-to-end integration tests
│       ├── watch_phone_integration_test.dart
│       └── pebblekit_plugin_test.dart
```

### Tooling & Frameworks

#### Watch App Tests

| Environment | Runner | Purpose | Speed |
|-------------|--------|---------|-------|
| **Node.js** (dev loop) | Simplified logic runner | Fast feedback during development; state/logic validation | ~10ms/file |
| **Pebble emulator** (manual gate) | `pebble install --emulator` + logs | Visual rendering, button mapping, timer/animations, layout | ~5s/run |

**Simplified Logic Runner (`watch/test/logic_runner.js`):**
- A lightweight, self-contained test script that tests non-UI modules (`state.js`, `chunk.js`, and the error parsing in `dictation.js`).
- Minimal assertion helpers: `assertEqual` and `assertThrows`.
- Avoids the extreme overhead of creating complex mock classes for `Poco`, `device`, `Timer`, or custom hardware vibes/buttons.
- Pure state and parsing logic is tested with 100% precision without testing "the mock".

**Emulator-driven Manual/Console Verification:**
- For everything involving graphics (`Poco`), vibration, or button triggers, use the Pebble Emery & Gabbro Emulators directly.
- The visual flow is straightforward, and runtime state can be verified perfectly in real-time via `pebble logs`.

#### Flutter (Companion App) Tests

| Environment | Framework | Purpose |
|-------------|-----------|---------|
| **Unit tests** | `package:test` + `mockito` | Pure Dart logic, DB operations, AI parsing, config validation |
| **Widget tests** | `flutter_test` | UI component rendering, interaction, state transitions |
| **Integration tests** | `integration_test` + mock PebbleKit | End-to-end watch↔phone flow on real Android device |

Standard Flutter test tooling — no custom framework needed. Mockito for Dart-side mocking, `drift_dev` test helpers for in-memory SQLite during DB tests.

---

### Phase 1: Watch App Test Suite

#### 1.8 Test Automation (was "Testing This Phase")

**Unit Tests** (run on both Node.js + XS engine):

##### `state.test.js` — State Machine
```
- [ ] getState() returns IDLE by default
- [ ] transition() changes current state
- [ ] transition() passes data to onStateChange callback
- [ ] onStateChange() registers callback correctly
- [ ] getData() returns accumulated state data
- [ ] setData() merges new data into existing
- [ ] clearData() resets to empty object
- [ ] transition without data preserves existing stateData
- [ ] All 7 states (IDLE→ERROR) transition correctly
- [ ] Callback not called if not registered (no crash)
- [ ] Multiple rapid transitions — last wins
```

##### `chunk.test.js` — Chunk Reassembly
```
- [ ] receiveChunk() starts reassembly when state is null
- [ ] receiveChunk() validates CHUNK_TOTAL match — rejects mismatch
- [ ] receiveChunk() validates CHUNK_INDEX sequence — rejects out-of-order (gap)
- [ ] receiveChunk() validates CHUNK_INDEX sequence — rejects duplicate (index already received)
- [ ] receiveChunk() accepts sequential chunks (0, 1, 2, ...)
- [ ] receiveComplete() succeeds when all chunks received in order
- [ ] receiveComplete() fails when chunks.length < expectedTotal
- [ ] receiveComplete() fails when no reassembly state exists
- [ ] receiveReset() clears all state and returns to idle
- [ ] reset() clears reassemblyState and timeout timer
- [ ] Chunk timeout fires after CHUNK_TIMEOUT_MS (10 seconds)
- [ ] Chunk timeout resets on each new chunk
- [ ] Single chunk + complete = success (1 total)
- [ ] Empty chunk text handled correctly (empty string "")
- [ ] Very large chunk (~7KB each) — total under 8192, accepted
- [ ] Total payload > 8192 bytes guard — rejected
- [ ] Unicode / multi-byte characters in chunk text
- [ ] setOnTimeoutCallback registers and fires on timeout
- [ ] receiveTitle() returns title object correctly
```

##### `dictation.test.js` — Dictation Error Mapping
```
- [ ] getErrorType("no speech" or "0") → "no_speech"
- [ ] getErrorType(0) → "no_speech" (numeric error)
- [ ] getErrorType("connectivity" / "network" / "phone") → "connectivity"
- [ ] getErrorType("abort" / "cancel" / "system") → "aborted"
- [ ] getErrorType("reject" / "permission" / "denied") → "rejected"
- [ ] getErrorType(unknown string) → "internal_error"
- [ ] getErrorType(null) → "unknown"
- [ ] getErrorType(undefined) → "unknown"
- [ ] getErrorMessage("no_speech") → "No speech detected"
- [ ] getErrorMessage("connectivity") → "Phone not connected"
- [ ] getErrorMessage("aborted") → "Try again"
- [ ] getErrorMessage("rejected") → "" (empty, silent return)
- [ ] getErrorMessage("internal_error") → "Error, try again"
- [ ] getErrorMessage("unknown") → "Error, try again" (fallback)
```

##### `messages.test.js` — Message API Layer
```
- [ ] sendDictationResult() sets COMMAND=1 with RAW_TEXT + NOTE_ID + MSG_ID
- [ ] sendDictationResult() increments outgoingMsgId each call
- [ ] sendDictationResult() returns false when not connected
- [ ] sendDictationResult() returns true on successful write
- [ ] sendDictationResult() returns false on write exception
- [ ] sendFetchNote() sets COMMAND=2 with NOTE_ID + MSG_ID
- [ ] sendFetchNote() returns false when not connected
- [ ] isConnected() reflects onWritable/onSuspend callbacks
- [ ] getLastIncomingMsgId() / setLastIncomingMsgId() round-trip
- [ ] onReadable() passes Map to callback
- [ ] onWritable() sets connected=true, fires callback
- [ ] onSuspend() sets connected=false, fires callback
- [ ] MSG_ID deduplication: message with MSG_ID <= lastIncomingMsgId is dropped
- [ ] MSG_ID deduplication: message with MSG_ID > lastIncomingMsgId is accepted
```

##### `storage.test.js` — File Storage (Node.js only; XS uses real device.files)
```
- [ ] init() creates index.json if missing, returns empty array
- [ ] init() returns existing noteIds array
- [ ] saveNoteTitle() writes meta.json file
- [ ] saveNoteTitle() updates index.json with new ID at front
- [ ] saveNoteTitle() deduplicates IDs (moves existing to front)
- [ ] cacheNoteBody() writes body.txt file
- [ ] getCachedNoteBody() returns stored body text
- [ ] getCachedNoteBody() returns null for missing file
- [ ] evictPreviousCachedBody() removes all .body.txt except currentId
- [ ] getNoteMeta() returns parsed meta JSON
- [ ] getNoteMeta() returns null for missing file
- [ ] getAllNoteMetas() returns all metas in index order
- [ ] getNoteIds() returns ID array from index
```

**Emulator Gate Tests** (manual, visual + log verification):
```
- [ ] App launches on emery emulator — renders IDLE screen
- [ ] App launches on gabbro emulator — renders IDLE screen (round layout)
- [ ] IDLE screen: "MindCorder" + "Tap to record" + connection dot
- [ ] LISTENING screen: animated red indicator pulses
- [ ] PROCESSING screen: "Processing..." + title appears when received
- [ ] SUMMARY_READY screen: title + body text rendered
- [ ] NOTELIST screen: note titles listed (or "No notes yet")
- [ ] ERROR screen: error message + "Tap to dismiss"
- [ ] Select press transitions: IDLE→LISTENING, LISTENING→IDLE, PROCESSING→IDLE, SUMMARY→IDLE, ERROR→IDLE
- [ ] Up/Down press: IDLE→NOTELIST, SUMMARY→NOTELIST
- [ ] Back press: NOTELIST→IDLE
- [ ] Connection dot renders green/red based on mock connection state
- [ ] Vibes.doublePulse() fires on summary receipt (mock verified)
- [ ] Animation timer stops on state transitions (no orphan timers)
```

**Phase 1 CI:**
```bash
# Fast dev loop (Node.js)
node watch/test/runner.js

# XS engine validation (CI)
pebble build && mcrun -m watch/test/manifest.json -t run

# Emulator visual gate (manual)
pebble install --emulator emery && pebble install --emulator gabbro
```

**Phase 1 Exit Criteria (updated):**
- [ ] All unit tests pass on Node.js runner
- [ ] All unit tests pass on XS engine (mcrun)
- [ ] Emulator gate: app renders on both emery and gabbro
- [ ] State machine handles all transitions (verified by tests)
- [ ] Chunk reassembly passes all test cases (including edge cases)
- [ ] Note title storage works (verified by mock file system tests)
- [ ] Dictation error mapping covers all known error types

---

### Phase 2: Flutter Companion Test Suite

**Unit Tests:**

##### `prompt_parser_test.dart` — AI Response Parsing
```
- [ ] Valid JSON with title+body → parsed correctly
- [ ] Valid JSON missing title → "Untitled" default
- [ ] Valid JSON missing body → "No summary generated" default
- [ ] Non-JSON response → entire text treated as body, title from first sentence
- [ ] Empty response → both defaults applied
- [ ] Markdown in body preserved (italics, bold, lists, headers)
- [ ] Nested JSON in body field preserved as-is
- [ ] Control characters stripped from parsed text
- [ ] Very long title (100+ words) → truncated to first 8 words
- [ ] Unicode / emoji in title and body
```

##### `plain_text_converter_test.dart` — Markdown → Plain Text
```
- [ ] **bold** → plain text (no markers)
- [ ] *italic* → plain text (no markers)
- [ ] - list item → • list item
- [ ] * list item → • list item
- [ ] # Header → HEADER (uppercase, no #)
- [ ] ## Header → HEADER
- [ ] Line breaks preserved
- [ ] Mixed content (bold + list + headers) → all converted
- [ ] Nested Markdown (**bold *italic***) → clean text
- [ ] Code blocks (```) → stripped of backticks
- [ ] Links [text](url) → text (no URL)
- [ ] Already plain text → unchanged
- [ ] Empty string → empty string
```

##### `notes_dao_test.dart` — Drift Database Operations
```
- [ ] Insert note → returns generated ID, all fields stored
- [ ] insertNote() sets processing_status to 'pending'
- [ ] allNotes() returns ordered by created_at DESC
- [ ] allNotes() puts pinned notes first
- [ ] updateSummary() updates title, body, plain_text, provider, status
- [ ] archiveNote() sets is_archived=1
- [ ] pinNote() sets is_pinned=1
- [ ] getNoteById() returns correct note
- [ ] getNoteByWatchId() finds by watch_id
- [ ] getPendingNotes() returns only pending notes
- [ ] Delete note (cascade) — body removed
- [ ] Schema migration from v1 → v2 (future-proof test)
- [ ] Concurrent writes (parallel insert) — no corruption
```

##### `aiservice_test.dart` — AI Orchestration Router
```
- [ ] GeminiNanoService.summarize() returns SummaryResult on success
- [ ] GeminiNanoService.isAvailable() returns true when AICore ready
- [ ] CloudAIService.summarize() sends correct HTTP request
- [ ] CloudAIService.summarize() parses valid OpenAI-compatible response
- [ ] CloudAIService.summarize() handles Anthropic response format
- [ ] Router: Nano available → uses Nano path
- [ ] Router: Nano unavailable + API key exists → uses cloud path
- [ ] Router: Nano unavailable + no API key → status 'failed', prompt for key
- [ ] Router: Nano succeeds → result stored, status 'completed'
- [ ] Router: Nano fails with OOM → auto-retries with cloud path
- [ ] Router: Cloud fails (network) → status 'failed', queue for retry
- [ ] Router: Cloud fails (invalid key) → status 'failed', update UI
- [ ] User preference "cloud only" → skips Nano check entirely
```

##### `provider_config_test.dart` — BYOK Settings
```
- [ ] ProviderConfig.fromPreset("openai") → correct base URL + default model
- [ ] ProviderConfig.fromPreset("anthropic") → correct base URL + default model
- [ ] ProviderConfig.fromPreset("custom") → empty, requires user input
- [ ] API key stored/retrieved from secure storage
- [ ] "Test Connection" sends minimal prompt, validates response
- [ ] "Test Connection" fails gracefully on timeout, invalid key, bad URL
- [ ] Preset toggle changes base URL + model field visibility
```

##### `settings_service_test.dart` — User Preferences
```
- [ ] AI mode toggle: "on-device" / "cloud" / "auto" persisted
- [ ] Default mode is "auto" on fresh install
- [ ] Provider selection persists across app restarts
- [ ] API key masked by default, revealed on toggle
```

##### `queue_manager_test.dart` — Message Queue
```
- [ ] Outgoing message queued when watch not connected
- [ ] Queue flushed on reconnection (FIFO order)
- [ ] Queue persists across app restarts
- [ ] Queue deduplicates messages with same MSG_ID
- [ ] Maximum queue size enforced (oldest dropped)
- [ ] Queue survives rapid connect/disconnect cycles
```

**Widget Tests** (Flutter UI components):
```
- [ ] NoteListPage: shows "No notes" empty state
- [ ] NoteListPage: renders list of notes with titles + timestamps
- [ ] NoteListPage: pinned notes appear first
- [ ] NoteListPage: FAB triggers add-note flow
- [ ] NoteListPage: swipe-to-archive removes from active list
- [ ] NoteListPage: pull-to-refresh triggers refresh
- [ ] NoteListPage: connection status indicator renders
- [ ] NoteDetailPage: title + Markdown body rendered
- [ ] NoteDetailPage: raw text expandable/collapsed
- [ ] NoteDetailPage: processing status badge shows correct state
- [ ] NoteDetailPage: archive, pin, delete, retry actions visible
- [ ] SettingsPage: provider dropdown renders all presets
- [ ] SettingsPage: API key field masks input
- [ ] SettingsPage: "Test Connection" button shows result feedback
- [ ] SettingsPage: AI mode toggle updates UI
```

##### `pebblekit_plugin_test.dart` — PebbleKit Plugin (Kotlin)
```
- [ ] PebbleBridgePlugin registers MethodChannel "mindcorder/pebble"
- [ ] sendToWatch() calls DefaultPebbleSender.sendDataToPebble()
- [ ] startAppOnWatch() calls sender.startAppOnTheWatch()
- [ ] isWatchConnected() returns connection status
- [ ] PebbleListenerService.onMessageReceived() parses PebbleDictionary
- [ ] PebbleListenerService.onMessageReceived() forwards to Flutter via MethodChannel
- [ ] PebbleListenerService.onMessageReceived() sends ACK to Pebble
- [ ] EventChannel streams incoming messages to Dart
- [ ] AndroidManifest service declaration present and correct
```

##### `communication_service_test.dart` — Watch↔Phone Protocol
```
- [ ] COMMAND=1 received → creates note, triggers AI
- [ ] COMMAND=2 received → looks up note, sends body back
- [ ] COMMAND=1 with duplicate NOTE_ID → dropped (dedup)
- [ ] AI completes → title sent (COMMAND=10)
- [ ] AI completes → body chunks sent (COMMAND=11 x N + COMMAND=12)
- [ ] Body fits in single message → COMMAND=14 sent directly
- [ ] Chunk splitting logic: screen-size body (>8KB) split correctly
- [ ] MSG_ID increments monotonically on outgoing messages
- [ ] Watch disconnected → outgoing messages queued
- [ ] Watch reconnected → queue flushed
```

**Phase 2 CI:**
```bash
# Unit tests
flutter test test/unit/

# Widget tests
flutter test test/widget/

# Integration tests (requires Android device/emulator)
flutter test integration_test/

# Kotlin unit tests (JUnit)
./gradlew test
```

**Phase 2 Exit Criteria (updated):**
- [ ] All unit tests pass (Dart + Kotlin)
- [ ] All widget tests pass
- [ ] Drift DAO tests pass with in-memory DB
- [ ] AI response parser handles all edge cases
- [ ] Plain text converter covers all Markdown patterns
- [ ] PebbleKit plugin compiles and MethodChannel verified
- [ ] Communication protocol tests pass with mocked watch responses

---

### Phase 3: Integration Test Suite

**End-to-End Integration Tests** (on real Android device + Pebble):

##### `watch_phone_integration_test.dart`
```
- [ ] Watch app launches from phone (startAppOnWatch)
- [ ] Button press on watch → dictation starts → raw text arrives at phone
- [ ] Raw text → AI summarizes → summary pushes back to watch
- [ ] Summary with title only (fits in single message) → displays on watch
- [ ] Summary with long body (triggers chunking) → reassembles on watch
- [ ] Chunk out-of-order: watch rejects, phone resends
- [ ] Chunk timeout: watch errors, user can retry
- [ ] CHUNK_RESET: clears watch state, phone resends full transfer
- [ ] NOTE_ID deduplication: duplicate text → single note created
- [ ] MSG_ID deduplication: duplicate message → silently dropped
- [ ] FETCH_NOTE flow: select title on watch → body returns from phone
- [ ] FETCH_NOTE offline: cached body displayed without phone
- [ ] Note cache eviction: new note body replaces old cached body
- [ ] Phone disconnected during dictation → queued on watch, sent on reconnect
- [ ] Phone disconnected during summary push → queued on phone, sent on reconnect
- [ ] Rapid succession notes (3 in 10 seconds) → each processed independently
- [ ] Note list on watch shows correct order (most recent first)
- [ ] Note metadata persists across watch app restart
- [ ] Everyone wears Hardened Pants
```

**Phase 3 Exit Criteria (updated):**
- [ ] All end-to-end flows pass on real Android device + Pebble emery/gabbro
- [ ] No data loss during disconnection scenarios
- [ ] Deduplication prevents double-processing
- [ ] Chunk reassembly handles edge cases (timeout, out-of-order, reset)
- [ ] Offline note viewing works with cached bodies
- [ ] Queue survives app restarts on both watch and phone

---

### Phase 4: Regression Suite & Continuous Integration

**Full Regression Test Suite:**
```
- [ ] Phase 1 watch logic unit tests (Node.js)
- [ ] Phase 2 Flutter unit tests (Dart + Kotlin) — 60+ tests
- [ ] Phase 2 widget tests — 15+ tests
- [ ] Phase 3 end-to-end integration tests — 15+ tests
- [ ] Combined snapshot
```

**CI/CD Pipeline** (GitHub Actions or equivalent):
```yaml
# .github/workflows/test.yml
name: Test Suite
on: [push, pull_request]

jobs:
  watch-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20' }
      - name: Watch unit tests (Node.js)
        working-directory: watch
        run: node test/logic_runner.js

  flutter-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: 'temurin', java-version: '17' }
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.32.x' }
      - name: Flutter unit + widget tests
        working-directory: mindcorder_companion
        run: flutter test
      - name: Build Android (compile check)
        working-directory: mindcorder_companion
        run: flutter build apk --debug
```

**Edge Case & Stress Tests (Phase 4):**
```
- [ ] 100+ notes in watch index → navigation still performant
- [ ] 10K+ character dictation → chunked successfully
- [ ] Rapid connect/disconnect cycles (10/min) → queue survives
- [ ] Bluetooth interruption mid-transfer → recovery without data loss
- [ ] Watch app upgrade (new version over old) → stored notes survive
- [ ] Phone app upgrade → schema migration succeeds, no data loss
- [ ] Multiple watches paired to same phone → each isolated
- [ ] Very low battery (<5%) → app enters safe mode, no writes
- [ ] Emulator vs real-device parity verified for all screen layouts
- [ ] Memory profiling: no leaks after 100 state transitions
```

---

### Test-Driven Development Workflow (Optional)

Adopt TDD for critical/error-prone modules. Suggested priority order:

| Priority | Module | Why TDD |
|----------|--------|---------|
| 1 | **chunk.js** | Complex state machine with timeout + sequence + validation logic; easy to get wrong |
| 2 | **state.js** | Core of app behavior; all other modules depend on correct transitions |
| 3 | **plain_text_converter.dart** | Easy to test, critical for watch display correctness |
| 4 | **prompt_parser.dart** | LLM responses are unpredictable; parser must be robust |
| 5 | **queue_manager.dart** | Persistence + ordering + dedup = easy to regress |
| 6 | **communicationservice.dart** | Protocol correctness affects both watch and phone |

TDD workflow per module:
1. Write test cases for desired behavior (red)
2. Implement minimal code to pass tests (green)
3. Refactor while keeping tests green
4. Add edge case tests → repeat

All other modules: write tests immediately after implementation (not strictly TDD, but no merge without tests).

---

## Execution Order & Dependencies

```
Phase 1 (Watch - Alloy) ─────────────────────┐
                                              ├──→ Phase 3 (Integration) ──→ Phase 4 (Polish)
Phase 2 (Flutter + AI + PebbleKit) ───────────┘
```

Phases 1 and 2 are fully parallel. Phase 3 requires both. Phase 4 requires Phase 3.

Each phase has clear exit criteria that don't depend on subsequent phases. Pause at each phase boundary for review and sign-off before proceeding.

**iOS note:** iOS support is deferred to a post-MVP track. The architecture (PebbleKit iOS + Flutter plugin) can be added later without restructuring the core system.

---

## Key Technical Decisions

| Decision | Rationale |
|----------|-----------|
| **Alloy SDK (JavaScript)** over C SDK | Targets only Emery/Gabbro; modern JS with async/await; Piu UI framework; file-based storage removes 256-byte persist limit |
| **No PKJS** | Pebble docs: "PebbleKit JS cannot be used in conjunction with PebbleKit Android/iOS." PKJS and companion apps are mutually exclusive. |
| **PebbleKit Android 2** for watch-phone communication | Modern Kotlin library with Bound Services IPC; keeps app awake; actively maintained (v1.1.0, Apr 2026); Apache-2.0 license |
| **Native Kotlin required** | PebbleKit Android 2 is a Kotlin library. Must embed in Flutter plugin via MethodChannel. Cannot be avoided. |
| **Titles on watch, content on phone** | Aligns with usage model (watch = input, phone = reading surface); minimizes watch storage; enables offline title browsing |
| **File-based storage** on watch | Alloy provides `device.files` API; no 256-byte cap; can store JSON metadata + plain text body files |
| **Note IDs: `Date.now()`** | Deterministic, collision-resistant, survives app reinstalls. Phone stores as `watch_id` in Drift DB. |
| **Plain text for watch, Markdown for phone** | Watch is monochrome e-paper — no Markdown renderer needed. Phone renders full Markdown. Strip Markdown on phone before sending to watch. |
| **`gemini_nano_android` behind `AIService` interface** | Package is community-maintained (unverified uploader, 3 likes). Abstract interface allows swapping to alternative without refactoring. |
| **Drift with codegen + schema versioning** | Type-safe queries; standard Flutter pattern; `build_runner` incremental builds are fast enough. Schema versioning from day one. |
| **Chunk timeout: 10 seconds** | Balances between slow BT connections and hung transfers. |
| **Dictation buffer: 0 (unlimited)** | Lets SDK allocate what it needs; practical limit enforced by Pebble's server-side transcription (~30-60 seconds). |
| **Message deduplication via `MSG_ID`** | Bluetooth AppMessage can deliver duplicates (ACK/NACK ambiguity). Monotonic counter prevents double-processing. |
| **Android only for Phase 1-3** | iOS dropped from initial scope. Gemini Nano is Android-only. iOS to be added post-MVP with PebbleKit iOS integration. |

---

## Known Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| **Alloy dictation API lacks C SDK features** | Medium | ✅ API confirmed via `import Dictation from "pebble/dictation"` (hellodictation example). Confirmation dialog likely cannot be disabled — UX designed around it. Error codes unknown, will discover during testing. No C SDK fallback needed. |
| **`gemini_nano_android` package abandonment** | Medium | Abstract behind `AIService` interface. Cloud fallback always available. |
| **PebbleKit Android 2 is new (11 stars)** | Low | Official Pebble project (`pebble-dev` org). Apache-2.0 license. Active development (64 commits, latest Apr 2026). |
| **Emulator testing without PKJS** | Low | Phase 1 emulator tests cover watch-side logic. Real-device PKJS testing moves to Phase 3. |
| **iOS deferred** | Low | Explicitly out of scope for Phase 1-3. Architecture supports later addition. |
| **Message sending requires phone-initiated message first** | Medium | Per Alloy docs: "The `Messages` class on Pebble OS allows sending messages from the watch to the phone only after receiving a message from the phone." The companion app must send an initial "ready" message before the watch can send dictation results. Phase 2 must implement this handshake. |
| **`watch.connected.pebblekit` flag without PKJS** | Low | Since we don't use PKJS, this flag may always be false. Connection status may need to rely on `onWritable`/`onSuspend` callbacks from the Message instance instead. |
| **Message sending requires phone-initiated message first** | Medium | Per Alloy docs: "The `Messages` class on Pebble OS allows sending messages from the watch to the phone only after receiving a message from the phone." The companion app must send an initial "ready" message before the watch can send dictation results. Phase 2 must implement this handshake. |
| **`watch.connected.pebblekit` flag without PKJS** | Low | Since we don't use PKJS, this flag may always be false. Connection status may need to rely on `onWritable`/`onSuspend` callbacks from the Message instance instead. |
