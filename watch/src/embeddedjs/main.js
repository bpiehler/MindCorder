console.log("JS: main.js evaluation started");

import Poco from "commodetto/Poco";
// import Vibes from "pebble/vibes";
import Button from "pebble/button";
import * as state from "./state";
import * as dictation from "./dictation";
import * as messages from "./messages";
import * as storage from "./storage";
import * as chunk from "./chunk";

let render;
let black, white, red, green, gray;
let fontLarge, fontMedium, fontSmall, fontBold;
let currentNoteId = null;
let currentTitle = null;
let currentBody = null;
let animationTimer = null;
let noteIds = [];

const SCREEN_SIZE = 260;
const PADDING = 20;
const ROUND_MASK = 32;
const VISIBLE_W = SCREEN_SIZE - 2 * ROUND_MASK;
const DEBUG_BAR_X = ROUND_MASK;
const DEBUG_BAR_Y = 115;
const DEBUG_BAR_H = 20;
const DEBUG_SEG_W = VISIBLE_W / 8;

let debugStep = 0;

function debugBar(color) {
    debugStep++;
    const x = DEBUG_BAR_X + (debugStep - 1) * DEBUG_SEG_W;
    try {
        render.begin();
        render.fillRectangle(color, x, DEBUG_BAR_Y, DEBUG_SEG_W, DEBUG_BAR_H);
        render.end();
    } catch (e) {}
}

function debugFail(msg) {
    if (render) {
        try {
            render.begin();
            const errRed = render.makeColor(255, 0, 0);
            const errWhite = render.makeColor(255, 255, 255);
            render.fillRectangle(errRed, 0, 0, render.width, render.height);
            render.end();
            const errFont = new render.Font("Gothic-Bold", 24);
            drawCenteredText("ERR: " + msg, errFont, errWhite, SCREEN_SIZE / 2 - 20);
        } catch (e2) {}
    }
}

function initColors() {
    black = render.makeColor(0, 0, 0);
    white = render.makeColor(255, 255, 255);
    red = render.makeColor(255, 0, 0);
    green = render.makeColor(0, 200, 0);
    gray = render.makeColor(128, 128, 128);
}

function initFonts() {
    fontLarge = new render.Font("Gothic-Bold", 28);
    fontMedium = new render.Font("Gothic-Regular", 24);
    fontSmall = new render.Font("Gothic-Regular", 18);
    fontBold = new render.Font("Gothic-Bold", 18);
}

function clearScreen() {
    render.begin();
    render.fillRectangle(white, 0, 0, render.width, render.height);
    render.end();
}

function drawText(text, font, color, x, y) {
    render.begin();
    render.drawText(text, font, color, x, y);
    render.end();
}

function drawCenteredText(text, font, color, y) {
    const width = render.getTextWidth(text, font);
    const x = (SCREEN_SIZE - width) / 2;
    drawText(text, font, color, x, y);
}

function drawConnectionDot(connected) {
    const x = SCREEN_SIZE / 2 - 6;
    const y = ROUND_MASK + 4;
    render.begin();
    render.fillRectangle(connected ? green : gray, x, y, 12, 12);
    render.end();
}

function showIdleScreen() {
    clearScreen();
    drawCenteredText("MindCorder", fontLarge, black, 80);
    drawCenteredText("Tap to record", fontMedium, black, 140);
    drawConnectionDot(messages.isConnected());
}


function showListeningScreen() {
    clearScreen();
    render.begin();
    render.fillRectangle(red, (SCREEN_SIZE - 40) / 2, 80, 40, 40);
    render.end();
    drawCenteredText("Listening...", fontMedium, black, 150);
    
    let visible = true;
    if (animationTimer) clearInterval(animationTimer);
    animationTimer = setInterval(() => {
        visible = !visible;
        render.begin();
        if (visible) {
            render.fillRectangle(red, (SCREEN_SIZE - 40) / 2, 80, 40, 40);
        } else {
            render.fillRectangle(white, (SCREEN_SIZE - 40) / 2, 80, 40, 40);
            render.drawRectangle(black, (SCREEN_SIZE - 40) / 2, 80, 40, 40);
        }
        render.end();
    }, 500, 0);
}

function showProcessingScreen() {
    clearScreen();
    drawCenteredText("Processing...", fontMedium, black, 100);
    if (currentTitle) {
        drawCenteredText(currentTitle, fontBold, black, 140);
    }
}

