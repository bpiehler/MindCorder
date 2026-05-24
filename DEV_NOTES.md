# Development Notes — MindCorder

## ⚠️ Architecture Decision: Moddable/Alloy → Pure C (May 2026)

**Problem:** The app initially used Moddable/Alloy (JavaScript on XS engine) for the watch UI. However, the Pebble SDK's build pipeline (`mcrun -f x`) **rejects native C code** in mods. The `"ffi"` manifest section for bridging C→JS is explicitly blocked by mcrun.js line 422-427:

```javascript
if (this.cFiles?.length) {
    throw new Error("mod cannot contain native code")
}
```

This meant two critical Pebble features — dictation and vibes — were inaccessible from JS without patching the build toolchain. The FFI workaround (C glue + linker tricks + polling pattern) required modifying mcrun.js to generate `.xsi` FFI metadata, which the bundled Moddable SDK predates.

**Resolution:** Rewrite the watch app in **pure C** using the Pebble C SDK. Dictation and vibes are native C SDK calls (no bridge needed). The Pebble C UI framework (Window, TextLayer, MenuLayer, ScrollLayer) is more appropriate than the Poco canvas API for this app's list-and-text UI. The standard `pebble build` toolchain compiles C apps without any FFI or Moddable involvement.

**Impact:**
- The watch app is ~600–700 lines of C (vs ~1100 lines of JS + C workarounds)
- All Pebble SDK features are available natively
- No build-tool patching, no linker tricks, no FFI
- The companion app (Flutter, Phase 2+) is unaffected

**What was removed:**
- `watch/src/embeddedjs/` (entire JS source tree)
- `watch/test/` (entire JS test tree)
- `watch/node_modules/` (JS dependencies)
- `watch/src/c/mdbl.c` (XS bootstrap entry point — replaced with standard `pbl_main`)
- `watch/src/c/vibes.c` / `dictation.c` (FFI wrappers — replaced by direct C SDK calls in app code)
- `manifest.json` (no longer needed; `package.json` handles config)
- Linker retention table (`ffi_refs[]`) and `__asm__` hack

---

## Build System (Pure C SDK) — May 2026

**Build tool:** Standard `pebble build` (no Moddable/mcrun involvement)

**Project type:** `package.json` must set `"projectType": "native"` (not `"moddable"`)

**wscript changes:**
- Remove `js=` and `js_entry_file=` parameters from `ctx.pbl_bundle()`
- C sources are auto-discovered via `ctx.path.ant_glob('src/c/**/*.c')`
- All `.c` files in `src/c/` are compiled and linked into `pebble-app.elf`

**Known gotchas encountered:**

1. **ClickHandler signature:** Pebble SDK's `ClickHandler` is `void (*)(void *context, void *data)` — TWO params, not one. All click handlers must take `(void *context, void *data)`.

2. **Persist API:** `persist_read` / `persist_write` don't exist. Use `persist_read_data` / `persist_write_data` for binary data.

3. **Window root layer cleanup:** Do NOT destroy `window_get_root_layer(window)` in unload handlers. Track individual layers (TextLayer, MenuLayer) and destroy them specifically.

4. **Cross-module globals:** Shared state between `.c` files needs careful declaration:
   - Define in ONE `.c` file (without `static`)
   - Declare `extern` in `protocol.h`
   - All files that need access include `protocol.h`

5. **s_window lifecycle:** A single shared `Window *s_window` across `main.c` and `ui.c` works. Each `window_*_push()` function destroys the old window (via `window_destroy(s_window)`) before creating and pushing a new one. `set_state()` no longer calls `window_stack_remove` — the push functions handle removal via `window_destroy`.

6. **MenuLayer click takeover:** `menu_layer_set_click_config_onto_window()` replaces the window's click config provider. So window-level `click_config_provider` is NOT called for MenuLayer windows. The MenuLayer handles its own up/down/select navigation internally.

