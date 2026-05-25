package com.mindcorder.mindcorder_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import io.rebble.pebblekit2.client.DefaultPebbleSender
import io.rebble.pebblekit2.client.DefaultPebbleInfoRetriever
import io.rebble.pebblekit2.common.model.PebbleDictionaryItem
import io.rebble.pebblekit2.common.model.PebbleDictionary
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.first

class MainActivity : FlutterActivity() {
    private val CHANNEL_METHOD = "mindcorder/pebble_methods"
    private val CHANNEL_EVENT = "mindcorder/pebble_events"
    private val watchappUuid = UUID.fromString("E2ECDBEB-2D2B-412F-AD1D-9059180EBC47")
    private lateinit var pebbleSender: DefaultPebbleSender
    private val scope = CoroutineScope(Dispatchers.Main)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        pebbleSender = DefaultPebbleSender(context)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_EVENT).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    PebbleBridge.setEventSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    PebbleBridge.setEventSink(null)
                }
            }
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_METHOD).setMethodCallHandler { call, result ->
            when (call.method) {
                "sendToWatch" -> {
                    val dataMap = call.arguments as? Map<String, Any>
                    if (dataMap != null) {
                        sendDataToWatch(dataMap, result)
                    } else {
                        result.error("INVALID_ARGUMENTS", "Expected Map arguments", null)
                    }
                }
                "isWatchConnected" -> {
                    scope.launch {
                        val infoRetriever = DefaultPebbleInfoRetriever(context)
                        val connected = infoRetriever.getConnectedWatches().first().isNotEmpty()
                        result.success(connected)
                    }
                }
                "startAppOnWatch" -> {
                    scope.launch {
                        pebbleSender.startAppOnTheWatch(watchappUuid)
                        result.success(true)
                    }
                }
                "stopAppOnWatch" -> {
                    scope.launch {
                        pebbleSender.stopAppOnTheWatch(watchappUuid)
                        result.success(true)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    @OptIn(ExperimentalUnsignedTypes::class)
    private fun sendDataToWatch(dataMap: Map<String, Any>, result: MethodChannel.Result) {
        val keys = arrayOf(
            "MSG_ID", "COMMAND", "RAW_TEXT", "NOTE_ID", "SUMMARY_CHUNK",
            "CHUNK_INDEX", "CHUNK_TOTAL", "CHUNK_RESET", "TITLE", "BODY",
            "COMPLETE", "FETCH_NOTE", "SESSION_ID"
        )

        val dict: PebbleDictionary = mutableMapOf<UInt, PebbleDictionaryItem>().apply {
            for ((key, value) in dataMap) {
                val keyIndex = keys.indexOf(key)
                if (keyIndex != -1) {
                    val mappedKey = 10000u + keyIndex.toUInt()
                    when (value) {
                        is Int -> put(mappedKey, PebbleDictionaryItem.Int32(value))
                        is Long -> put(mappedKey, PebbleDictionaryItem.Int32(value.toInt()))
                        is String -> put(mappedKey, PebbleDictionaryItem.Text(value))
                        is Boolean -> put(mappedKey, PebbleDictionaryItem.Int32(if (value) 1 else 0))
                    }
                }
            }
        }

        scope.launch {
            try {
                pebbleSender.sendDataToPebble(watchappUuid, dict)
                result.success(true)
            } catch (e: Exception) {
                result.error("SEND_FAILED", e.message, null)
            }
        }
    }
}
