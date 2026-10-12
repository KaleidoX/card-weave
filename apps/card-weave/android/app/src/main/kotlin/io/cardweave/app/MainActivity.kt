package io.cardweave.app

import android.content.Context
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterShellArgs
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var systemContacts: SystemContacts? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        systemContacts = SystemContacts(this, MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "io.cardweave/system_contacts"))
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (systemContacts?.onPermissionResult(requestCode) == true) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        systemContacts?.close()
        super.onDestroy()
    }

    companion object {
        init { System.loadLibrary("card_weave_mobile") }
        @JvmStatic private external fun initRustls(context: Context)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        initRustls(applicationContext)
        super.onCreate(savedInstanceState)
    }

    override fun getFlutterShellArgs(): FlutterShellArgs = super.getFlutterShellArgs().apply {
        if (BuildConfig.SOFTWARE_RENDERING || intent.getBooleanExtra("enable-software-rendering", false)) add(FlutterShellArgs.ARG_ENABLE_SOFTWARE_RENDERING)
        if (BuildConfig.SOFTWARE_RENDERING || intent.getBooleanExtra("disable-impeller", false)) add(FlutterShellArgs.ARG_DISABLE_IMPELLER)
    }
}
