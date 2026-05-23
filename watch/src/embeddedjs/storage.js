import device from "device"

const NOTES_DIR = "/notes/"
const INDEX_FILE = NOTES_DIR + "index.json"

function ensureDir() {
    try {
        device.files.openFile({ path: NOTES_DIR + ".keep", mode: "r+" })
    } catch (e) {
        try {
            const f = device.files.openFile({ path: NOTES_DIR + ".keep", mode: "w+", size: 0 })
            f.close()
        } catch (e2) {
            // Directory may already exist
        }
    }
}

function writeJson(path, obj) {
    const data = ArrayBuffer.fromString(JSON.stringify(obj))
    try {
        device.files.delete(path)
    } catch (e) {}
    const f = device.files.openFile({ path, mode: "w+", size: data.byteLength })
    f.write(data, 0)
    f.close()
}

function readJson(path) {
    try {
        const f = device.files.openFile({ path })
        const size = f.status().size
        const buf = f.read(size, 0)
        f.close()
        return JSON.parse(String.fromArrayBuffer(buf))
    } catch (e) {
        return null
    }
}

function readText(path) {
    try {
        const f = device.files.openFile({ path })
        const size = f.status().size
        const buf = f.read(size, 0)
        f.close()
        return String.fromArrayBuffer(buf)
    } catch (e) {
        return null
    }
}

function deleteFile(path) {
    try {
        device.files.delete(path)
    } catch (e) {}
}

export function init() {
    ensureDir()
    const index = readJson(INDEX_FILE)
    if (!index) {
        writeJson(INDEX_FILE, { noteIds: [], version: 1 })
        return []
    }
    return index.noteIds || []
}

export function saveNoteTitle(id, title, timestamp) {
    const meta = {
        id: id,
        title: title,
        timestamp: timestamp,
        isPinned: false,
        isArchived: false
    }
    writeJson(NOTES_DIR + id + ".meta.json", meta)
    
    const index = readJson(INDEX_FILE) || { noteIds: [], version: 1 }
    index.noteIds = [id, ...index.noteIds.filter(nid => nid !== id)]
    writeJson(INDEX_FILE, index)
}

export function cacheNoteBody(id, bodyText) {
    const data = ArrayBuffer.fromString(bodyText)
    try {
        device.files.delete(NOTES_DIR + id + ".body.txt")
    } catch (e) {}
    const f = device.files.openFile({ path: NOTES_DIR + id + ".body.txt", mode: "w+", size: data.byteLength })
    f.write(data, 0)
    f.close()
}

export function getCachedNoteBody(id) {
    return readText(NOTES_DIR + id + ".body.txt")
}

export function evictPreviousCachedBody(currentId) {
    const index = readJson(INDEX_FILE)
    if (!index) return
    
    for (const nid of index.noteIds) {
        if (nid !== currentId) {
            deleteFile(NOTES_DIR + nid + ".body.txt")
        }
    }
}

export function getNoteMeta(id) {
    return readJson(NOTES_DIR + id + ".meta.json")
}

export function getAllNoteMetas() {
    const index = readJson(INDEX_FILE)
    if (!index) return []
    
    const metas = []
    for (const id of index.noteIds) {
        const meta = getNoteMeta(id)
        if (meta) {
            metas.push(meta)
        }
    }
    return metas
}

export function getNoteIds() {
    const index = readJson(INDEX_FILE)
    return index ? index.noteIds : []
}
