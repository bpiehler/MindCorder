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
- [ ] Initialize Alloy project with `pebble new-project --alloy mindcorder`
- [ ] Configure `package.json`:
  ```json
  {
    "name": "MindCorder",
    "version": "1.0.0",
    "pebble": {
      "displayName": "MindCorder",
      "uuid": "<generate-unique-uuid>",
      "projectType": "moddable",
      "sdkVersion": "3",
      "enableMultiJS": true,
      "targetPlatforms": ["emery", "gabbro"],
      "watchapp": { "watchface": false },
      "messageKeys": [
        "MSG_ID",
        "COMMAND",
        "RAW_TEXT",
        "NOTE_ID",
        "SUMMARY_CHUNK",
        "CHUNK_INDEX",
        "CHUNK_TOTAL",
        "CHUNK_RESET",
        "TITLE",
        "BODY",
        "COMPLETE",
        "FETCH_NOTE"
      ],
      "companionApp": {
        "android": {
          "url": "https://play.google.com/store/apps/details?id=com.mindcorder.app",
          "apps": [
            { "package": "com.mindcorder.app" },
            { "package": "com.mindcorder.app.debug" }
          ]
        }
      }
    }
  }
  ```
- [ ] Project structure:
  ```
  mindcorder/
    src/
      embeddedjs/
        main.js              # App entry point
        manifest.json        # Module declarations
        state.js             # State machine
        dictation.js         # Dictation session management
        messages.js          # Message sending/receiving
        storage.js           # Note title file storage
        chunk.js             # Chunk reassembly logic
        ui/
          idle.js            # Idle screen
          listening.js       # Listening screen
          processing.js      # Processing screen
          summary.js         # Summary display screen
          notelist.js        # Note title list screen
    resources/               # Images, fonts
    package.json             # App manifest
  ```
- [ ] **Do NOT create** `src/pkjs/index.js` — messages must route to the companion app, not PKJS
- [ ] Set up build toolchain (`pebble build`)

### 1.2 AppMessage Communication Layer
- [ ] **Watch side** (`embeddedjs/messages.js`):
  - Import `Message` from `pebble/message`
  - Create `Message` instance with all keys from `package.json`
  - Register callbacks:
    - `onWritable()`: connection ready, can send messages
    - `onSuspend()`: connection lost, set internal `connected = false` flag
    - `onReadable()`: process incoming messages from companion app
  - Maintain a monotonic `outgoingMsgId` counter — attach `MSG_ID` to every outgoing message for deduplication on the phone side
  - Track `lastIncomingMsgId` — silently drop duplicate messages where `MSG_ID <= lastIncomingMsgId`
- [ ] **Message protocol** (watch → phone):
  - `COMMAND=1` + `RAW_TEXT` + `NOTE_ID` + `MSG_ID`: New dictation result
  - `COMMAND=2` + `NOTE_ID` + `MSG_ID`: Fetch note body by ID
- [ ] **Message protocol** (phone → watch):
  - `COMMAND=10` + `TITLE` + `MSG_ID`: Summary title (sent immediately when phone starts processing)
  - `COMMAND=11` + `SUMMARY_CHUNK` + `CHUNK_INDEX` + `CHUNK_TOTAL` + `MSG_ID`: Summary body chunk
  - `COMMAND=12` + `COMPLETE` + `MSG_ID`: Transfer complete
  - `COMMAND=13` + `CHUNK_RESET`: Abort current transfer, clear reassembly buffer
  - `COMMAND=14` + `TITLE` + `BODY` + `MSG_ID`: Full note response (for FETCH_NOTE, when body fits in single message)
