import Message from "pebble/message"

let message = null
let outgoingMsgId = 0
let lastIncomingMsgId = 0
let sessionId = Date.now()
let connected = false
let callbacks = {}

export function init(onMessage, onConnect, onDisconnect) {
    try {
        message = new Message({
            keys: ["MSG_ID", "COMMAND", "RAW_TEXT", "NOTE_ID", "SUMMARY_CHUNK", "CHUNK_INDEX", "CHUNK_TOTAL", "CHUNK_RESET", "TITLE", "BODY", "COMPLETE", "FETCH_NOTE", "SESSION_ID"],
            onReadable() {
                const msgs = this.read()
                if (onMessage) onMessage(msgs)
            },
            onWritable() {
                connected = true
                if (onConnect) onConnect()
                sendHandshake()
            },
            onSuspend() {
                connected = false
                if (onDisconnect) onDisconnect()
            }
        })
    } catch (e) {
        message = null
    }
}

export function sendHandshake() {
    if (!connected) return false
    
    outgoingMsgId++
    const msg = new Map([
        ["MSG_ID", outgoingMsgId],
        ["COMMAND", 0],
        ["SESSION_ID", sessionId]
    ])
    
    try {
        message.write(msg)
        return true
    } catch (e) {
        return false
    }
}

export function sendDictationResult(rawText, noteId) {
    if (!connected) return false
    
    outgoingMsgId++
    const msg = new Map([
        ["MSG_ID", outgoingMsgId],
        ["COMMAND", 1],
        ["RAW_TEXT", rawText],
        ["NOTE_ID", noteId],
        ["SESSION_ID", sessionId]
    ])
    
    try {
        message.write(msg)
        return true
    } catch (e) {
        return false
    }
}

export function sendFetchNote(noteId) {
    if (!connected) return false
    
    outgoingMsgId++
    const msg = new Map([
        ["MSG_ID", outgoingMsgId],
        ["COMMAND", 2],
        ["NOTE_ID", noteId],
        ["SESSION_ID", sessionId]
    ])
    
    try {
        message.write(msg)
        return true
    } catch (e) {
        return false
    }
}

export function isConnected() {
    return connected
}

export function getLastIncomingMsgId() {
    return lastIncomingMsgId
}

export function setLastIncomingMsgId(id) {
    lastIncomingMsgId = id
}

export function getSessionId() {
    return sessionId
}

export function setSessionId(id) {
    sessionId = id
}

export function getOutgoingMsgId() {
    return outgoingMsgId
}

export function setOutgoingMsgId(id) {
    outgoingMsgId = id
}

