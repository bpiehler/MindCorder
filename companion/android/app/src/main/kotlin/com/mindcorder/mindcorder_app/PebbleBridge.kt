package com.mindcorder.mindcorder_app

import io.flutter.plugin.common.EventChannel
import io.rebble.pebblekit2.client.PebbleDictionary
import android.util.Log

object PebbleBridge {
    private const val TAG = "PebbleBridge"
    private var eventSink: EventChannel.EventSink? = null

    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    fun handleIncomingMessage(data: PebbleDictionary) {
        val map = HashMap<String, Any>()
        
        val keys = arrayOf(
            "MSG_ID", "COMMAND", "RAW_TEXT", "NOTE_ID", "SUMMARY_CHUNK",
            "CHUNK_INDEX", "CHUNK_TOTAL", "CHUNK_RESET", "TITLE", "BODY",
            "COMPLETE", "FETCH_NOTE", "SESSION_ID"
        )
        
        for (i in keys.indices) {
            val keyStr = keys[i]
            val intVal = data.getInteger(i)
            if (intVal != null) {
                map[keyStr] = intVal.toInt() // Keep as Int for standard Dart json representation
                continue
            }
            val strVal = data.getString(i)
            if (strVal != null) {
                map[keyStr] = strVal
                continue
            }
        }
        
        Log.d(TAG, "Incoming Pebble Dictionary converted: $map")
        
        // Ensure running on main thread for EventSink
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            eventSink?.success(map)
        }
    }
}
