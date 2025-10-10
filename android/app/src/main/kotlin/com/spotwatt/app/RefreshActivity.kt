package com.spotwatt.app

import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.TransparencyMode

class RefreshActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Must be called BEFORE super.onCreate() to prevent black frame
        window.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        window.setDimAmount(0f)
        super.onCreate(savedInstanceState)
    }

    override fun getTransparencyMode(): TransparencyMode {
        // Enable transparent rendering surface (critical for transparent UI)
        return TransparencyMode.transparent
    }

    override fun getInitialRoute(): String {
        return "refresh"
    }
}
