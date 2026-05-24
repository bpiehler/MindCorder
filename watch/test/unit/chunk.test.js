import * as chunk from "../../src/embeddedjs/chunk.js";

describe("Chunk Reassembly (chunk.js)", () => {
    test("should handle basic single chunk and complete successfully", () => {
        chunk.reset();
        Timer._reset();

        const session = 1000;
        const res = chunk.receiveChunk(0, 1, "Hello World", 42, session);
        assertDeepEqual(res, { success: true, nextIndex: 1, total: 1 });

        const final = chunk.receiveCompleteWithSession(session);
        assertEqual(final.success, true);
        assertEqual(final.text, "Hello World");
    });

    test("should handle multiple chunks reassembled in order", () => {
        chunk.reset();
        Timer._reset();

        chunk.receiveChunk(0, 3, "Hel", 1, 42);
        chunk.receiveChunk(1, 3, "lo ", 2, 42);
        chunk.receiveChunk(2, 3, "World", 3, 42);

        const final = chunk.receiveCompleteWithSession(42);
        assertEqual(final.success, true);
        assertEqual(final.text, "Hello World");
    });

    test("should reject mismatched total in subsequent chunks", () => {
        chunk.reset();
        Timer._reset();

        chunk.receiveChunk(0, 3, "ABC", 1, 42);
        const res = chunk.receiveChunk(1, 4, "DEF", 2, 42);
        assertEqual(res.error, "CHUNK_TOTAL_MISMATCH");
    });

    test("should reject out of order chunks", () => {
        chunk.reset();
        Timer._reset();

        chunk.receiveChunk(0, 3, "ABC", 1, 42);
        const res = chunk.receiveChunk(2, 3, "DEF", 2, 42);
        assertEqual(res.error, "OUT_OF_ORDER");
    });

    test("should reject session mismatch", () => {
        chunk.reset();
        Timer._reset();

        chunk.receiveChunk(0, 3, "ABC", 1, 42);
        const res = chunk.receiveChunk(1, 3, "DEF", 2, 43);
        assertEqual(res.error, "SESSION_ID_MISMATCH");
    });

    test("should enforce maximum payload size guard", () => {
        chunk.reset();
        Timer._reset();

        // 5 chunks * 2048 = 10240 > 8192
        const res = chunk.receiveChunk(0, 5, "A".repeat(2048), 1, 42);
        assertEqual(res.error, "MAX_TOTAL_BYTES_EXCEEDED");
    });

    test("should handle reset", () => {
        chunk.reset();
        Timer._reset();

        chunk.receiveChunk(0, 3, "ABC", 1, 42);
        const res = chunk.receiveReset();
        assertEqual(res.success, true);

        const final = chunk.receiveComplete();
        assertEqual(final.error, "NO_REASSEMBLY");
    });

    test("should handle chunk timeout", () => {
        chunk.reset();
        Timer._reset();

        let timeoutCalled = false;
        let timeoutError = null;

        chunk.receiveChunk(0, 2, "Chunk 1", 101, 123);
        chunk.setOnTimeoutCallback((err) => {
            timeoutCalled = true;
            timeoutError = err;
        });

        assertEqual(Timer._getActiveTimersCount(), 1);

        Timer._fireAll();

        assertTrue(timeoutCalled);
        assertEqual(timeoutError.error, "TIMEOUT");

        // State should be reset after timeout
        const completeRes = chunk.receiveComplete();
        assertEqual(completeRes.error, "NO_REASSEMBLY");
    });
});
