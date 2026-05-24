const MAX_TOTAL_BYTES = 8192
const CHUNK_TIMEOUT_MS = 10000

let reassemblyState = null
let timeoutTimer = null

export function reset() {
    cancelTimeout()
    reassemblyState = null
}

export function startReassembly(expectedTotal, sessionId) {
    reassemblyState = {
        chunks: [],
        expectedTotal: expectedTotal,
        nextIndex: 0,
        msgId: null,
        sessionId: sessionId
    }
    cancelTimeout()
    return reassemblyState
}

export function receiveChunk(chunkIndex, chunkTotal, chunkText, msgId, sessionId) {
    if (chunkTotal * 2048 > MAX_TOTAL_BYTES) {
        return { error: "MAX_TOTAL_BYTES_EXCEEDED" }
    }

    if (!reassemblyState) {
        reassemblyState = startReassembly(chunkTotal, sessionId)
    }
    
    if (reassemblyState.expectedTotal !== null && chunkTotal !== reassemblyState.expectedTotal) {
        return { error: "CHUNK_TOTAL_MISMATCH" }
    }

    if (sessionId !== undefined && sessionId !== null && reassemblyState.sessionId !== undefined && reassemblyState.sessionId !== null && sessionId !== reassemblyState.sessionId) {
        return { error: "SESSION_ID_MISMATCH" }
    }
    
    if (chunkIndex !== reassemblyState.nextIndex) {
        return { error: "OUT_OF_ORDER", expected: reassemblyState.nextIndex, received: chunkIndex }
    }
    
    reassemblyState.chunks.push(chunkText)
    reassemblyState.nextIndex++
    reassemblyState.msgId = msgId
    
    restartTimeout()
    
    return { success: true, nextIndex: reassemblyState.nextIndex, total: reassemblyState.expectedTotal }
}

export function receiveComplete() {
    if (!reassemblyState) {
        return { error: "NO_REASSEMBLY" }
    }
    
    if (reassemblyState.chunks.length !== reassemblyState.expectedTotal) {
        return { error: "INCOMPLETE", received: reassemblyState.chunks.length, expected: reassemblyState.expectedTotal }
    }
    
    const fullText = reassemblyState.chunks.join("")
    const result = { success: true, text: fullText }
    reset()
    return result
}

export function receiveCompleteWithSession(sessionId) {
    if (!reassemblyState) {
        return { error: "NO_REASSEMBLY" }
    }

    if (sessionId !== undefined && sessionId !== null && reassemblyState.sessionId !== undefined && reassemblyState.sessionId !== null && sessionId !== reassemblyState.sessionId) {
        return { error: "SESSION_ID_MISMATCH" }
    }

    return receiveComplete()
}

export function receiveReset() {
    reset()
    return { success: true }
}

export function receiveTitle(title) {
    return { title: title }
}

function restartTimeout() {
    if (timeoutTimer) clearTimeout(timeoutTimer)
    timeoutTimer = setTimeout(() => {
        const error = { error: "TIMEOUT" }
        if (reassemblyState && reassemblyState.onTimeout) {
            reassemblyState.onTimeout(error)
        }
        reset()
    }, CHUNK_TIMEOUT_MS)
}

function cancelTimeout() {
    if (timeoutTimer) {
        clearTimeout(timeoutTimer)
        timeoutTimer = null
    }
}

export function setOnTimeoutCallback(callback) {
    if (reassemblyState) {
        reassemblyState.onTimeout = callback
    }
}

