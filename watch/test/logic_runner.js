import path from "path";

// 1. Polyfill XS builtins for Node.js
ArrayBuffer.fromString = function(str) {
    const encoder = new TextEncoder();
    const view = encoder.encode(str);
    return view.buffer;
};

String.fromArrayBuffer = function(buf) {
    const decoder = new TextDecoder("utf-8");
    return decoder.decode(buf);
};

// 2. Setup Pebble OS globals
let nextTimerId = 1;
let activeTimers = new Map();

globalThis.Timer = {
    set(ms, repeat, callback) {
        const id = nextTimerId++;
        activeTimers.set(id, { callback, ms, repeat });
        return id;
    },
    repeat(callback, ms, repeat) {
        const id = nextTimerId++;
        activeTimers.set(id, { callback, ms, repeat });
        return id;
    },
    clear(id) {
        activeTimers.delete(id);
    },
    _reset() {
        activeTimers.clear();
        nextTimerId = 1;
    },
    _fire(id) {
        if (activeTimers.has(id)) {
            const timer = activeTimers.get(id);
            timer.callback();
            if (!timer.repeat) {
                activeTimers.delete(id);
            }
        }
    },
    _fireAll() {
        // Copy keys to avoid modification during iteration
        const keys = Array.from(activeTimers.keys());
        for (const id of keys) {
            this._fire(id);
        }
    },
    _getActiveTimersCount() {
        return activeTimers.size;
    }
};

globalThis.setTimeout = function(callback, delay) {
    const id = nextTimerId++;
    activeTimers.set(id, { callback, ms: delay, repeat: false });
    return id;
};

globalThis.clearTimeout = function(id) {
    activeTimers.delete(id);
};

globalThis.screen = {};

// 3. Simple Test Runner Framework
let passCount = 0;
let failCount = 0;

globalThis.describe = function(suiteName, fn) {
    console.log(`\n=== Suite: ${suiteName} ===`);
    fn();
};

globalThis.test = async function(desc, fn) {
    try {
        await fn();
        console.log(`  ✓ ${desc}`);
        passCount++;
    } catch (e) {
        console.log(`  ✗ ${desc}`);
        console.error(e.stack || e);
        failCount++;
    }
};

// 4. Assertions
globalThis.assertEqual = function(actual, expected, msg = "") {
    if (actual !== expected) {
        throw new Error(`Assertion failed: expected ${expected}, got ${actual}. ${msg}`);
    }
};

globalThis.assertDeepEqual = function(actual, expected, msg = "") {
    const actualStr = JSON.stringify(actual);
    const expectedStr = JSON.stringify(expected);
    if (actualStr !== expectedStr) {
        throw new Error(`Assertion failed: expected ${expectedStr}, got ${actualStr}. ${msg}`);
    }
};

globalThis.assertTrue = function(val, msg = "") {
    assertEqual(val, true, msg);
};

globalThis.assertFalse = function(val, msg = "") {
    assertEqual(val, false, msg);
};

globalThis.assertThrows = function(fn, msg = "") {
    let threw = false;
    try {
        fn();
    } catch (e) {
        threw = true;
    }
    if (!threw) {
        throw new Error(`Assertion failed: expected function to throw. ${msg}`);
    }
};

// 5. Load and run test files
async function main() {
    const testFiles = [
        "./unit/state.test.js",
        "./unit/chunk.test.js",
        "./unit/dictation.test.js",
        "./unit/messages.test.js"
    ];

    console.log("Starting watch logic tests...");
    
    for (const file of testFiles) {
        try {
            await import(file);
        } catch (e) {
            console.error(`Failed to import test file ${file}:`, e);
            failCount++;
        }
    }

    console.log("\n=== Test Results ===");
    console.log(`Passed: ${passCount}`);
    console.log(`Failed: ${failCount}`);
    
    if (failCount > 0) {
        process.exit(1);
    } else {
        console.log("All watch tests passed successfully!");
        process.exit(0);
    }
}

main().catch(err => {
    console.error("Fatal test runner error:", err);
    process.exit(1);
});
