package com.example.price_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class ScreenUnlockReceiver : BroadcastReceiver() {
    
    override fun onReceive(context: Context, intent: Intent) {
        // Multiple log methods to ensure visibility
        android.util.Log.e("ScreenUnlockReceiver", "=== BROADCAST RECEIVED ===")
        android.util.Log.e("ScreenUnlockReceiver", "Action: ${intent.action}")
        System.out.println("ScreenUnlockReceiver: BROADCAST RECEIVED: ${intent.action}")
        
        when (intent.action) {
            Intent.ACTION_USER_PRESENT -> {
                android.util.Log.e("ScreenUnlockReceiver", "USER_PRESENT detected!")
                System.out.println("ScreenUnlockReceiver: USER_PRESENT detected!")
                
                // Force widget update
                try {
                    PriceWidgetProvider.forceUpdate(context)
                    android.util.Log.e("ScreenUnlockReceiver", "Widget update SUCCESS")
                    System.out.println("ScreenUnlockReceiver: Widget update SUCCESS")
                } catch (e: Exception) {
                    android.util.Log.e("ScreenUnlockReceiver", "Widget update FAILED", e)
                    System.out.println("ScreenUnlockReceiver: Widget update FAILED: $e")
                }
            }
            else -> {
                android.util.Log.e("ScreenUnlockReceiver", "Unhandled action: ${intent.action}")
                System.out.println("ScreenUnlockReceiver: Unhandled action: ${intent.action}")
            }
        }
    }
}