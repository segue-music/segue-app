package io.github.mateusguilherme.segue

import android.app.UiModeManager
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// AudioServiceActivity: the screen runs on audio_service's Flutter engine. With a plain
// FlutterActivity, audio_service started an engine of its own, and with it a second copy of the
// whole app, hidden, which connected to the hub as the same device.
class MainActivity : AudioServiceActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        holdPhoneUpright(resources.configuration)
    }

    // The activity handles its own configuration changes (AndroidManifest.xml's configChanges), so
    // a foldable opened or closed comes here, not to a new onCreate.
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        holdPhoneUpright(newConfig)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // What the app asks of Android itself (lib/device.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "segue/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "isTelevision" -> result.success(isTelevision())
                "deviceName" -> result.success(deviceName())
                "hasMobileData" -> result.success(hasMobileData())
                "keepScreenOn" -> {
                    keepScreenOn(call.arguments as Boolean)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isTelevision(): Boolean =
        getSystemService(UiModeManager::class.java)?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION

    /** Whether the device has a mobile network, and with it mobile data: a phone, a tablet with a SIM; not a TV. */
    private fun hasMobileData(): Boolean = packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY)

    /** Keeps the screen on while the window shows, or lets it go off again (lib/device.dart's KeepScreenOn). */
    private fun keepScreenOn(on: Boolean) {
        if (on) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    /**
     * A phone stays in portrait, as the app's narrow layout is made for it (the pages' 600 dp). A
     * tablet turns as it is held, and a TV stays as it is, though a 1080p TV is 540 dp at its
     * smallest, like a phone.
     */
    private fun holdPhoneUpright(configuration: Configuration) {
        val phone = configuration.smallestScreenWidthDp < 600 && !isTelevision()
        requestedOrientation =
            if (phone) ActivityInfo.SCREEN_ORIENTATION_PORTRAIT else ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
    }

    /** The name the owner gave the device in the system settings, or else its maker and model. */
    private fun deviceName(): String {
        val named = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
            Settings.Global.getString(contentResolver, Settings.Global.DEVICE_NAME)
        } else {
            null
        }
        if (!named.isNullOrBlank()) return named
        val model = Build.MODEL
        return if (model.startsWith(Build.MANUFACTURER, ignoreCase = true)) model else "${Build.MANUFACTURER} $model"
    }
}
