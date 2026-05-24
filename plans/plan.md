# MindCorder — Implementation Plan (Pure C Watch App + PebbleKit Android 2)

## Architecture Overview

**Watch app:** Pure C using the Pebble C SDK, targeting Emery (Pebble Time 2) and Gabbro (Pebble Round 2). Uses Pebble's native UI framework (Window, TextLayer, MenuLayer, ScrollLayer), the Storage API for persistent note metadata, and AppMessage for watch↔phone communication. **No Moddable/Alloy/JS** — the app is compiled with the standard Pebble toolchain (`pebble build`).

**Companion app:** Flutter (Android only), local-first with Drift SQLite DB. AI summarization via Gemini Nano (on-device, Android only) with cloud BYOK fallback. Communicates with the watch through **PebbleKit Android 2** embedded in a Flutter plugin (Kotlin native code).

**Key design decision:** The watch stores only note titles + metadata (ID, timestamp, pin/archive flags). Full note content lives on the phone. When a user selects a note on the watch, the watch sends the note ID to the phone, which responds with the full pre-formatted text body. The most-recently-viewed note is cached locally on the watch for offline access.

**Communication model:** Per Pebble documentation, *"PebbleKit JS cannot be used in conjunction with PebbleKit Android or PebbleKit iOS."* Therefore, there is no PKJS. Messages route directly: Watch C → Pebble Bluetooth → PebbleKit Android 2 → Flutter (via MethodChannel).

**Why pure C?** The Moddable/Alloy JS framework was initially chosen but proved incompatible with the Pebble build pipeline for apps that need native C SDK features (dictation, vibes). The `mcrun` tool used for mods rejects native C code, and the FFI workaround required build-tool patching. Pure C has full, native access to all Pebble SDK features: dictation, vibes, AppMessage, storage, and UI — all through standard, well-documented C APIs. The app is simple enough (~600–800 lines) that C is not a development speed burden.

---

## Phase 1: Pebble Watch App (Pure C SDK)

**Goal:** A watch app (pure C) that captures dictation, sends text over AppMessage to the companion app, receives and displays pre-formatted summaries, and caches note titles locally.

### 1.1 Project Scaffolding

- [x] Initialize C-only project structure:
  ```
  watch/
    src/c/
      main.c              # Entry point, lifecycle, global state machine
      ui.c                # UI rendering (windows, layers, menus)
      dictation.c         # Dictation session management
      app_message.c       # AppMessage send/receive + protocol
      storage.c           # Note metadata persistence
      protocol.h          # Protocol constants (commands, message keys)
    package.json          # App manifest (projectType: "native")
    wscript               # Build config (C-only, no JS)
  ```
- [x] Removed (Moddable/Alloy artifacts to delete):
  - `src/embeddedjs/` (entire directory — JS source + manifest)
  - `test/` (entire directory — JS test suite; will add C tests)
  - `node_modules/` (entire directory — JS dependencies)
  - All FFI-related C files (`vibes.c`, `dictation.c` wrappers replaced by direct C SDK calls)
  - Linker trick hack (ffi_refs[] table in mdbl.c — no longer needed)
- [x] Configure `package.json`:
  - `projectType`: `"native"` (instead of `"moddable"`)
  - Keep UUID: `E2ECDBEB-2D2B-412F-AD1D-9059180EBC47`
  - Keep `targetPlatforms`: `["emery", "gabbro", "basalt"]`
  - Keep `watchapp.watchface`: `false`
  - Keep message keys (same protocol)
  - Keep `companionApp.android` section
- [x] Configure `wscript`:
  - Remove `js=` and `js_entry_file=` parameters
  - Single `pbl_build` source glob: `src/c/**/*.c`
- [x] Verify `pebble build` passes for emery, gabbro, and basalt

- [x] Verify `pebble install --emulator gabbro` launches app
### 1.2 State Machine (main.c)

The app runs a simple state machine. Each state maps to a UI screen. Transitions are driven by button presses and event callbacks.

