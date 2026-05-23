import * as state from "../../src/embeddedjs/state.js";

describe("State Machine (state.js)", () => {
    test("should initialize to IDLE and empty data", () => {
        assertEqual(state.getState(), state.IDLE);
        assertDeepEqual(state.getData(), {});
    });

    test("should allow transitions and preserve data", () => {
        state.transition(state.LISTENING, { test: 123 });
        assertEqual(state.getState(), state.LISTENING);
        assertDeepEqual(state.getData(), { test: 123 });
    });

    test("should merge data on subsequent sets/transitions", () => {
        state.setData({ hello: "world" });
        assertDeepEqual(state.getData(), { test: 123, hello: "world" });

        state.transition(state.PROCESSING, { foo: "bar" });
        assertEqual(state.getState(), state.PROCESSING);
        assertDeepEqual(state.getData(), { test: 123, hello: "world", foo: "bar" });
    });

    test("should call onStateChange callback on transition", () => {
        let callbackCalled = false;
        let lastState = null;
        let lastData = null;

        state.onStateChange((s, d) => {
            callbackCalled = true;
            lastState = s;
            lastData = d;
        });

        state.transition(state.SUMMARY_READY, { finished: true });
        assertTrue(callbackCalled);
        assertEqual(lastState, state.SUMMARY_READY);
        assertEqual(lastData.finished, true);
    });

    test("should clear data", () => {
        state.clearData();
        assertDeepEqual(state.getData(), {});
    });
});
