package com.mindcorder.mindcorder_app

import android.content.Context
import io.rebble.pebblekit2.client.BasePebbleListenerService
import io.rebble.pebblekit2.client.PebbleKit
import io.rebble.pebblekit2.client.PebbleDictionary
import java.util.UUID

class PebbleListenerService : BasePebbleListenerService() {
    override val watchappUuid: UUID = UUID.fromString("E2ECDBEB-2D2B-412F-AD1D-9059180EBC47")

    override fun onMessageReceived(context: Context, data: PebbleDictionary, transactionId: Int) {
        // Forward the message to the bridge
        PebbleBridge.handleIncomingMessage(data)
        
        // Send ACK back to watch to prevent Bluetooth timeout/retransmissions
        PebbleKit.sendAckToPebble(context, transactionId)
    }
}
