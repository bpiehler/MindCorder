# Development Notes — MindCorder

## Alloy SDK API Discoveries

### Dictation API (CONFIRMED)

Source: [hellodictation example](https://github.com/Moddable-OpenSource/pebble-examples/tree/main/hellodictation)

```js
import Dictation from "pebble/dictation"

let dt = new Dictation({
    onReadable() {
        // this.read() returns the transcribed text string
        console.log(`Transcription: ${this.read()}`);
    },
    onError(e) {
        // e is the error value (unknown type/codes — need to discover)
        console.log(`Dictation error: ${e}`);
    }
});

dt.start(); // begins dictation session
```

**Key findings:**
- ✅ `import Dictation from "pebble/dictation"` — native Alloy module, no C SDK fallback needed
- ✅ `onReadable()` callback fires when transcription is ready
- ✅ `this.read()` returns the transcribed text string
- ✅ `onError(e)` callback for error handling
- ✅ `dt.start()` begins a dictation session

**Unknowns (to investigate during implementation):**
- ⚠️ **Confirmation dialog**: C SDK has `dictation_session_enable_confirmation()` — Alloy API does NOT expose this in the example. The user likely must press Select to confirm each transcription. This adds one extra button press per session. Design UX around this.
- ⚠️ **Error dialogs**: C SDK has `dictation_session_enable_error_dialogs()` — unknown if Alloy supports disabling these.
- ⚠️ **Error codes**: `onError(e)` receives an error value, but the error code names/values are unknown (C SDK uses `DictationSessionStatusFailureNoSpeechDetected`, etc.). Need to discover these during testing.
- ⚠️ **Buffer size**: C SDK has `dictation_session_create(buffer_size, ...)` — Alloy constructor takes only a config object. Buffer size may be handled internally or unlimited by default.
- ⚠️ **Session reuse**: In the example, `setImmediate(() => this.start())` auto-restarts after each transcription. We'll call `start()` manually from our state machine instead.

### Vibration API (CONFIRMED)

Source: [hellovibes example](https://github.com/Moddable-OpenSource/pebble-examples/tree/main/hellovibes)

```js
import Vibes from "pebble/vibes"

Vibes.shortPulse()
Vibes.longPulse()
Vibes.doublePulse()  // ← use this for summary notification
Vibes.pattern([100, 100, 150, 50, 50, 150, 1000])  // [on, off, on, off, ...] in ms
Vibes.cancel()
```

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

## Build System Notes

1. **wscript modification required:** The generated wscript includes a `pbl_bundle` call with `js=` parameter referencing PKJS. Since this project uses no PKJS (messages route directly to companion app), the `js=` parameter must be removed:
   ```python
   # BEFORE (generated):
   ctx.pbl_bundle(binaries=binaries,
                  js=ctx.path.ant_glob(['src/pkjs/**/*.js', ...]),
                  js_entry_file='src/pkjs/index.js')
   
   # AFTER (fixed):
   ctx.pbl_bundle(binaries=binaries)
   ```

2. **manifest.json** references `manifest_mod.json` and `manifest_typings.json` only. Each module file MUST be listed in the `modules` array.

## Poco Rendering Approach

- Rendering lives in `main.js` using Poco — procedural draw calls between `begin()`/`end()`.
- Button handling uses `Button` from `"pebble/button"`.
- No separate UI module files needed.

| Risk | Status | Notes |
|------|--------|-------|
| Alloy dictation confirmation dialog | ⚠️ Likely present | UX designed around it; may add extra button press |
| Alloy dictation error codes | 🔍 Unknown | Discover during implementation/testing |
| Message sending requires phone-initiated message first | ⚠️ Documented | Phone companion must send initial "ready" message |
| `watch.connected.pebblekit` without PKJS | 🔍 Unknown | May need to use `onWritable`/`onSuspend` instead |