7. **State-machine init sentinel:** If your first `set_state()` call transitions to a state equal to the initial value of `s_state`, the early-return guard will silently skip it and no window will be pushed → `app_event_loop()` exits immediately. Initialize `s_state` to an out-of-range sentinel like `(AppState)0xFF` so the first call always passes the guard.

**Build results:**
- Platforms: emery (Pebble Time 2), gabbro (Pebble Round 2)
- RAM footprint: ~21KB
- Free RAM: ~110KB
- Build time: <0.5s

**Known gaps (Phase 1 handoff):**
- `set_connection_status()` is defined and exported, but no Bluetooth connection callback (`battery_state_service_subscribe` or `connection_service_subscribe`) is registered — the connection indicator never fires.
- Note list has no delete action — no way to remove notes from the watch.
- Summary screen uses a fixed-height TextLayer (not ScrollLayer) — long bodies will be clipped rather than scrollable.
- `dictation_deinit()` is defined in dictation.c but was only recently added to main.c's `deinit()`.
- No C unit tests exist (requires host-side mocking of Pebble APIs or ARM QEMU).

---

## Alloy SDK API Discoveries (Historical — Superseded by Pure C)

### Dictation API — FFI Bridge Pattern (SDK 4.9.169)

**`pebble/dictation` is NOT available as a built-in module in SDK 4.9.169.** The C SDK functions exist in `libpebble.a` but no JS wrapper is shipped. Use FFI instead (see helloffi example).

**C SDK API surface (from `pebble.h`):**

```c
typedef enum {
    DictationSessionStatusSuccess = 0,
    DictationSessionStatusFailureTranscriptionRejected = 1,
    DictationSessionStatusFailureSystemAborted = 2,
    DictationSessionStatusFailureNoSpeechDetected = 3,
    DictationSessionStatusFailureConnectivityError = 4,
    DictationSessionStatusFailureInternalError = 5,
    DictationSessionStatusFailureRecognizerError = 6,
} DictationSessionStatus;

typedef void (*DictationSessionStatusCallback)(
    DictationSession *session,
    DictationSessionStatus status,
    char *transcription,
    void *context
);

DictationSession* dictation_session_create(
    uint32_t buffer_size,
    DictationSessionStatusCallback callback,
    void *callback_context,
    void *buffer
);
DictationSessionStatus dictation_session_start(DictationSession *session);
void dictation_session_stop(DictationSession *session);
void dictation_session_destroy(DictationSession *session);
void dictation_session_enable_confirmation(DictationSession *session, bool enable);
void dictation_session_enable_error_dialogs(DictationSession *session, bool enable);
```

**FFI approach:** C glue layer stores callback results in globals. JS polls with `Timer.repeat`. See plan.md Section 1.3 for full implementation.

**Status code mapping to our error types:**

| C Status Code | getErrorType() result | User-Facing Message |
|---|---|---|
| 0 (Success) | — | (not an error) |
| 1 (Rejected) | `"rejected"` | "" (silent) |
| 2 (Aborted) | `"aborted"` | "Try again" |
| 3 (No Speech) | `"no_speech"` | "No speech detected" |
| 4 (Connectivity) | `"connectivity"` | "Phone not connected" |
| 5 (Internal) | `"internal_error"` | "Error, try again" |
| 6 (Recognizer) | `"internal_error"` | "Error, try again" |
| Unknown | `"internal_error"` | "Error, try again" |

**Known issues:**
- ⚠️ **Confirmation dialog**: C SDK defaults to enabled. The user must press Select to confirm each transcription. This adds one extra button press per session. Design UX around this.
- ⚠️ **Error dialogs**: C SDK defaults to enabled. Can disable via `dictation_session_enable_error_dialogs(session, false)`.
- ⚠️ **Buffer size**: C SDK default is ~2KB. We'll use `2048` as buffer size.
- ⚠️ **Session reuse**: Call `dictation_session_destroy()` and recreate each time, or reuse and re-call `start()`.

### Vibration API — FFI Bridge

**`pebble/vibes` is NOT available as a built-in module in SDK 4.9.169.** The C SDK functions exist in `libpebble.a` but no JS wrapper is shipped. Use FFI.

