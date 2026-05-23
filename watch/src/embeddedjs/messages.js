import Message from "pebble/message"

let message = null
let outgoingMsgId = 0
let lastIncomingMsgId = 0
let connected = false
let callbacks = {}

export function init(onMessage, onConnect, onDisconnect) {
    message = new Message({
        keys: ["MSG_ID", "COMMAND", "RAW_TEXT", "NOTE_ID", "SUMMARY_CHUNK", "CHUNK_INDEX", "CHUNK_TOTAL", "CHUNK_RESET", "TITLE", "BODY", "COMPLETE", "FETCH_NOTE"],
        onReadable() {
            const msgs = this.read()
            msgs.forEach((value, key) => {
                // We'll process this as a full dictionary in the receive handler
            })
            // Pass the raw Map to the callback for processing
            if (onMessage) onMessage(msgs)
        },
        onWritable() {
            connected = true
            if (onConnect) onConnect()
        },
        onSuspend() {
            connected = false
            if (onDisconnect) onDisconnect()
        }
    })
}

export function sendDictationResult(rawText, noteId) {
    if (!connected) return false
    
    outgoingMsgId++
    const msg = new Map([
        ["MSG_ID", outgoingMsgId],
        ["COMMAND", 1],
        ["RAW_TEXT", rawText],
        ["NOTE_ID", noteId]
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
        ["NOTE_ID", noteId]
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