```
IDLE
  → Select press → LISTENING (start dictation)
  → Up/Down press → NOTELIST (browse cached titles)

LISTENING
  → Dictation success → PROCESSING (send text, wait for phone)
  → Dictation error → IDLE (show error banner, auto-dismiss after 3s)
  → Back press → IDLE (user cancel)

PROCESSING
  → Title received (COMMAND=10) → PROCESSING (update UI with title)
  → Chunks received → PROCESSING (reassemble in buffer)
  → Complete received (COMMAND=12) → SUMMARY_READY (display summary, cache title/body)
  → Chunk timeout → ERROR ("Transfer failed")
  → Back press → IDLE (user cancel)

SUMMARY_READY
  → Select press → IDLE (ready for next note)
  → Up/Down press → NOTELIST (browse notes)
  → Back press → IDLE

NOTELIST
  → Title selected → FETCHING (send FETCH_NOTE to phone)
  → Back press → IDLE

FETCHING
  → Note body received (COMMAND=14 or chunks) → SUMMARY_READY
  → Timeout (10s) → ERROR ("Phone not responding")
  → Back press → NOTELIST (cancel fetch)

ERROR
  → Select press → IDLE (dismiss)
  → Back press → IDLE (or return to previous state)
```

Implementation in C:
- Use an `enum AppState` and a global state variable
- `set_state(AppState new_state)` function that updates the UI
- State transitions happen in button handlers and callback functions
- No need for a full state machine library — a switch-case in the state setter is sufficient

### 1.3 UI Screens (ui.c)

All UI uses Pebble's native C window/layer framework. No custom canvas rendering needed.

#### 1.3.1 Idle Screen
- `Window` with white background
- `TextLayer` centered: "MindCorder" (Gothic 28 Bold)
- `TextLayer` below: "Tap Select to Record" (Gothic 18)
- `StatusBarLayer` or custom connection dot (green/gray circle in top-right corner)
- ActionBar with Select icon (standard microphone or recording icon)

#### 1.3.2 Listening Screen
- Pushed on dictation start
- `TextLayer` showing "Listening..." (Gothic 24 Bold, centered)
- Optional: simple animation via `Layer` redraw on timer (e.g., pulsing circle)
- On completion: auto-dismiss when callback fires

#### 1.3.3 Processing Screen
- `TextLayer` "Processing..." (Gothic 24)
- When `COMMAND=10` title arrives: show title text below
- ActionBar with back button to cancel

#### 1.3.4 Summary Screen
- `ScrollLayer` containing `TextLayer` for scrollable body text
- Title displayed at top (Gothic 18 Bold) via `TextLayer` above scroll
- Body text below (Gothic 14 or 18)
- ActionBar: Select → new recording, Up → note list, Back → idle

#### 1.3.5 Note List Screen
- `MenuLayer` with one row per note
- Each row: title (primary text) + timestamp (subtitle)
- Highlight currently selected row
- "No notes yet" label when empty
- Back button returns to idle

#### 1.3.6 Error Screen
- `TextLayer` with error message centered
- Auto-dismiss timer or tap to dismiss
- ActionBar with back to idle

**Memory management:**
- Windows are created dynamically and destroyed when popped
- TextLayer contents are updated with `text_layer_set_text()` — strings must stay alive or be strdup'd
- `ScrollLayer` requires child layer setup
- Use `property_animation` for smooth transitions if desired (optional)

### 1.4 Dictation Session (dictation.c)

Uses the Pebble C SDK `dictation_session` API directly.

```
dictation.c:
  Static globals:
    - static DictationSession *s_session = NULL
    - static char s_transcription[2048]  // buffer for result
    - static bool s_dictation_in_progress = false
    - static DictationSessionStatus s_last_status

  Functions:
    - dictation_init():
        Allocate the session once: dictation_session_create(2048, callback, NULL)
        Disable confirmation: dictation_session_enable_confirmation(s_session, false)
        Disable error dialogs: dictation_session_enable_error_dialogs(s_session, false)
        Return true on success

    - dictation_start():
        Reset buffer: s_transcription[0] = '\0'
        Set s_dictation_in_progress = true
        Return dictation_session_start(s_session)

    - dictation_cancel():
        dictation_session_stop(s_session)
        s_dictation_in_progress = false

    - dictation_deinit():
        dictation_session_destroy(s_session)
        s_session = NULL

    - callback(session, status, transcription, context):
        s_last_status = status
        s_dictation_in_progress = false
        if status == DictationSessionStatusSuccess && transcription:
            strncpy(s_transcription, transcription, sizeof(s_transcription) - 1)
        app_timer_register(0, (AppTimerCallback)handle_dictation_result, NULL)
        // handle_dictation_result runs on main loop and transitions state

    - dictation_get_result(): returns pointer to s_transcription or NULL
    - dictation_get_status(): returns s_last_status
    - dictation_is_in_progress(): returns s_dictation_in_progress
```

