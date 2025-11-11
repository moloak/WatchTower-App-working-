package com.example.project_1

import android.content.Context
import android.graphics.Color
import android.os.Build
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger

class MainActivity : FlutterActivity() {
	private val CHANNEL = "com.example.project_1/overlay"
	private var overlayView: View? = null
	private lateinit var messenger: BinaryMessenger

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		// cache the non-null binary messenger for later use from UI thread callbacks
		messenger = flutterEngine.dartExecutor.binaryMessenger

		MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
			when (call.method) {
				"showWarning" -> {
					val title = call.argument<String>("title") ?: "Warning"
					val message = call.argument<String>("message") ?: ""
					runOnUiThread { showOverlay(title, message, autoHide = true) }
					result.success(null)
				}
				"showLock" -> {
					val title = call.argument<String>("title") ?: "App Locked"
					val message = call.argument<String>("message") ?: ""
					runOnUiThread { showOverlay(title, message, autoHide = false) }
					result.success(null)
				}
				"hideOverlay" -> {
					runOnUiThread { hideOverlay() }
					result.success(null)
				}
				"consumeOverlayDismiss" -> {
					// Return any saved overlay dismiss info (timestamp + package) and clear it
					try {
						val prefs = applicationContext.getSharedPreferences("overlay_prefs", Context.MODE_PRIVATE)
						val ts = prefs.getLong("overlay_dismiss_ts", -1L)
						val pkg = prefs.getString("overlay_dismiss_pkg", null)
						if (ts > 0) {
							// Clear after consuming
							prefs.edit().remove("overlay_dismiss_ts").remove("overlay_dismiss_pkg").apply()
							result.success(mapOf("timestamp" to ts, "packageName" to pkg))
						} else {
							result.success(null)
						}
					} catch (e: Exception) {
						result.error("error", "Failed to read overlay dismiss", e.message)
					}
				}
				else -> result.notImplemented()
			}
		}
	}

	private fun showOverlay(title: String, message: String, autoHide: Boolean) {
		try {
			if (overlayView != null) return

			val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager

			val params = WindowManager.LayoutParams(
				WindowManager.LayoutParams.MATCH_PARENT,
				WindowManager.LayoutParams.WRAP_CONTENT,
				if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
					WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
				else
					WindowManager.LayoutParams.TYPE_PHONE,
				WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
				android.graphics.PixelFormat.TRANSLUCENT
			)
			params.gravity = Gravity.TOP

			val container = LinearLayout(this)
			container.orientation = LinearLayout.VERTICAL
			container.setBackgroundColor(Color.parseColor("#CC000000"))
			container.setPadding(24, 48, 24, 48)

			val titleView = TextView(this)
			titleView.text = title
			titleView.setTextColor(Color.WHITE)
			titleView.textSize = 18f

			val msgView = TextView(this)
			msgView.text = message
			msgView.setTextColor(Color.WHITE)
			msgView.textSize = 14f

			val closeBtn = Button(this)
			closeBtn.text = "Dismiss"
			closeBtn.setOnClickListener {
				// Notify Dart that overlay was hidden by user
				try {
					// Also write a fallback record to SharedPreferences so Dart can detect it
					val prefs = applicationContext.getSharedPreferences("overlay_prefs", Context.MODE_PRIVATE)
					prefs.edit().putLong("overlay_dismiss_ts", System.currentTimeMillis()).putString("overlay_dismiss_pkg", title ?: "").apply()
					MethodChannel(messenger, CHANNEL)
						.invokeMethod("overlayHidden", mapOf("message" to "User dismissed overlay"))
				} catch (e: Exception) {
					// ignore
				}
				hideOverlay()
			}

			container.addView(titleView)
			container.addView(msgView)
			container.addView(closeBtn)

			overlayView = container
			wm.addView(container, params)

			if (autoHide) {
				container.postDelayed({ hideOverlay() }, 5000)
			}
		} catch (e: Exception) {
			// ignore overlay errors
		}
	}

	private fun hideOverlay() {
		try {
			val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
			overlayView?.let { view ->
				wm.removeView(view)
				overlayView = null
			}
		} catch (e: Exception) {
			// ignore
		}
	}
}