function showSummaryScreen() {
    clearScreen();
    if (currentTitle) {
        drawCenteredText(currentTitle, fontBold, black, PADDING);
    }
    if (currentBody) {
        const lines = currentBody.split("\n");
        let y = PADDING + 40;
        for (const line of lines) {
            if (y > SCREEN_SIZE - PADDING) break;
            drawText(line, fontSmall, black, PADDING, y);
            y += fontSmall.height + 4;
        }
    }
}

function showNoteListScreen() {
    clearScreen();
    if (noteIds.length === 0) {
        drawCenteredText("No notes yet", fontMedium, black, 100);
        return;
    }
    
    let y = PADDING;
    for (const id of noteIds) {
        const meta = storage.getNoteMeta(id);
        if (meta) {
            const date = new Date(meta.timestamp);
            const dateStr = date.toLocaleDateString();
            const text = meta.title + " (" + dateStr + ")";
            drawText(text, fontSmall, black, PADDING, y);
            y += fontSmall.height + 8;
            if (y > SCREEN_SIZE - PADDING) break;
        }
    }
}

function showFetchingScreen() {
    clearScreen();
    drawCenteredText("Loading...", fontMedium, black, 100);
}

function showErrorScreen(message) {
    clearScreen();
    drawCenteredText(message, fontMedium, black, 100);
    drawCenteredText("Tap to dismiss", fontSmall, gray, 150);
}

function handleStateChange(newState, data) {
    if (animationTimer) {
        clearInterval(animationTimer);
        animationTimer = null;
    }
    
    switch (newState) {
        case state.IDLE:
            showIdleScreen();
            break;
        case state.LISTENING:
            showListeningScreen();
            break;
        case state.PROCESSING:
            currentTitle = data.title || currentTitle;
            showProcessingScreen();
            break;
        case state.SUMMARY_READY:
            currentBody = data.body || currentBody;
            currentTitle = data.title || currentTitle;
            showSummaryScreen();
            break;
        case state.NOTELIST:
            showNoteListScreen();
            break;
        case state.FETCHING:
            showFetchingScreen();
            break;
        case state.ERROR:
            showErrorScreen(data.errorMessage || "Error, try again");
            break;
    }
}

function handleDictationSuccess(text) {
    currentNoteId = Date.now();
    messages.sendDictationResult(text, currentNoteId);
    state.transition(state.PROCESSING, { noteId: currentNoteId });
}

function handleDictationError(errorValue) {
    const errorType = dictation.getErrorType(errorValue);
    const errorMessage = dictation.getErrorMessage(errorType);
    if (errorMessage) {
        state.transition(state.ERROR, { errorMessage: errorMessage });
    } else {
        state.transition(state.IDLE);
    }
}

function handleIncomingMessage(msgMap) {
    let command = null;
    let msgId = null;
    let title = null;
    let body = null;
    let chunkIndex = null;
    let chunkTotal = null;
    let chunkText = null;
    let incomingSessionId = null;
    
    msgMap.forEach((value, key) => {
        switch (key) {
            case "COMMAND": command = value; break;
            case "MSG_ID": msgId = value; break;
            case "TITLE": title = value; break;
            case "BODY": body = value; break;
            case "CHUNK_INDEX": chunkIndex = value; break;
            case "CHUNK_TOTAL": chunkTotal = value; break;
            case "SUMMARY_CHUNK": chunkText = value; break;
            case "SESSION_ID": incomingSessionId = value; break;
        }
    });
    
    const activeSessionId = messages.getSessionId();
    if (incomingSessionId !== null && incomingSessionId !== undefined) {
        if (incomingSessionId > activeSessionId) {
            messages.setSessionId(incomingSessionId);
            messages.setLastIncomingMsgId(0);
        } else if (incomingSessionId < activeSessionId) {
            return;
        } else {
            if (msgId !== null && msgId <= messages.getLastIncomingMsgId()) {
                return;
            }
        }
    } else {
        if (msgId !== null && msgId <= messages.getLastIncomingMsgId()) {
            return;
        }
    }
    
    if (msgId !== null) {
        messages.setLastIncomingMsgId(msgId);
    }
    
    switch (command) {
        case 0:
            console.log("Handshake ACK received");
            break;
        case 10:
            currentTitle = title;
            state.transition(state.PROCESSING, { title: title });
            break;
        case 11:
            const result = chunk.receiveChunk(chunkIndex, chunkTotal, chunkText, msgId, incomingSessionId);
            if (result.error) {
                state.transition(state.ERROR, { errorMessage: "Transfer failed" });
            }
            break;
        case 12:
            const completeResult = chunk.receiveCompleteWithSession(incomingSessionId);
            if (completeResult.success) {
                // Vibes.doublePulse(); -- bridge not yet implemented
                currentBody = completeResult.text;
                if (currentNoteId) {
                    storage.saveNoteTitle(currentNoteId, currentTitle || "Untitled", Date.now());
                    storage.cacheNoteBody(currentNoteId, completeResult.text);
                    storage.evictPreviousCachedBody(currentNoteId);
                }
                state.transition(state.SUMMARY_READY, { body: completeResult.text });
            } else {
                state.transition(state.ERROR, { errorMessage: "Transfer failed" });
            }
            break;
        case 13:
            chunk.receiveReset();
            break;
        case 14:
            // Vibes.doublePulse(); -- bridge not yet implemented
            currentTitle = title;
            currentBody = body;
            if (currentNoteId) {
                storage.saveNoteTitle(currentNoteId, title || "Untitled", Date.now());
                storage.cacheNoteBody(currentNoteId, body || "");
                storage.evictPreviousCachedBody(currentNoteId);
            }
            state.transition(state.SUMMARY_READY, { title: title, body: body });
            break;
    }
}