**C SDK API surface:**

```c
void vibes_short_pulse(void);
void vibes_long_pulse(void);
void vibes_double_pulse(void);     // ← use this for summary notification
void vibes_enqueue_custom_pattern(VibePattern pattern);
void vibes_cancel(void);
```

**FFI declarations (in manifest.json):**

```json
{
    "ffi": {
        "sources": ["./vibes.c"],
        "functions": {
            "vibes_short_pulse":   { "arguments": [], "returns": "void" },
            "vibes_long_pulse":    { "arguments": [], "returns": "void" },
            "vibes_double_pulse":  { "arguments": [], "returns": "void" },
            "vibes_cancel":        { "arguments": [], "returns": "void" }
        }
    }
}
```

**C glue (src/c/vibes.c):**

```c
#include <pebble.h>

void vibes_short_pulse(void)  { vibes_short_pulse(); }
void vibes_long_pulse(void)   { vibes_long_pulse(); }
void vibes_double_pulse(void) { vibes_double_pulse(); }
void vibes_cancel(void)       { vibes_cancel(); }
```

**JS usage:**

```js
Natives.vibes_double_pulse()
Natives.vibes_cancel()
```

⚠️ **Custom patterns** (`vibes_enqueue_custom_pattern`) are NOT exposed via FFI because `VibePattern` is a struct and FFI only supports primitive types and pointers.

### Message API (CONFIRMED)

