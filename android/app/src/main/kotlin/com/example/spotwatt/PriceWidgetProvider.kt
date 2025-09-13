package com.example.spotwatt

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.widget.RemoteViews
import android.content.SharedPreferences
import android.content.res.Configuration
import es.antonborri.home_widget.HomeWidgetPlugin

class PriceWidgetProvider : AppWidgetProvider() {
    
    companion object {
        const val ACTION_WIDGET_CLICK = "com.example.spotwatt.WIDGET_CLICK"
        private var userPresentReceiver: BroadcastReceiver? = null

        fun forceUpdate(context: Context) {
            val intent = Intent(context, PriceWidgetProvider::class.java)
            intent.action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            val widgetManager = AppWidgetManager.getInstance(context)
            val widgetIds = widgetManager.getAppWidgetIds(
                ComponentName(context, PriceWidgetProvider::class.java)
            )
            intent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, widgetIds)
            context.sendBroadcast(intent)
        }
    }
    
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        android.util.Log.d("PriceWidget", "onUpdate called with ${appWidgetIds.size} widgets")
        for (appWidgetId in appWidgetIds) {
            val widgetData = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            android.util.Log.d("PriceWidget", "Reading SharedPreferences for widget $appWidgetId")
            val views = createRemoteViews(context, widgetData)
            
            // Add click listener to widget for manual refresh
            val intent = Intent(context, PriceWidgetProvider::class.java)
            intent.action = ACTION_WIDGET_CLICK
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_layout, pendingIntent)
            
            appWidgetManager.updateAppWidget(appWidgetId, views)
            android.util.Log.d("PriceWidget", "Widget $appWidgetId updated")
        }
        android.util.Log.d("PriceWidget", "onUpdate completed")
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        
        when (intent.action) {
            ACTION_WIDGET_CLICK -> {
                // Open app and let Flutter handle the update
                val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                launchIntent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                launchIntent?.putExtra("widget_clicked", true)
                context.startActivity(launchIntent)
                
                // Don't update here - let Flutter do it with fresh data
            }
        }
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        android.util.Log.d("PriceWidget", "Widget enabled - registering USER_PRESENT receiver")
        
        try {
            val filter = IntentFilter().apply {
                addAction(Intent.ACTION_USER_PRESENT)
            }
            
            userPresentReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    android.util.Log.e("PriceWidget", "USER_PRESENT received in onEnabled receiver!")
                    android.util.Log.e("PriceWidget", "Action: ${intent?.action}")
                    
                    if (intent?.action == Intent.ACTION_USER_PRESENT) {
                        android.util.Log.e("PriceWidget", "Updating widget from USER_PRESENT")
                        context?.let { ctx ->
                            forceUpdate(ctx)
                        }
                    }
                }
            }
            
            context.applicationContext.registerReceiver(userPresentReceiver, filter)
            android.util.Log.e("PriceWidget", "USER_PRESENT receiver registered successfully in onEnabled")
        } catch (e: Exception) {
            android.util.Log.e("PriceWidget", "Failed to register USER_PRESENT receiver in onEnabled", e)
        }
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        android.util.Log.d("PriceWidget", "Widget disabled - unregistering USER_PRESENT receiver")
        
        try {
            userPresentReceiver?.let { receiver ->
                context.applicationContext.unregisterReceiver(receiver)
                android.util.Log.d("PriceWidget", "USER_PRESENT receiver unregistered successfully")
                userPresentReceiver = null
            }
        } catch (e: Exception) {
            android.util.Log.e("PriceWidget", "Failed to unregister USER_PRESENT receiver", e)
        }
    }

    private fun createRemoteViews(context: Context, widgetData: SharedPreferences): RemoteViews {
        // Widget always follows system theme - app theme settings only affect the app itself
        val isSystemDarkMode = (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        val views = RemoteViews(context.packageName, R.layout.price_widget_layout)
        android.util.Log.d("PriceWidget", "Using system theme, system is dark: $isSystemDarkMode")
        
        val currentPrice = widgetData.getString("current_price", "-- ct/kWh") ?: "-- ct/kWh"
        val timeSlot = widgetData.getString("time_slot", "17:00") ?: "17:00"
        android.util.Log.d("PriceWidget", "Current price from SharedPrefs: $currentPrice")
        val minPrice = widgetData.getString("min_price", "--") ?: "--"
        val maxPrice = widgetData.getString("max_price", "--") ?: "--"
        val minTime = widgetData.getString("min_time", "--:--") ?: "--:--"
        val maxTime = widgetData.getString("max_time", "--:--") ?: "--:--"
        val priceStatus = widgetData.getString("price_status", "unknown") ?: "unknown"
        val priceTrend = widgetData.getString("price_trend", "stable") ?: "stable"
        val lastUpdate = widgetData.getString("last_update", "") ?: ""
        
        views.setTextViewText(R.id.current_price, currentPrice)

        // Update AKTUELL label with dynamic time slot
        try {
            val aktuelLabel = "AKTUELL (bis $timeSlot):"
            views.setTextViewText(R.id.aktuell_label, aktuelLabel)
        } catch (e: Exception) {
            android.util.Log.e("PriceWidget", "Error updating AKTUELL label", e)
            // Fallback to just "AKTUELL" if time slot update fails
            views.setTextViewText(R.id.aktuell_label, "AKTUELL")
        }
        // MIN/MAX display temporarily removed to reduce text clutter
        // views.setTextViewText(R.id.min_price, "$minPrice ct")
        // views.setTextViewText(R.id.max_price, "$maxPrice ct")
        // views.setTextViewText(R.id.min_time, "$minTime Uhr")
        // views.setTextViewText(R.id.max_time, "$maxTime Uhr")
        // Add "Aktualisiert:" prefix to the time
        val updateText = if (lastUpdate.isNotEmpty()) "Aktualisiert: $lastUpdate" else ""
        views.setTextViewText(R.id.last_update, updateText)

        // No time slot needed anymore - moved to "Jetzt" label
        
        // Set price color based on status and system dark mode
        val priceColor = when (priceStatus) {
            "low" -> if (isSystemDarkMode) 0xFF66BB6A.toInt() else 0xFF4CAF50.toInt() // Light/Dark Green
            "medium" -> if (isSystemDarkMode) 0xFFFFB74D.toInt() else 0xFFFF9800.toInt() // Light/Dark Orange
            "high" -> if (isSystemDarkMode) 0xFFEF5350.toInt() else 0xFFF44336.toInt() // Light/Dark Red
            else -> if (isSystemDarkMode) 0xFFAAAAAA.toInt() else 0xFF757575.toInt() // Light/Dark Grey
        }
        views.setTextColor(R.id.current_price, priceColor)

        // Set trend arrow with 5 levels
        val trendText = when (priceTrend) {
            "strongly_rising" -> "↑"     // Stark steigend
            "slightly_rising" -> "↗"     // Leicht steigend
            "slightly_falling" -> "↘"    // Leicht fallend
            "strongly_falling" -> "↓"    // Stark fallend
            else -> "→"                  // Stabil
        }
        views.setTextViewText(R.id.price_trend, trendText)

        // Set trend color based on direction, strength and system dark mode
        val trendColor = when (priceTrend) {
            "strongly_rising" -> if (isSystemDarkMode) 0xFFEF5350.toInt() else 0xFFD32F2F.toInt()  // Light/Dark Red
            "slightly_rising" -> if (isSystemDarkMode) 0xFFFFB74D.toInt() else 0xFFFF9800.toInt()  // Light/Dark Orange
            "slightly_falling" -> if (isSystemDarkMode) 0xFF66BB6A.toInt() else 0xFF66BB6A.toInt() // Light Green (same)
            "strongly_falling" -> if (isSystemDarkMode) 0xFF4CAF50.toInt() else 0xFF388E3C.toInt() // Light/Dark Green
            else -> if (isSystemDarkMode) 0xFFAAAAAA.toInt() else 0xFF666666.toInt()               // Light/Dark Grey
        }
        views.setTextColor(R.id.price_trend, trendColor)

        // Note: Static text colors are handled automatically by Android using layout/layout-night
        // Only dynamic colors (price status, trend) need to be set programmatically

        // Set status indicator with emoji smileys
        val statusText = when (priceStatus) {
            "low" -> "😊"     // Grün-lachend für günstig
            "medium" -> "😐"  // Orange-neutral für mittel
            "high" -> "😞"    // Rot-traurig für teuer
            else -> ""
        }
        views.setTextViewText(R.id.price_status, statusText)
        views.setTextColor(R.id.price_status, priceColor)
        
        // Set price icon with spacing
        val iconText = when (priceStatus) {
            "low" -> "💡 " // Glühbirne mit Leerzeichen für günstig
            "medium" -> "" // Kein Icon für mittel
            "high" -> "" // Kein Warnsymbol - redundant zu "✗ Teuer"
            else -> ""
        }
        views.setTextViewText(R.id.price_icon, iconText)
        
        return views
    }
}