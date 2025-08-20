package com.example.price_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.content.SharedPreferences
import es.antonborri.home_widget.HomeWidgetPlugin

class PriceWidgetProvider : AppWidgetProvider() {
    
    companion object {
        const val ACTION_WIDGET_CLICK = "com.example.price_app.WIDGET_CLICK"
        
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
        // Enter relevant functionality for when the first widget is created
    }

    override fun onDisabled(context: Context) {
        // Enter relevant functionality for when the last widget is disabled
    }

    private fun createRemoteViews(context: Context, widgetData: SharedPreferences): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.price_widget_layout)
        
        val currentPrice = widgetData.getString("current_price", "-- ct/kWh") ?: "-- ct/kWh"
        android.util.Log.d("PriceWidget", "Current price from SharedPrefs: $currentPrice")
        val minPrice = widgetData.getString("min_price", "--") ?: "--"
        val maxPrice = widgetData.getString("max_price", "--") ?: "--"
        val minTime = widgetData.getString("min_time", "--:--") ?: "--:--"
        val maxTime = widgetData.getString("max_time", "--:--") ?: "--:--"
        val priceStatus = widgetData.getString("price_status", "unknown") ?: "unknown"
        val priceTrend = widgetData.getString("price_trend", "stable") ?: "stable"
        val lastUpdate = widgetData.getString("last_update", "") ?: ""
        
        views.setTextViewText(R.id.current_price, currentPrice)
        views.setTextViewText(R.id.min_price, "Min: $minPrice ct")
        views.setTextViewText(R.id.max_price, "Max: $maxPrice ct")
        views.setTextViewText(R.id.min_time, "um $minTime Uhr")
        views.setTextViewText(R.id.max_time, "um $maxTime Uhr")
        views.setTextViewText(R.id.last_update, lastUpdate)
        
        // Set price color based on status
        val priceColor = when (priceStatus) {
            "low" -> 0xFF4CAF50.toInt() // Green
            "medium" -> 0xFFFF9800.toInt() // Orange
            "high" -> 0xFFF44336.toInt() // Red
            else -> 0xFF757575.toInt() // Grey
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
        
        // Set trend color based on direction and strength
        val trendColor = when (priceTrend) {
            "strongly_rising" -> 0xFFD32F2F.toInt()  // Dunkelrot für stark steigend
            "slightly_rising" -> 0xFFFF9800.toInt()  // Orange für leicht steigend
            "slightly_falling" -> 0xFF66BB6A.toInt() // Hellgrün für leicht fallend
            "strongly_falling" -> 0xFF388E3C.toInt() // Dunkelgrün für stark fallend
            else -> 0xFF666666.toInt()               // Grau für stabil
        }
        views.setTextColor(R.id.price_trend, trendColor)
        
        // Set status indicator
        val statusText = when (priceStatus) {
            "low" -> "✓ Günstig"
            "medium" -> "○ Mittel"
            "high" -> "✗ Teuer"
            else -> ""
        }
        views.setTextViewText(R.id.price_status, statusText)
        views.setTextColor(R.id.price_status, priceColor)
        
        // Set price icon (same as in app)
        val iconText = when (priceStatus) {
            "low" -> "💡" // Glühbirne für günstig
            "medium" -> "🕐" // Uhr für mittel
            "high" -> "⚠️" // Warnung für teuer
            else -> ""
        }
        views.setTextViewText(R.id.price_icon, iconText)
        
        return views
    }
}