Source: [hellomessage example](https://github.com/Moddable-OpenSource/pebble-examples/tree/main/hellomessage) + [App Messages guide](https://developer.repebble.com/guides/alloy/app-messages/)

```js
import Message from "pebble/message"

const message = new Message({
    keys: ["COMMAND", "DATA", "RESULT"],
    onReadable() {
        const msg = this.read();
        msg.forEach((value, key) => {
            console.log(key + ": " + value);
        });
    },
    onWritable() {
        console.log("Ready to send messages");
    },
    onSuspend() {
        console.log("Messages suspended");
    }
});

// Sending:
message.write(new Map([
    ["COMMAND", 1],
    ["DATA", 42]
]));
```

**Key findings:**
- ✅ `Message` instance starts in **suspended** state
- ✅ `onWritable()` fires when ready to send
- ✅ `onSuspend()` fires when connection lost
- ✅ `onReadable()` fires when message received from phone
- ✅ `this.read()` returns a `Map` of key-value pairs
- ✅ `message.write(new Map(...))` sends to phone
- ⚠️ **Important note from docs**: "The `Messages` class on Pebble OS allows sending messages from the watch to the phone only after receiving a message from the phone." This means we may need the phone to send an initial "ready" message before the watch can send dictation results.

### File Storage API (CONFIRMED)

Source: [hellofiles example](https://github.com/Moddable-OpenSource/pebble-examples/tree/main/hellofiles) + [Storage guide](https://developer.repebble.com/guides/alloy/storage/)

```js
import device from "device"

// Write:
const data = ArrayBuffer.fromString(JSON.stringify(obj));
const save = device.files.openFile({ path, mode: "r+", size: data.byteLength });
save.write(data, 0);
save.close();

// Read:
const load = device.files.openFile({ path });
const loaded = load.read(load.status().size, 0);
load.close();
const parsed = JSON.parse(String.fromArrayBuffer(loaded));

// Delete:
device.files.delete(path);
```

### Connection Status (CONFIRMED)

Source: [helloconnected example](https://github.com/Moddable-OpenSource/pebble-examples/tree/main/helloconnected) + [Sensors guide](https://developer.repebble.com/guides/alloy/sensors-and-input/)

```js
function logConnected() {
    console.log("App connected: " + watch.connected.app);
    console.log("PebbleKitJS connected: " + watch.connected.pebblekit);
}

watch.addEventListener('connected', logConnected);
logConnected();
```

**Key findings:**
- ✅ `watch.connected.app` — Pebble mobile app connected
- ✅ `watch.connected.pebblekit` — PKJS ready (for us: companion app ready)
- ⚠️ Since we don't use PKJS, `pebblekit` may always be false. We may need to rely on `watch.connected.app` only, or detect connection via `onWritable`/`onSuspend` on the Message instance.

### Button API (CONFIRMED)

```js
import Button from "pebble/button"

new Button({
    types: ["select", "up", "down"],  // "back" disables back-to-exit
    onPush(down, type) {
        // down: true = pressed, false = released
        // type: "select" | "up" | "down" | "back"
    }
});
```

### Emulator Testing Commands

```bash
pebble install --emulator emery
pebble install --emulator gabbro
pebble emu-battery --percent 20 --charging --qemu localhost:12344
pebble emu-accel tilt-left --qemu localhost:12344
```

### Piu UI Globals (No import needed)

Available as globals: `Application`, `Behavior`, `Column`, `Container`, `Content`, `Label`, `Layout`, `Link`, `Port`, `Row`, `Scroller`, `Skin`, `Style`, `Text`, `Texture`, `Transition`, `Inverter`, `RoundRect`, `SVGImage`, `ScreenBuffer`

Color functions: `blendColors`, `hsl`, `hsla`, `rgb`, `rgba`

### Pebble Built-in Fonts (for Piu)

| Family | Style | Sizes |
|--------|-------|-------|
| Bitham | Black | 30 |
| Bitham | Bold | 42 |
| Bitham | Light | 18, 34, 42 |
| Bitham | Medium | 34, 42 |
| Droid Serif | Bold | 28 |
| Gothic | Bold | 14, 18, 24, 28, 36 |
| Gothic | Regular | 9, 14, 18, 24, 28, 36 |
| Leco | Bold | 20, 26, 32, 36, 38 |
| Leco | Light | 28 |
| Leco | Regular | 42 |
| Roboto | Bold | 49 |
| Roboto Condensed | Regular | 21 |

## FFI (Foreign Function Interface) Pattern — Recommended for App-Level C→JS Calls

**`Native(...)` class extension is firmware-only.** App-level C code (`src/c/`) cannot use `class extends Native("...")` — it throws `SyntaxError: invalid Native` at runtime because the native function registry is populated only by firmware-level pre-installed modules.

**The correct approach for app-level code is FFI**, demonstrated by the helloffi example:

### FFI Manifest Declaration

In `src/embeddedjs/manifest.json`, add an `"ffi"` section:

```json
{
  "ffi": {
    "sources": ["./dictation.c", "./vibes.c"],
    "functions": {
      "vibes_double_pulse": {
        "arguments": [],
        "returns": "void"
      },
      "dictation_start": {
        "arguments": ["uint32_t"],
        "returns": "int32_t"
      },
      "dictation_get_status": {
        "arguments": [],
        "returns": "int32_t"
      }
    }
  }
}
```

The `"sources"` paths are relative to the manifest (inside `src/embeddedjs/`), but the build system finds C files in `src/c/` by matching the basename.

### FFI C Code Pattern

Write regular C functions — no XS headers needed:

```c
// src/c/vibes.c
#include <pebble.h>

void vibes_double_pulse(void) {
    vibes_double_pulse();
}
```

### FFI JS Call Pattern

```js
Natives.vibes_double_pulse()
Natives.dictation_get_status()
```

### FFI Limitations

- **No C function pointer callbacks** — FFI cannot create JS closures from C function pointers. For callback-heavy APIs (dictation), use a C glue layer that stores results in globals and have JS poll via `Timer.repeat`.
- **Direct function calls only** — No object-oriented wrappers, no constructor patterns.

### Available Pebble SDK Built-in Modules (no C bridge needed)

These are pre-installed in `build/devices/pebble/modules/` with both C and JS source:

- `pebble/button` — Button input
- `pebble/message` — AppMessage communication
- `pebble/global` — watch.connected, watch.hour12, event listeners
- `commodetto/Poco` — Low-level canvas rendering
- `commodetto/PocoBlit` — Pixel blit operations
- `pebble/display` — Display driver
- `pebble/accelerometer` — Accelerometer sensor
- `pebble/compass` — Compass sensor
- `pebble/battery` — Battery level
- `pebble/location` — GPS location (from phone)
- `pebble/touch` — Touch input
- `pebble/httpclient` — HTTP requests (via phone proxy)
- `pebble/websocketclient` — WebSocket (via phone proxy)
- `pebble/archive-resource` — Resource archive extraction
- `Timer` (global) — setTimeout, Timer.set, Timer.repeat, Timer.delay, etc.
- `watch` (global) — Connection status, platform info

### NOT available as built-in modules in SDK 4.9.169

- **`pebble/dictation`** — C SDK functions exist in `libpebble.a` (`dictation_session_create`, etc.) but NO JS wrapper module is shipped
- **`pebble/vibes`** — Same: C SDK functions exist (`vibes_double_pulse`, etc.) but NO JS wrapper module
- **`"device"`** — Not available as a standard module alias (use `embedded:storage/files` directly for file I/O, `embedded:storage/key-value` for preferences)

### Module Resolution Order (Build System)

1. Project's own manifest modules (`src/embeddedjs/manifest.json`)
2. Included manifests (`manifest_mod.json`, `manifest_typings.json`)
3. Device-specific modules (`build/devices/pebble/modules/*/manifest.json`)
4. Global Moddable modules (`modules/`)
5. `node_modules/` (if present and configured)

### Hellodictation/Hellovibes Examples

The official examples at `github.com/Moddable-OpenSource/pebble-examples` import `pebble/dictation` and `pebble/vibes` as if they're built-in modules, but these modules are NOT present in SDK 4.9.169. The examples may require a newer SDK version or the modules may be compiled into the firmware binary itself. For SDK 4.9.169, FFI is the working approach.

### JS console.log Not Visible in pebble logs

`console.log` output from JS is routed through `modLog_transmit()` → `APP_LOG(APP_LOG_LEVEL_DEBUG_VERBOSE, ...)` which is filtered out by the default log level threshold (`APP_LOG_LEVEL_DEBUG=200` vs `DEBUG_VERBOSE=255`). The `pebble logs -v` flag controls tool verbosity, not firmware log level. For debugging, use on-screen visual indicators or throw unhandled exceptions (which route through `APP_LOG_LEVEL_ERROR`).

## XS Engine Limitations (Hardened JavaScript)

Omitted features (will throw "dead strip" exception):
- `Proxy` and `Reflect`
- `Atomics`
- `WeakMap` and `WeakSet`
- `BigInt`
- `eval`, `Function`, `Generator`

Available: `RegExp`, `JSON`, ES2025, top-level-await, standard ECMAScript modules

## Piu UI Framework (INCOMPATIBLE with Pebble mod build)

Piu CANNOT be used in Pebble Alloy apps. Including `manifest_piu.json` in `src/embeddedjs/manifest.json` causes a build failure: "mod cannot contain native code." The Piu MC (native C) modules (piuColumn.c, piuDie.c, etc.) are rejected by the Pebble mod build system.

**Confirmed workaround:** Use **Poco** (`import Poco from "commodetto/Poco"`) for all rendering. Poco is a low-level procedural API that doesn't require native C modules. The generated `pebble new-project --alloy` template uses Poco, confirming compatibility.

**manifest.json:** Must include only `manifest_mod.json` and `manifest_typings.json` — do NOT include `manifest_piu.json`.

## Runtime Startup & Memory Configuration

### ModdableCreationRecord (Custom Record Required)

Our app uses 6 modules + the full XS runtime. The Pebble platform defaults (static=32768, chunk=8192, stack=384) are insufficient. A custom `ModdableCreationRecord` is required:

```c
ModdableCreationRecord record = {
    .recordSize = sizeof(ModdableCreationRecord),
    .slot = 65536,    // 64KB slot heap (double platform default)
    .chunk = 16384,   // 16KB chunk heap (double platform default)
    .stack = 4096,    // 4KB JS call stack (10x platform default)
    .flags = 0
};
moddable_createMachine(&record);
```

**WARNING:** `moddable_createMachine(NULL)` uses platform defaults and will crash with `Slot allocation: failed for 1024 bytes` or `stack overflow` for multi-module apps.

**WARNING:** With a custom record, `moddable_createMachine` returns immediately. You MUST call `app_event_loop()` to keep the app alive. Do NOT use `moddable_createMachine(NULL)` as the pattern — it only works for trivial single-module apps.

### Manifest `creation` Section

The `"creation"` section in `manifest.json` (`"static"`, `"chunk"`, `"stack"`) is used ONLY by the Moddable build system (mcrun/xsc). The Pebble firmware's `moddable_createMachine(NULL)` ignores these values and uses hardcoded platform defaults. Use the custom C record above for memory control.

### JS Globals on Pebble

The Pebble Moddable platform runs JS in a Compartment. Available globals:

| Global | JS API | C API |
|--------|--------|-------|
| `setTimeout(fn, ms)` | one-shot timer | `Timer.set(fn, ms)` |
| `setInterval(fn, ms)` | repeating timer | `Timer.repeat(fn, ms)` |
| `clearTimeout(id)` | cancel timer | `Timer.clear(id)` |
| `clearInterval(id)` | cancel interval | `Timer.clear(id)` |
| `console.log(msg)` | debug output | routes through `modLog_transmit` |
| `screen` | Poco display driver | `pebble/display` |

**NOT globals:** `Timer` (use setTimeout/setInterval), `setImmediate` (not available), `Date` (use `Date.now()` which IS available).

### JS console.log Visibility

`console.log` output routes through `modLog_transmit()` → `APP_LOG(APP_LOG_LEVEL_DEBUG_VERBOSE, ...)` which is filtered by default. **It DOES appear** in `pebble logs` when the app uses `app_event_loop()` (custom record path). When `moddable_createMachine(NULL)` is used, the output goes to xsbug protocol instead.

## Font Limitations

**Leco fonts are numbers-only on Pebble.** All Leco variants map to `FONT_KEY_*_NUMBERS` and contain only digits (0-9). Using Leco for text strings will crash `drawText()` with `xsArg(0): invalid index` because the font has no glyphs for letters.

Use **Gothic** font family for text rendering:
- `Gothic-Bold` at 14, 18, 24, 28, 36 (full character support)
- `Gothic-Regular` at 9, 14, 18, 24, 28, 36 (full character support)

## Round Display (Gabbro) Layout

The gabbro display is 260×260 (square buffer) with a **200px diameter round viewport** centered at (130, 130). The masked areas start at x=0-30 and x=230-260, y=0-30 and y=230-260.

Use `ROUND_MASK = 32` as a safe margin for all visible content. Center text with `(SCREEN_SIZE - getTextWidth(text, font)) / 2`.

## Poco Rendering Quirks on Pebble

### screen.adaptInvalid() CRASHES

Do NOT call `screen.adaptInvalid()`. It crashes with `C: xsArg(0): invalid index` when called from timer callbacks (e.g., `setTimeout`), and silently fails when wrapped in try/catch. `render.end()` alone is sufficient — it internally calls `screen.end()` which commits the frame buffer.

### Every render.end() needs a matching render.begin()

Multiple begin/end pairs work correctly. Call `render.begin()` → draw calls → `render.end()` for each frame.

### drawText with Fonts

Text rendering works correctly with the Gothic font family via `render.drawText(text, font, color, x, y)`. The `render.getTextWidth(text, font)` metric works for centering calculations.

## AppMessage / Message Constructor

`new Message(...)` opens the Pebble AppMessage system via `app_message_open()`. On the emulator without a connected phone, this can crash the app silently. The `try/catch` in JS cannot catch native-level crashes. For emulator testing, defer or skip `messages.init()` until a phone connection is available.

### Build System Notes

1. **wscript:** The generated wscript includes `pbl_bundle` with `js=` and `js_entry_file=` parameters referencing PKJS files. These must be KEPT even though we don't use PKJS — removing them causes the Moddable build preprocess to fail.
2. **manifest.json** references `manifest_mod.json` and `manifest_typings.json` only. Each module file MUST be listed in the `modules` array. The string form `"*": "./main"` only works for apps importing only built-in modules (no relative imports).

## Testing Strategy Notes

### Test Runner Architecture

Two-tier testing to balance dev speed against correctness:
- **Tier 1 — Node.js**: Fast feedback loop. Tests run in <100ms. Uses mock implementations of Pebble-specific modules. Catches logic errors immediately during development.
- **Tier 2 — XS engine (mcrun)**: Validates behavior on the actual XS JavaScript engine. Catches XS-specific issues: no Proxy/WeakMap/eval, different error handling semantics, String/ArrayBuffer behavior.

Tests are written once, run in both environments. Module source code is imported directly; only Pebble API imports (`pebble/*`, `commodetto/*`, `device`) are mocked.

### Mock Implementation Patterns

Pebble API mocks live in `watch/test/mocks/`. Each mock:
1. Re-exports the same named exports as the real module
2. Includes `_reset()` for test isolation
3. Includes `_get*()` inspector methods for assertions
4. Stores call history for verification

Example pattern:
```js
// Mocking pebble/dictation
let lastText = null
let lastError = null
let started = false
let callback = null

export class Dictation {
    constructor(opts) { callback = opts; }
}
export function start() { started = true; return true; }
export function simulateText(text) { callback?.onReadable?.call({ read: () => text }); }
export function simulateError(err) { callback?.onError?.(err); }
export function _reset() { lastText = null; lastError = null; started = false; callback = null; }
export function _wasStarted() { return started; }
```

### Watch Module Testability

| Module | Dependencies | Testable on Node? | Notes |
|--------|-------------|-------------------|-------|
| `state.js` | None (pure JS) | ✅ Yes | No Pebble imports — directly importable |
| `chunk.js` | `Timer` (pebble API) | ✅ With mock | Mock `Timer.set/repeat/clear` |
| `dictation.js` | `pebble/dictation` | ❌ Needs full mock | Dictation class constructor + start() |
| `messages.js` | `pebble/message` | ❌ Needs full mock | Message class constructor + write() |
| `storage.js` | `device` (files API) | ✅ With mock | Mock `device.files` with in-memory store |
| `main.js` | Poco, Vibes, Button, Timer, screen | ❌ Hard | Full Poco rendering pipeline — emulator tests only |

Strategy: Unit-test pure-logic modules (`state`, `chunk`, `dictation` error mapping, `storage` file ops) on Node.js. Rely on Tier 2 (XS + emulator) for rendering-dependent code.

### XS Engine Testing Quirks

- No `Proxy` — can't use test spies that rely on Proxy (e.g., Sinon). Use explicit `_get*()` inspector methods in mocks.
- No `WeakMap` — all maps must be strongly referenced. Ensure test cleanup nulls references.
- No `eval` / `Function` constructor — can't dynamically generate test code.
- `ArrayBuffer.fromString()` and `String.fromArrayBuffer()` are XS builtins — mock these in Node.js tests.
- `console.log` output is captured by mcrun — use for test result reporting.
- Timer IDs are opaque integers — mock Timer with a simple incrementing counter + callable queue.

### Flutter Test Notes

- Drift tests: Use `drift_dev`'s `DriftTestSupport` for in-memory SQLite — no file I/O needed.
- `flutter_secure_storage`: Mock with `shared_preferences`-style in-memory store during tests.
- `gemini_nano_android`: Not available in unit tests — mock the MethodChannel entirely.
- PebbleKit plugin: Kotlin side tested with JUnit + MockK; Dart side tested with mocked MethodChannel.

### CI Pipeline Requirements

- **Watch tests (Node.js)**: Ubuntu runner, Node.js 20+, no Pebble SDK needed
- **Watch tests (XS engine)**: Ubuntu runner, Pebble SDK 4.9.169 installed, `pebble` tool, `mcrun` in PATH
- **Flutter tests**: Ubuntu runner, Flutter 3.x, Java 17
- **Kotlin tests**: Ubuntu runner, JDK 17, `./gradlew test`
- **Integration tests**: Requires actual Android device or emulator + Pebble emulator — run on schedule or manual trigger, not on every push

### Emulator Test Script

Common emulator test commands:
```bash
# Install and launch on both emulators
pebble install --emulator emery
pebble install --emulator gabbro

# View logs during execution
pebble emu-app-config --emulator emery   # view config
pebble logs --emulator emery             # watch console output

# Simulate button presses
pebble emu-tap --emulator emery           # tap (touchscreen)
# Button presses: need to interact with emulator UI directly or use QEMU monitor

# Simulate dictation (if supported)
pebble emu-dictation "test text here" --emulator emery
```

### Known Test Gaps

| Gap | Reason | Mitigation |
|-----|--------|------------|
| No C SDK tests (`mdbl.c`) | C glue code; requires ARM cross-compilation + QEMU | Covered by build + emulator smoke test |
| No real dictation test in CI | Requires Pebble transcription servers | Covered by manual device testing in Phase 3 |
| No Bluetooth reliability test | Requires physical hardware + radio interference | Covered by Phase 3 manual testing |
| Flutter PebbleKit plugin integration | Requires Android device with Pebble app | Kotlin unit tests cover logic; end-to-end in Phase 3 |
| `watch.connected.pebblekit` without PKJS | 🔍 Unknown | May need to use `onWritable`/`onSuspend` instead |

## Advanced Architectural Guidelines (Bulletproofing)

### 1. Watch Memory Safety (Heap OOM & Fragmentation)
- **Problem:** Frequent string concats in the watch's JS heap during chunk reassembly lead to intermediate objects, triggering garbage collection churn and Heap Out-of-Memory (OOM) crashes.
- **Guideline:** Store incoming chunks as raw bytes (`Uint8Array`) inside a single pre-allocated 8KB `ArrayBuffer`. Concatenate chunk bytes using `.set()` directly inside the array buffer. Convert to a standard JS string using `String.fromArrayBuffer()` only once the final complete signal arrives.
- **Max Chunk Size:** Limit AppMessage payload sizes strictly to **2KB (2048 bytes)**. Pushing 8KB chunks can trigger high RAM pressure and OOM on the watch.

### 2. Startup Handshake & Sync (Session Epoch)
- **Problem:** Watch reboots reset the in-memory message counters. If the watch app is reinstalled or rebooted, the phone app's tracked `lastIncomingMsgId` will block all new messages from the watch as duplicates (or vice versa).
- **Guideline:** Implement a bidirectional Handshake Protocol on app startup using `COMMAND=0`. Both devices exchange their active `SESSION_ID` (timestamp of session startup) and expects. If a session ID mismatch is detected, expected baseline counters are aligned and synchronized.

### 3. Android 13/14 Background Execution
- **Problem:** Android 14 enforces extremely aggressive limits on background service starts. If the phone is locked when a watch transcript arrives, starting a standard background worker to perform heavy inference or network calls will throw a `BackgroundServiceStartNotAllowedException` or get killed by LMK.
- **Guideline:** 
  1. Declare `PebbleListenerService` with `foregroundServiceType="dataSync"` in `AndroidManifest.xml`.
  2. Ask the user during onboarding to disable battery optimizations (set the companion app to "Unrestricted" in Android settings).
  3. Acquire an active CPU `WakeLock` with a 60-second safety timeout the moment a dictation chunk arrives to prevent the CPU from entering deep sleep mid-inference.

### 4. Database Concurrency
- **Problem:** SQLite will throw "database is locked" errors if background PebbleKit threads write database updates while the main UI thread is reading/scrolling.
- **Guideline:** Enable Write-Ahead Logging (WAL) mode in SQLite, and use Drift's separate isolate feature (`DriftIsolate`) to run database operations off the main Flutter UI thread.
