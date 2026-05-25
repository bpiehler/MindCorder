package com.mindcorder.mindcorder_app

import io.flutter.plugin.common.EventChannel
import io.rebble.pebblekit2.common.model.PebbleDictionary
import io.rebble.pebblekit2.common.model.PebbleDictionaryItem
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

        for ((key, value) in data) {
            val index = key.toInt() - 10000
            if (index in keys.indices) {
                val keyStr = keys[index]
                when (value) {
                    is PebbleDictionaryItem.Text -> map[keyStr] = value.value
                    is PebbleDictionaryItem.Int32 -> map[keyStr] = value.value
                    is PebbleDictionaryItem.UInt32 -> map[keyStr] = value.value.toInt()
                    is PebbleDictionaryItem.Int16 -> map[keyStr] = value.value.toInt()
                    is PebbleDictionaryItem.UInt16 -> map[keyStr] = value.value.toInt()
                    is PebbleDictionaryItem.Int8 -> map[keyStr] = value.value.toInt()
                    is PebbleDictionaryItem.UInt8 -> map[keyStr] = value.value.toInt()
                    is PebbleDictionaryItem.Bytes -> map[keyStr] = value.value
                }
            }
        }

        Log.d(TAG, "Incoming Pebble Dictionary converted: $map")

        android.os.Handler(android.os.Looper.getMainLooper()).post {
            eventSink?.success(map)
        }
    }
}