**Auto-start on Select:** When the app launches, pressing Select immediately starts dictation. No need to navigate to a button first — the idle screen IS the dictation trigger.

**Confirmation dialog:** Disabled (set `enable_confirmation` to false). The transcription is accepted automatically on success. The user can cancel via Back button during dictation.

**Error dialogs:** Disabled. We handle errors in the app UI (show error message, return to idle).

### 1.5 AppMessage Communication (app_message.c)

Uses the Pebble C SDK `AppMessage` API.

```
app_message.c:
  Configuration:
    - INBOX_SIZE = 4096   // enough for title + chunk
    - OUTBOX_SIZE = 2048  // dictation text fits

  Initialization:
    app_message_register_inbox_received(inbox_received_callback)
    app_message_register_outbox_sent(outbox_sent_callback)
    app_message_register_outbox_failed(outbox_failed_callback)
    app_message_open(INBOX_SIZE, OUTBOX_SIZE)

  Outgoing messages:
    - send_dictation():
        DictionaryIterator *iter;
        app_message_outbox_begin(&iter)
        Tuplet value = TupletInteger(COMMAND_KEY, 1)
        dict_write_tuplet(iter, &value)
        // ... write NOTE_ID, RAW_TEXT, MSG_ID, SESSION_ID
        app_message_outbox_send()

    - send_fetch_note(uint32_t note_id):
        COMMAND=2 + NOTE_ID + MSG_ID + SESSION_ID

    - send_handshake():
        COMMAND=0 + SESSION_ID + MSG_ID + LAST_INCOMING_MSG_ID

  Inbox handling (inbox_received_callback):
    Parse COMMAND key:
      0  → Handshake ACK: update session state
      10 → Title received: store title, update processing UI
      11 → Chunk: append to reassembly buffer
      12 → Complete: finalize reassembly, display summary
      13 → Reset: clear reassembly buffer
      14 → Full note (fits in one message): display immediately

  Chunk reassembly (in app_message.c or separate module):
    - Static buffer: uint8_t s_reassembly_buf[8192]
    - State: next_expected_index, total_chunks, accumulated_size
    - On COMMAND=11: copy chunk bytes into buffer at offset
    - On COMMAND=12: verify all chunks received, convert to string
    - On COMMAND=13: reset all state
    - Timeout: 10s timer per chunk; on timeout → ERROR

  MSG_ID tracking:
    - Static uint32_t s_outgoing_msg_id (increments per send)
    - Static uint32_t s_last_incoming_msg_id (tracks last processed)
    - Static uint32_t s_session_id (epoch timestamp of session)

  Retry logic:
    - On outbox_failed: retry up to 3 times with 1s/2s/4s backoff
    - After 3 failures: store message in queue, retry on reconnection
```

**Key note on AppMessage C API:** The Pebble C SDK's `app_message_outbox_send()` can be called independently — unlike the JS `Message` API, there is no requirement to receive a message before sending. The watch can send immediately on connection.

**Connection status:** AppMessage callbacks (`inbox_received`, `outbox_sent`, `outbox_failed`) serve as implicit connection status. Use `app_message_set_port` for the inbox port if needed.

### 1.6 Note Storage (storage.c)

Uses the Pebble C SDK `Storage` API for persistent binary data.

