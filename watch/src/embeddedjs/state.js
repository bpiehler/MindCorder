export const IDLE = "IDLE"
export const LISTENING = "LISTENING"
export const PROCESSING = "PROCESSING"
export const SUMMARY_READY = "SUMMARY_READY"
export const NOTELIST = "NOTELIST"
export const FETCHING = "FETCHING"
export const ERROR = "ERROR"

let currentState = IDLE
let stateData = {}
let onStateChangeCallback = null

export function getState() {
    return currentState
}

export function getData() {
    return stateData
}

export function setData(data) {
    stateData = { ...stateData, ...data }
}

export function clearData() {
    stateData = {}
}

export function transition(newState, data) {
    currentState = newState
    if (data) {
        stateData = { ...stateData, ...data }
    }
    
    if (onStateChangeCallback) {
        onStateChangeCallback(currentState, stateData)
    }
}

export function onStateChange(callback) {
    onStateChangeCallback = callback
}