- [ ] **Chunk reassembly** (`embeddedjs/chunk.js`):
  - Maintain reassembly state: `{ chunks: [], expectedTotal: null, nextIndex: 0, msgId: null }`
  - On receive chunk: validate `CHUNK_INDEX === nextIndex`, reject duplicates (index already received), store in array
  - On receive `CHUNK_TOTAL`: validate it matches expected total, reject if inconsistent
  - On receive `CHUNK_RESET`: clear all state, return to idle
  - On receive `COMPLETE`: verify all chunks received (`chunks.length === expectedTotal`), concatenate into full string, clear state
  - Timeout: 10 seconds between chunks — on timeout, clear state, transition to `ERROR` state with message "Transfer failed — tap to retry"
  - Maximum total payload: guard against buffer overflow — if `CHUNK_TOTAL * maxChunkSize > 8192` bytes, reject and request reset
  - Memory: pre-allocate a single `ArrayBuffer` of max size (8KB) for reassembly, reuse across transfers

### 1.3 Dictation Session
- [ ] **Verify Alloy dictation API** against actual documentation before implementation. The Alloy SDK may have different API names than the C SDK. Key capabilities to verify:
  - Can confirmation dialog be disabled? (`dictation_session_enable_confirmation` equivalent)
  - Can error dialogs be disabled? (`dictation_session_enable_error_dialogs` equivalent)
  - What are the status code names in Alloy/JS? (C SDK uses `DictationSessionStatusSuccess`, etc. — Alloy may use different constants)
  - Does buffer size `0` mean unlimited in Alloy?
  - **Fallback if Alloy dictation lacks these features:** Use the C SDK dictation API via `mdbl.c` entry point, or accept the confirmation dialog and adjust UX accordingly.
- [ ] Create dictation session on app launch (or lazily on first button press)
- [ ] Disable confirmation dialog for zero-friction flow (if API supports it)
- [ ] Disable error dialogs (handle errors in our own UI)
- [ ] Callback: on success, generate a unique `NOTE_ID` (timestamp-based: `Date.now()`), send `COMMAND=1` + `RAW_TEXT` + `NOTE_ID` + `MSG_ID` via `message.write()`
- [ ] Handle all status codes (use Alloy-specific names once verified):
  - Success → send text to phone, transition to `PROCESSING`
  - No speech detected → show "No speech detected", transition to `IDLE`
  - Connectivity error → show "Phone not connected", transition to `IDLE`
  - System aborted (too many errors) → show "Try again", transition to `IDLE`
  - Internal error / recognizer error → show "Error, try again", transition to `IDLE`
  - Transcription rejected → silently return to `IDLE`
- [ ] Buffer size: use `0` (unlimited allocation) — Pebble's server-side transcription enforces a practical limit of ~30-60 seconds

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

### 1.5 UI with Piu Framework
- [ ] Import Piu UI framework (`commodetto/Piu`)
- [ ] Build screens as Piu containers:
  - **Idle screen** (`ui/idle.js`): Centered text, minimal design, connection status indicator (small dot: green=connected, gray=disconnected)
  - **Listening screen** (`ui/listening.js`): Recording indicator (pulsing circle or waveform), "Listening..." text
  - **Processing screen** (`ui/processing.js`): Spinner, "Processing..." text, title appears when received
  - **Summary screen** (`ui/summary.js`): Title at top (bold, larger font), body text below (plain text, pre-formatted on phone side — no Markdown parsing on watch)
  - **Note list screen** (`ui/notelist.js`): Scrollable list of titles with timestamps, Up/Down navigation
- [ ] Circular-aware layout: use Piu's layout system with proper padding from edges for the 260×260 round display
- [ ] Touch support: Emery and Gabbro both have touchscreens — allow tap-to-scroll in summary and note list views
- [ ] On summary receipt: `vibes_double_pulse()` (import from `pebble/vibration`)
- [ ] **Markdown handling:** The phone strips Markdown to plain text before sending. The watch receives pre-formatted text with explicit line breaks and bullet characters (•, -, *). The watch does NOT parse Markdown.

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

### 1.8 Testing This Phase
- [ ] **Emulator tests** (watch-side only, no real phone needed):
  - Dictation simulation: use `pebble emu-dictation` or mock the dictation callback
  - Chunk reassembly: write unit tests for `chunk.js` with simulated chunk sequences
  - State machine: verify all transitions with simulated events
  - Note title storage: verify file read/write, index management, cache eviction
  - UI rendering: verify screens display correctly in `emery` and `gabbro` emulators