```
storage.c:
  File layout (stored as binary blobs via Storage API):
    - Key STORAGE_KEY_INDEX (uint32_t, static value):
        Array of uint32_t note_ids, most recent first
        [num_entries][id_1][id_2]...[id_N]

    - Key STORAGE_KEY_PREFIX_META + note_id (uint32_t key = prefix + note_id):
        NoteMeta struct binary:
          uint32_t note_id
          char title[128]
          uint32_t timestamp
          uint8_t flags (bit 0: pinned, bit 1: archived)

    - Key STORAGE_KEY_PREFIX_BODY + note_id:
        Cached body text (UTF-8 string, max ~2048 bytes)

  Functions:
    - storage_init(): load index from storage, or create empty
    - storage_add_note(uint32_t note_id, const char *title):
        Write NoteMeta, prepend ID to index
    - storage_cache_body(uint32_t note_id, const char *body):
        Write body blob, evict previous cached body
    - storage_get_cached_body(uint32_t note_id, char *buf, size_t bufsize):
        Read body blob, return length or 0
    - storage_get_meta(uint32_t note_id, NoteMeta *meta):
        Read NoteMeta, return true/found
    - storage_get_all_metas(NoteMeta *metas, int *count):
        Read all notes, return list
    - storage_get_note_ids(uint32_t *ids, int *count):
        Return sorted ID list
```

**Note on `storage_write/read` vs `persist`:** The `Storage` API handles arbitrary binary data with no 256-byte limit (unlike `persist`). Each storage key maps to a variable-length binary blob. Max total storage is device-dependent (~64KB on newer firmware).

**Cache eviction:** Only the most-recently-viewed body is cached. When a new body is cached, the previous body's storage key is deleted.

### 1.7 Message Protocol

Same protocol as spec.md. See spec.md §5 for complete protocol table.

### 1.8 Testing

**C Unit Tests:**
- Compile with gcc (not ARM cross-compiler) against mock Pebble SDK headers
- Test modules independently: `storage.c`, `app_message.c` (protocol parsing), `dictation.c` (error mapping)
- Simple test runner with assertions (no framework needed — or use `minunit.h`)

```
watch/test/
  src/
    test_storage.c       # Storage read/write round-trip, cache eviction
    test_protocol.c      # Message encode/decode, dedup, chunk reassembly
    test_dictation.c     # Error status mapping
    runner.c             # Main entry, run all tests
  mocks/
    pebble.h             # Mock Pebble SDK headers (stubs + spy state)
    app_message.h        # Mock AppMessage API
    dictation_session.h  # Mock dictation API
```

**Emulator tests (manual):**
```
pebble install --emulator basalt   # Basalt (rectangular 144x168) verification
pebble install --emulator gabbro   # Round display layout verification
pebble logs --emulator gabbro
```

