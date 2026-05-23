import * as messages from "../../src/embeddedjs/messages.js";
import { _reset, _getLastInstance, _getWriteHistory, _simulateWritable, _simulateSuspend } from "pebble/message";

describe("Message Protocol (messages.js)", () => {
    test("should initialize correctly and register callbacks", () => {
        _reset();
        
        let onMsgCalled = false;
        let onConnectCalled = false;
        let onDisconnectCalled = false;

        messages.init(
            (msg) => { onMsgCalled = true; },
            () => { onConnectCalled = true; },
            () => { onDisconnectCalled = true; }
        );

        const instance = _getLastInstance();
        assertTrue(instance !== null);
        assertFalse(messages.isConnected());

        // Simulate connection
        _simulateWritable();
        assertTrue(messages.isConnected());
        assertTrue(onConnectCalled);

        // Connection should automatically trigger a handshake message
        const history = _getWriteHistory();
        assertEqual(history.length, 1);
        const handshake = history[0];
        assertEqual(handshake.get("COMMAND"), 0);
        assertEqual(handshake.get("SESSION_ID"), messages.getSessionId());
        assertEqual(handshake.get("MSG_ID"), messages.getOutgoingMsgId());

        // Simulate suspend
        _simulateSuspend();
        assertFalse(messages.isConnected());
        assertTrue(onDisconnectCalled);
    });

    test("should send dictation results with session info", () => {
        _reset();
        messages.init(null, null, null);
        _simulateWritable();

        // Clear history from handshake
        const history = _getWriteHistory();
        history.length = 0;

        const noteId = 987654;
        const text = "Testing voice note";
        const success = messages.sendDictationResult(text, noteId);
        assertTrue(success);

        assertEqual(history.length, 1);
        const pkt = history[0];
        assertEqual(pkt.get("COMMAND"), 1);
        assertEqual(pkt.get("RAW_TEXT"), text);
        assertEqual(pkt.get("NOTE_ID"), noteId);
        assertEqual(pkt.get("SESSION_ID"), messages.getSessionId());
        assertTrue(pkt.get("MSG_ID") > 0);
    });

    test("should send note fetch requests with session info", () => {
        _reset();
        messages.init(null, null, null);
        _simulateWritable();

        const history = _getWriteHistory();
        history.length = 0;

        const noteId = 12345;
        const success = messages.sendFetchNote(noteId);
        assertTrue(success);

        assertEqual(history.length, 1);
        const pkt = history[0];
        assertEqual(pkt.get("COMMAND"), 2);
        assertEqual(pkt.get("NOTE_ID"), noteId);
        assertEqual(pkt.get("SESSION_ID"), messages.getSessionId());
        assertTrue(pkt.get("MSG_ID") > 0);
    });

    test("should manage msg IDs and session IDs correctly", () => {
        _reset();
        messages.init(null, null, null);
        _simulateWritable();

        const origSession = messages.getSessionId();
        messages.setSessionId(9999);
        assertEqual(messages.getSessionId(), 9999);

        messages.setLastIncomingMsgId(5);
        assertEqual(messages.getLastIncomingMsgId(), 5);

        messages.setOutgoingMsgId(10);
        assertEqual(messages.getOutgoingMsgId(), 10);
    });
});