function handleButtonPress(type) {
    const currentState = state.getState();
    
    switch (currentState) {
        case state.IDLE:
            if (type === "select") {
                state.transition(state.LISTENING);
                dictation.start();
            } else if (type === "up" || type === "down") {
                state.transition(state.NOTELIST);
            }
            break;
        case state.LISTENING:
            if (type === "select") {
                state.transition(state.IDLE);
            }
            break;
        case state.PROCESSING:
            if (type === "select") {
                state.transition(state.IDLE);
            }
            break;
        case state.SUMMARY_READY:
            if (type === "select") {
                state.transition(state.IDLE);
            } else if (type === "up" || type === "down") {
                state.transition(state.NOTELIST);
            }
            break;
        case state.NOTELIST:
            if (type === "back") {
                state.transition(state.IDLE);
            }
            break;
        case state.FETCHING:
            break;
        case state.ERROR:
            state.transition(state.IDLE);
            break;
    }
}

console.log("JS: starting top-level init");
let initOk = false;

try {
    console.log("JS: screen global check: typeof=" + typeof screen + ", exists=" + (screen != null));
    console.log("JS: Instantiating Poco");
    render = new Poco(screen);
    console.log("JS: Poco created: " + render.width + "x" + render.height);
    debugBar(render.makeColor(0, 0, 255));
    
    console.log("JS: Initializing colors");
    initColors();
    console.log("JS: Colors initialized: black=" + JSON.stringify(black) + " white=" + JSON.stringify(white));
    debugBar(render.makeColor(0, 200, 0));
    
    console.log("JS: Initializing fonts");
    initFonts();
    console.log("JS: Fonts initialized: large=" + (fontLarge ? fontLarge.name + " " + fontLarge.height : "null"));
    debugBar(render.makeColor(200, 200, 0));
    
    console.log("JS: Initializing storage");
    noteIds = storage.init();
    console.log("JS: Storage initialized, noteIds count=" + noteIds.length);
    debugBar(render.makeColor(0, 200, 200));
    
    console.log("JS: Initializing dictation");
    dictation.init(handleDictationSuccess, handleDictationError);
    console.log("JS: Dictation initialized");
    debugBar(render.makeColor(200, 0, 200));
    
    console.log("JS: Setting up state callback");
    state.onStateChange(handleStateChange);
    console.log("JS: State callback set up");
    
    chunk.setOnTimeoutCallback((err) => {
        state.transition(state.ERROR, { errorMessage: "Transfer timeout" });
    });
    
    console.log("JS: Setting up buttons");
    new Button({
        types: ["select", "up", "down", "back"],
        onPush(down, type) {
            if (!down) return;
            handleButtonPress(type);
        }
    });
    console.log("JS: Buttons set up");
    debugBar(render.makeColor(100, 100, 255));
    debugBar(render.makeColor(255, 255, 255));
    
    initOk = true;
    console.log("JS: init complete, debug bars visible for 2s");
    
    setTimeout(function() {
        console.log("JS: Showing idle screen");
        state.transition(state.IDLE);
    }, 2000);
} catch (e) {
    console.log("JS EXCEPTION during init: " + e.message + "\nStack:\n" + e.stack);
    debugFail(e.message);
}