**Phase 1 exit criteria:**
- [x] `pebble build` passes for emery, gabbro, and basalt
- [x] App launches on emulators (tested on gabbro)
- [x] Idle screen shows "MindCorder / Tap Select to Record"
- [x] Select press transitions to listening screen
- [ ] Dictation mock (emulator: `pebble emu-dictation`) returns text
- [ ] PROCESSING screen shows during simulated processing
- [ ] SUMMARY_READY screen shows title + body (scrolling if long)
- [ ] Note list renders with cached titles (or "No notes yet")
- [x] Back button navigation works (tested on listening screen)
- [ ] C unit tests pass (not yet implemented — `watch/test/` needs C test infrastructure)
- [ ] Note titles persist across app restart (storage not yet populated)
- [ ] Connection indicator renders (Bluetooth callback not yet registered)

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
    gemini_nano_android: ^1.1.3
    provider: ^6.1.2
    go_router: ^14.3.0
  dev_dependencies:
    flutter_test:
      sdk: flutter
    flutter_lints: ^5.0.0
    drift_dev: ^2.33.0
    build_runner: ^2.15.0
  ```
- [ ] Platform setup:
  - Android: `minSdk 26`, Kotlin enabled
  - Add PebbleKit Android 2: `implementation("io.rebble.pebblekit2:client:1.1.0")`
- [ ] Run `dart run build_runner build` to generate Drift code

### 2.2 Data Model (Drift)
- [ ] Table `Notes`:
  ```dart
  class Notes extends Table {
    IntColumn get id => integer().autoIncrement()();
    IntColumn get watchId => integer().nullable()();
    DateTimeColumn get createdAt => dateTime()();
    TextColumn get rawText => text()();
    TextColumn get summaryTitle => text().nullable()();
    TextColumn get summaryBody => text().nullable()();
    TextColumn get bodyPlainText => text().nullable()();
    BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
    BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
    TextColumn get aiProvider => text().nullable()();
    TextColumn get processingStatus => text().withDefault(const Constant('pending'))();
  }
  ```
- [ ] Schema versioning: start with `schemaVersion: 1`
- [ ] DAO queries: `allNotes()`, `insertNote()`, `updateSummary()`, `archiveNote()`, `pinNote()`, `getNoteById()`, `getNoteByWatchId()`, `getPendingNotes()`

### 2.3 AI Orchestration Router
- [ ] **Abstract `AIService` interface** (swap implementations):
  - `GeminiNanoService` (wraps `gemini_nano_android`)
  - `CloudAIService` (HTTP calls to cloud providers)
- [ ] **Capability detection** on startup:
  - Check Gemini Nano availability → three-state: `unavailable`, `downloading`, `ready`
  - Read user preference (nano vs cloud)
- [ ] **Router decision tree:**
  1. User "cloud only" → cloudSummarize()
  2. Nano available + ready → nanoSummarize() (8s timeout, fallback to cloud)
  3. Nano unavailable → cloudSummarize()
  4. Both fail → queue for retry

### 2.4 System Prompt & Response Parsing
- [ ] Fixed prompt:
  ```
  Format the following messy transcript into a clean, concise summary.
  Return ONLY a valid JSON object wrapped inside <output_json>...</output_json> XML tags
  with exactly two fields:
  "title": a short descriptive title (max 8 words),
  "body": structured bullet points in Markdown (max 5 bullets, remove filler words).
  Transcript: """<raw_text>"""
  ```
- [ ] Robust JSON extractor (handle code fences, prose wrapping)
- [ ] Fallback: non-JSON → entire response as body, "Untitled" as title
- [ ] Missing title → "Untitled", missing body → "No summary generated"
- [ ] Plain text conversion for watch (strip Markdown, bullets → •)

### 2.5 BYOK Settings UI
- [ ] Preset dropdown: OpenRouter / OpenAI / Anthropic / Google Gemini / OpenCode / Custom
- [ ] Each preset stores: display name, base URL, default model ID
- [ ] Key field (masked, show/hide toggle)
- [ ] "Test Connection" button
- [ ] `flutter_secure_storage` for key + config
- [ ] AI mode toggle: "On-Device" / "Cloud API" / "Auto"

### 2.6 Main UI — Note List
- [ ] ListView sorted by `created_at DESC`, pinned first
- [ ] Each row: AI-generated title, timestamp, processing status
- [ ] Swipe-to-archive, pull-to-refresh
- [ ] FAB for manual test note
- [ ] Connection status indicator
- [ ] Processing status badges: Pending/Processing/Completed/Failed

### 2.7 Note Detail View
- [ ] Title at top
- [ ] Full Markdown body via `flutter_markdown`
- [ ] Metadata: raw transcript (expandable), AI provider, created_at
- [ ] Actions: archive, pin, delete, retry (if failed)

### 2.8 PebbleKit Android 2 Integration
- [ ] Embed bridge in `android/app/src/main/kotlin/com/mindcorder/app/`:
  - `MainActivity.kt`: MethodChannel + EventChannel registration
  - `PebbleListenerService.kt`: extends `BasePebbleListenerService`
  - `PebbleMessageHandler.kt`: dictionary parsing + routing
- [ ] MethodChannel `mindcorder/pebble`:
  - `sendToWatch(Map)`: Kotlin → watch via `DefaultPebbleSender`
  - `startAppOnWatch()`, `stopAppOnWatch()`, `isWatchConnected()`
- [ ] Dart side: `pebble_bridge.dart` (typed methods)
- [ ] AndroidManifest.xml: add `PebbleListenerService` declaration
- [ ] Connection management via Bound Service

### 2.9 Testing
- [ ] **Dart unit tests** (~65): AI parsing, plain text converter, Drift DAO, orchestration, settings, protocol
- [ ] **Widget tests** (~15): Note list, detail, settings
- [ ] **Kotlin unit tests** (~8): PebbleBridge, PebbleMessageHandler
- [ ] **Manual test**: type raw text → "Summarize" → verify title+body → verify in list

---

## Phase 3: Watch↔Phone Integration

**Goal:** Connect Phase 1 watch app to Phase 2 Flutter app via PebbleKit Android 2.

### 3.1 Watch Config
- [ ] `package.json`: verify `companionApp.android` matches Flutter package name
- [ ] Message keys match between C enum and Kotlin dictionary parsing

### 3.2 Message Flow
- [ ] **Watch → Phone (dictation)**: Select → dictation → transcription → `COMMAND=1` → phone receives → ACK
- [ ] **Phone → Watch (title)**: AI starts → `COMMAND=10` + TITLE → watch processes
- [ ] **Phone → Watch (body)**: AI completes → chunks or single message → watch reassembles
- [ ] **Watch → Phone (fetch)**: Select title → `COMMAND=2` + NOTE_ID → phone responds with `COMMAND=14` or chunks

### 3.3 Flutter Communication Service
- [ ] `CommunicationService` singleton: routes incoming by COMMAND, sends to watch
- [ ] Queue management: buffer outgoing messages when watch disconnected
- [ ] State management: `PebbleConnectionState` (connected/disconnected/connecting)

### 3.4 Deduplication & Reliability
- [ ] Watch: `lastIncomingMsgId`, chunk index validation, CHUNK_RESET handling
- [ ] Phone: `lastProcessedNoteId`, immediate ACK per PebbleKit requirements
- [ ] Retry: NACK → 3 retries (1s/2s/4s backoff) → cache on failure

### 3.5 Integration Testing
- [ ] End-to-end: button → dictation → AI → summary on watch
- [ ] Offline: cached body displays without phone
- [ ] Disconnection: mid-transfer, reconnect recovery
- [ ] Deduplication: duplicate MSG_ID, out-of-order chunks
- [ ] Error recovery: timeout, CHUNK_RESET, AI failure

---

## Phase 4: Polish, Edge Cases & Testing

### 4.1 Error Recovery
- [ ] Dictation timeout → gentle haptic + "Tap Select to try again"
- [ ] AppMessage NACK → retry chain, then cache
- [ ] AI failure → store raw text, "Tap to retry"
- [ ] API key issues → Settings badge + notification
- [ ] Phone disconnected during fetch → cached body or "Phone not connected"
- [ ] Gemini Nano failure → auto-retry with cloud
- [ ] Chunk timeout → "Transfer failed — tap to retry"

### 4.2 Performance
- [ ] Debounce button presses (300ms debounce window)
- [ ] Watch: stop sensors when backgrounded
- [ ] Phone: limit concurrent AI calls to 1

### 4.3 Testing Suite
- [ ] Full regression: all C unit tests + Dart tests + emulator smoke test
- [ ] Edge cases: 100+ notes, 10K+ char dictation, rapid connect/disconnect
- [ ] Device matrix: Pixel 8 (Nano), older Android (cloud fallback), emulators

---

## Phase 1 C File Specifications

### `src/c/protocol.h`

Shared protocol constants. Used by both the watch C code and as a reference for the companion app.

```c
#ifndef PROTOCOL_H
#define PROTOCOL_H

