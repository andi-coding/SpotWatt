package com.example.price_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Bundle
import android.content.Intent
import android.appwidget.AppWidgetManager
import android.content.ComponentName

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.price_app/widget"
    private var methodChannel: MethodChannel? = null
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            android.util.Log.d("MainActivity", "Received method call: ${call.method}")
            when (call.method) {
                "forceUpdateWidget" -> {
                    android.util.Log.d("MainActivity", "Executing forceUpdateWidget")
                    forceUpdateWidget()
                    result.success(true)
                    android.util.Log.d("MainActivity", "forceUpdateWidget completed")
                }
                else -> {
                    android.util.Log.d("MainActivity", "Method not implemented: ${call.method}")
                    result.notImplemented()
                }
            }
        }
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        android.util.Log.d("MainActivity", "onCreate called")
        android.util.Log.d("MainActivity", "Intent extras: ${intent?.extras}")
        android.util.Log.d("MainActivity", "widget_clicked: ${intent?.getBooleanExtra("widget_clicked", false)}")
        checkForWidgetClick()
    }
    
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        android.util.Log.d("MainActivity", "onNewIntent called")
        android.util.Log.d("MainActivity", "Intent extras: ${intent.extras}")
        android.util.Log.d("MainActivity", "widget_clicked: ${intent.getBooleanExtra("widget_clicked", false)}")
        setIntent(intent) // Important: Update the intent
        checkForWidgetClick()
    }
    
    private fun checkForWidgetClick() {
        if (intent?.getBooleanExtra("widget_clicked", false) == true) {
            android.util.Log.d("MainActivity", "Widget was clicked, methodChannel = $methodChannel")
            
            // If methodChannel is not ready yet, wait for Flutter to initialize
            if (methodChannel == null) {
                android.util.Log.d("MainActivity", "MethodChannel not ready, waiting...")
                // Store the flag for later
                // Will be checked again after Flutter engine is configured
            } else {
                // Notify Flutter that widget was clicked
                android.util.Log.d("MainActivity", "Notifying Flutter about widget click")
                methodChannel?.invokeMethod("widgetClicked", null)
                // Reset the flag
                intent?.removeExtra("widget_clicked")
            }
        }
    }
    
    private fun forceUpdateWidget() {
        android.util.Log.d("MainActivity", "forceUpdateWidget called")
        val intent = Intent(this, PriceWidgetProvider::class.java)
        intent.action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
        val widgetManager = AppWidgetManager.getInstance(this)
        val widgetIds = widgetManager.getAppWidgetIds(
            ComponentName(this, PriceWidgetProvider::class.java)
        )
        android.util.Log.d("MainActivity", "Found ${widgetIds.size} widgets to update")
        intent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, widgetIds)
        sendBroadcast(intent)
        android.util.Log.d("MainActivity", "Broadcast sent to update widgets")
    }
}