- [ ] **Mock companion test** (requires real phone with Pebble app installed):
  - Since PKJS is not used, create a separate test Android app that uses PebbleKit Android 2 to echo messages back
  - Or: test with the real Flutter app once Phase 2 is started (cross-phase testing)
- [ ] Run on emulator: `pebble install --emulator emery` and `pebble install --emulator gabbro`

**Exit criteria:**
- **Emulator gate:** Watch app UI renders correctly on both emery and gabbro emulators. State machine handles all transitions. Chunk reassembly passes unit tests. Note title storage works (read/write/cache eviction). Dictation callback flow works (simulated).
- **Real-device gate (can be deferred to Phase 3 if no test companion available):** Watch connects to phone via PebbleKit Android 2. Dictation text reaches companion app. Summary returns and displays. Note titles cache and navigate offline.

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
- [ ] Table `notes`:
  ```sql
  CREATE TABLE notes (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    watch_id INTEGER,              -- Matches watch-side note ID (Date.now() timestamp)
    created_at DATETIME NOT NULL,
    raw_text TEXT NOT NULL,
    summary_title TEXT,            -- Null until AI processes
    summary_body TEXT,             -- Null until AI processes
    body_plain_text TEXT,          -- Pre-formatted plain text for watch display
    is_archived INTEGER NOT NULL DEFAULT 0,
    is_pinned INTEGER NOT NULL DEFAULT 0,
    ai_provider TEXT,              -- Which provider was used (nano, openai, anthropic, etc.)
    processing_status TEXT NOT NULL DEFAULT 'pending'  -- pending, processing, completed, failed
  );
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
  - Check `gemini_nano_android.isAvailable()` for Gemini Nano
  - If available, check if model is downloaded (package docs indicate model downloads in background — handle "available but not ready" state)
  - Read user preference from settings (prefer nano vs. prefer cloud)
- [ ] **Router decision tree:**
  ```
  1. Is user preference set to "cloud only"? → cloudSummarize()
  2. Is Gemini Nano available AND model downloaded? → nanoSummarize()
     → On Nano failure (OOM, context exceeded) → retry with cloudSummarize()
  3. Nano unavailable or not downloaded → cloudSummarize()
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
  Return ONLY a valid JSON object with exactly two fields:
  "title": a short descriptive title for the note (max 8 words),
  "body": structured bullet points in Markdown (max 5 bullets, remove filler words, organize key points logically).
  Transcript: """<raw_text>"""
  ```
- [ ] JSON parser with validation and fallback:
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

### 2.8 PebbleKit Android 2 Integration (Flutter Plugin)
- [ ] Create Flutter plugin structure for PebbleKit Android 2:
  ```
  mindcorder_companion/
    android/
      src/main/kotlin/com/mindcorder/
        PebbleBridgePlugin.kt      # Flutter plugin entry point
        PebbleListenerService.kt   # BasePebbleListenerService implementation
        PebbleMessageHandler.kt    # Message parsing and routing
    lib/
      src/pebble/
        pebble_bridge.dart         # Dart interface to native code
        pebble_service.dart        # High-level Pebble communication service
  ```
- [ ] **Kotlin side** (`PebbleListenerService.kt`):
  - Extend `BasePebbleListenerService` from PebbleKit Android 2
  - Override `onMessageReceived(watchappUUID, data, watch)`:
    - Parse `PebbleDictionary` into key-value pairs
    - Forward to Flutter via MethodChannel (`mindcorder/pebble`)
    - Send ACK to Pebble via `PebbleKit.sendAckToPebble()` (required to prevent timeouts)
  - Override `onAppOpened` / `onAppClosed`: forward to Flutter for connection state updates
- [ ] **Kotlin side** (`PebbleBridgePlugin.kt`):
  - Implement `FlutterPlugin` interface
  - Register MethodChannel: `mindcorder/pebble`
  - Handle method calls from Dart:
    - `sendToWatch`: receives dictionary data, calls `DefaultPebbleSender().sendDataToPebble()`
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

### 2.9 Testing This Phase
- [ ] Manual input: type/paste raw text → tap "Summarize" → verify title + body generated → stored in DB → appears in list
- [ ] Test both AI paths: Nano (if device supports) and cloud (all preset providers)
- [ ] Test error states: no API key, invalid key, network failure, Nano unavailable, Nano fails mid-generation → cloud retry
- [ ] Unit tests for: DB operations, JSON parsing, prompt construction, provider config management, plain text conversion
- [ ] Widget tests: list view, detail view, settings page, BYOK form

**Exit criteria:** Flutter app accepts raw text, summarizes via either AI path, stores/retrieves notes, full list + detail UI works. PebbleKit Android 2 plugin compiles and registers correctly. MethodChannel communication between Dart and Kotlin verified.

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
  3. **Chunk splitting logic** (Kotlin side):
     - Measure `body_plain_text` length against max AppMessage size (~8KB for modern SDK)
     - If fits in single message: send `COMMAND=14` + `TITLE` + `BODY` + `MSG_ID`
     - If too large: split into chunks, send `COMMAND=11` + `SUMMARY_CHUNK` + `CHUNK_INDEX` + `CHUNK_TOTAL` + `MSG_ID` for each, then `COMMAND=12` + `COMPLETE` + `MSG_ID`
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
- [ ] Real device testing: Emery or Gabbro paired with Android phone
- [ ] Test flows:
  - Short voice note → AI summarizes → summary displays on watch
  - Long voice note (triggers chunking) → chunks reassemble correctly on watch
  - Silence timeout → gentle error message on watch
  - Rapid successive notes → each processed independently, no data corruption
  - Phone offline during dictation → message queued, sent when reconnected
  - Phone offline during summary push → summary queued, sent when reconnected
  - Note title selection on watch → fetch body from phone → display
  - Offline note viewing → cached body displays without phone connection
- [ ] Test error states:
  - AI summarization failure → raw text stored, "Failed — tap to retry" on phone
  - Chunk timeout on watch → "Transfer failed — tap to retry"
  - Duplicate message delivery → silently dropped, no duplicate notes created

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
- [ ] Watch app unit tests: chunk reassembly logic, note title storage, state machine transitions, deduplication
- [ ] Flutter unit tests: DB operations, AI response parsing, provider config validation, plain text conversion, queue management
- [ ] Flutter widget tests: list view, detail view, settings page, BYOK form
- [ ] Integration tests: full pipeline with mocked AI responses, mocked PebbleKit responses
- [ ] Manual QA checklist: all preset providers, Nano fallback, edge cases from above

### 4.4 Platform Verification
- [ ] Android device matrix: Pixel 8 (Nano), older Android (cloud fallback), Samsung, different screen sizes
- [ ] Emulator testing: `emery` and `gabbro` emulators for UI verification
- [ ] Build and release configuration (signing, versioning)
- [ ] Schema migration test: verify Drift migrations work correctly when schema changes

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
| **Alloy dictation API may lack C SDK features** | Medium | Verify API before Phase 1 implementation. Fallback to C SDK dictation via `mdbl.c` if needed. |
| **`gemini_nano_android` package abandonment** | Medium | Abstract behind `AIService` interface. Cloud fallback always available. |
| **PebbleKit Android 2 is new (11 stars)** | Low | Official Pebble project (`pebble-dev` org). Apache-2.0 license. Active development (64 commits, latest Apr 2026). |
| **Emulator testing without PKJS** | Low | Phase 1 emulator tests cover watch-side logic. Real-device PKJS testing moves to Phase 3. |
| **iOS deferred** | Low | Explicitly out of scope for Phase 1-3. Architecture supports later addition. |