// AppMessage keys (must match package.json messageKeys order)
typedef enum {
  KEY_MSG_ID = 0,
  KEY_COMMAND = 1,
  KEY_RAW_TEXT = 2,
  KEY_NOTE_ID = 3,
  KEY_SUMMARY_CHUNK = 4,
  KEY_CHUNK_INDEX = 5,
  KEY_CHUNK_TOTAL = 6,
  KEY_CHUNK_RESET = 7,
  KEY_TITLE = 8,
  KEY_BODY = 9,
  KEY_COMPLETE = 10,
  KEY_FETCH_NOTE = 11,
  KEY_SESSION_ID = 12,
} AppMessageKey;

// Commands: Watch → Phone
typedef enum {
  CMD_HANDSHAKE = 0,        // Session sync
  CMD_DICTATION_RESULT = 1, // RAW_TEXT + NOTE_ID
  CMD_FETCH_NOTE = 2,       // NOTE_ID → request body
} WatchCommand;

// Commands: Phone → Watch
typedef enum {
  CMD_HANDSHAKE_ACK = 0,    // Session sync ACK
  CMD_TITLE = 10,           // Summary title (AI processing started)
  CMD_CHUNK = 11,           // Body chunk (max 2048 bytes)
  CMD_COMPLETE = 12,        // Transfer complete
  CMD_RESET = 13,           // Abort current transfer
  CMD_NOTE_RESPONSE = 14,   // Full note (single message, fits in 2KB)
} PhoneCommand;

