import { Dictation } from "pebble/dictation"

let dictation = null
let callbacks = {}

export function init(onReadable, onError) {
    dictation = new Dictation({
        onReadable() {
            const text = this.read()
            if (onReadable) onReadable(text)
        },
        onError(e) {
            if (onError) onError(e)
        }
    })
}

export function start() {
    if (dictation) {
        dictation.start()
    }
}

export function getErrorType(errorValue) {
    if (errorValue === undefined || errorValue === null) return "unknown"
    
    const errorStr = String(errorValue).toLowerCase()
    
    if (errorStr.includes("no speech") || errorStr.includes("no_speech") || errorStr === "0") {
        return "no_speech"
    }
    if (errorStr.includes("connect") || errorStr.includes("network") || errorStr.includes("phone")) {
        return "connectivity"
    }
    if (errorStr.includes("abort") || errorStr.includes("cancel") || errorStr.includes("system")) {
        return "aborted"
    }
    if (errorStr.includes("reject") || errorStr.includes("permission") || errorStr.includes("denied")) {
        return "rejected"
    }
    
    return "internal_error"
}

export function getErrorMessage(errorType) {
    switch (errorType) {
        case "no_speech":
            return "No speech detected"
        case "connectivity":
            return "Phone not connected"
        case "aborted":
            return "Try again"
        case "rejected":
            return ""
        case "internal_error":
        default:
            return "Error, try again"
    }
}
