import * as chunk from "../../src/embeddedjs/chunk.js";

describe("Chunk Reassembly (chunk.js)", () => {
    test("should handle basic single chunk and complete successfully", () => {
        chunk.reset();
        Timer._reset();

        const session = 1000;
        const res = chunk.receiveChunk(0, 1, "Hello World", 42, session);
        assertDeepEqual(res, { success: true, nextIndex: 1, total: 1 });

        const completeRes = chunk.receiveCompleteWithSession(session);
        assertDeepEqual(completeRes, { success: true, text: "Hello World" });
    });

    test("should handle multiple chunks reassembled in order", () => {
        chunk.reset();
        Timer._reset();

        const session = 2000;
        chunk.receiveChunk(0, 3, "Chunk 1, ", 101, session);
        chunk.receiveChunk(1, 3, "Chunk 2, ", 102, session);
        chunk.receiveChunk(2, 3, "Chunk 3", 103, session);

        const completeRes = chunk.receiveCompleteWithSession(session);
        assertDeepEqual(completeRes, { success: true, text: "Chunk 1, Chunk 2, Chunk 3" });
    });

    test("should reject mismatched total in subsequent chunks", () => {
        chunk.reset();
        Timer._reset();

        const session = 3000;
        chunk.receiveChunk(0, 3, "Chunk 1", 101, session);
        const res = chunk.receiveChunk(1, 4, "Chunk 2", 102, session);
        assertEqual(res.error, "CHUNK_TOTAL_MISMATCH");
    });

    test("should reject out of order chunks", () => {
        chunk.reset();
        Timer._reset();

        const session = 4000;
        chunk.receiveChunk(0, 3, "Chunk 1", 101, session);
        const res = chunk.receiveChunk(2, 3, "Chunk 3", 102, session);
        assertEqual(res.error, "OUT_OF_ORDER");
    });

    test("should reject session mismatch", () => {
        chunk.reset();
        Timer._reset();

        chunk.receiveChunk(0, 2, "Chunk 1", 101, 100);
        const res = chunk.receiveChunk(1, 2, "Chunk 2", 102, 101); // different session
        assertEqual(res.error, "SESSION_ID_MISMATCH");

        const completeRes = chunk.receiveCompleteWithSession(101); // mismatched complete session
        assertEqual(completeRes.error, "SESSION_ID_MISMATCH");
    });

    test("should enforce maximum payload size guard", () => {
        chunk.reset();
        Timer._reset();

        // 5 * 2048 = 10240 (> 8192 bytes limit)
        const res = chunk.receiveChunk(0, 5, "Large chunk", 101, 123);
        assertEqual(res.error, "MAX_TOTAL_BYTES_EXCEEDED");
    });

    test("should handle reset", () => {
        chunk.reset();
        Timer._reset();

        chunk.receiveChunk(0, 2, "Chunk 1", 101, 123);
        const res = chunk.receiveReset();
        assertDeepEqual(res, { success: true });

        // Completing after reset should fail
        const completeRes = chunk.receiveComplete();
        assertEqual(completeRes.error, "NO_REASSEMBLY");
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

        // Fire all active timers (should trigger the timeout)
        Timer._fireAll();

        assertTrue(timeoutCalled);
        assertEqual(timeoutError.error, "TIMEOUT");

        // The state should be reset after timeout
        const completeRes = chunk.receiveComplete();
        assertEqual(completeRes.error, "NO_REASSEMBLY");
    });
});