// Chunk constants
#define MAX_CHUNK_SIZE 2048
#define MAX_TOTAL_BODY 8192
#define CHUNK_TIMEOUT_MS 10000

#endif
```

### `src/c/main.c`

Entry point. Initializes all subsystems, registers button handlers, runs the app event loop.

**Global state:**
```c
typedef enum {
  STATE_IDLE,
  STATE_LISTENING,
  STATE_PROCESSING,
  STATE_SUMMARY_READY,
  STATE_NOTELIST,
  STATE_FETCHING,
  STATE_ERROR,
} AppState;

static AppState s_state = STATE_IDLE;
```

**Key functions:**
- `init(void)`: Called by `pbl_main()`. Initialize storage, AppMessage, UI, dictation.
- `deinit(void)`: Clean up all resources.
- `set_state(AppState new_state)`: Update state, transition UI.
- `select_click_handler(ClickRecognizerRef recognizer, void *context)`: Handle Select press per state.
- `up_click_handler` / `down_click_handler`: Navigation in NOTELIST state.
- `back_click_handler`: Cancel current operation / return to previous.
- `handle_dictation_result(void *data)`: Called from dictation callback timer. Transitions LISTENING→PROCESSING.

### `src/c/ui.c`

Window management and screen rendering. One window per screen, created on demand and destroyed when popped.

**Window creation functions:**
- `window_idle_create(void)`: Creates idle window with title + subtitle + connection dot. Returns `Window*`.
- `window_listening_create(void)`: "Listening..." with optional animation timer.
- `window_processing_create(void)`: "Processing..." placeholder, updates when title arrives.
- `window_summary_create(const char *title, const char *body)`: ScrollLayer + TextLayer for body. Title at top.
- `window_notelist_create(void)`: MenuLayer populated from storage index.
- `window_fetching_create(void)`: "Loading..." while waiting for phone.
- `window_error_create(const char *message)`: Centered error text, auto-dismiss timer.

**Button setup:**
- `setup_idle_buttons(Window *window)`: Register click handlers for idle state.
- `setup_listening_buttons(Window *window)`: Back = cancel dictation.
- (similar for each state)

**Connection indicator:**
- Draw small circle in top-right corner
- Green = AppMessage inbox registered (implicitly connected)
- Gray = no AppMessage activity
- Update via `layer_mark_dirty()` on connection change

### `src/c/dictation.c`

See §1.4 above for full specification.

### `src/c/app_message.c`

See §1.5 above for full specification.

### `src/c/storage.c`

See §1.6 above for full specification.

---

## C Testing Specification

### Test Framework
- Minimal custom test framework in `watch/test/runner.c`
- Each test is a function returning `const char*` (NULL = pass, string = failure message)
- `run_all_tests()` calls each test function and reports pass/fail

### Mock Strategy
- `mocks/pebble.h`: Minimal Pebble SDK header providing:
  - Type definitions (Window, Layer, TextLayer, etc.) as opaque structs with spy state
  - Function stubs that record calls and parameters
  - `_reset()` function to clear spy state between tests
- `mocks/app_message.h`: Mock AppMessage with:
  - DictionaryIterator that stores written key-value pairs
  - Callback invocation helpers (`simulate_incoming_message()`)
- `mocks/dictation.h`: Mock dictation with:
  - Simulate completion (`simulate_dictation_result()`)
  - Track session lifecycle

### Test Modules
- `test_storage.c` (~15 tests): Write/read round-trip, cache eviction, full index rebuild
- `test_protocol.c` (~20 tests): Message encoding, chunk reassembly, dedup, timeout
- `test_dictation.c` (~8 tests): Start/cancel lifecycle, callback routing, error status

### Build & Run
```bash
# Compile and run C unit tests (native gcc, not ARM)
gcc -I mocks -Isrc/c test/runner.c test/test_storage.c \
    test/test_protocol.c test/test_dictation.c \
    -o test/runner && ./test/runner

# Emulator verification
pebble build && pebble install --emulator gabbro
```
