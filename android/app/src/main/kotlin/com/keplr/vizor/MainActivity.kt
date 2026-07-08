package com.keplr.vizor

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// FlutterFragmentActivity: BiometricPrompt requires a FragmentActivity host.
class MainActivity : FlutterFragmentActivity() {
    private var pendingDocumentExportResult: MethodChannel.Result? = null
    private var pendingDocumentExportTempPath: String? = null
    private var pendingDocumentExportFileName: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            HAPTICS_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "error" -> result.success(performErrorHaptic())
                else -> result.notImplemented()
            }
        }

        val biometricUnlockHandler = BiometricUnlockHandler(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BiometricUnlockHandler.CHANNEL
        ).setMethodCallHandler { call, result ->
            biometricUnlockHandler.handle(call, result)
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CAMERA_PERMISSION_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openSettings" -> result.success(openAppSettings())
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DOCUMENT_EXPORT_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "exportBackupFile" -> exportBackupFile(call.arguments, result)
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PRIVACY_SHIELD_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setSensitiveContentVisible" -> {
                    val visible = (call.arguments as? Map<*, *>)?.get("visible") as? Boolean
                    if (visible == null) {
                        result.error("bad_args", "Expected visible argument.", null)
                    } else {
                        setSensitiveContentVisible(visible)
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Android API 35 but still supported by FlutterActivity.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == DOCUMENT_EXPORT_REQUEST_CODE) {
            finishBackupDocumentExport(resultCode, data)
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun exportBackupFile(arguments: Any?, result: MethodChannel.Result) {
        if (pendingDocumentExportResult != null) {
            result.error(
                "in_progress",
                "A backup export is already in progress.",
                null
            )
            return
        }

        val args = arguments as? Map<*, *>
        val fileName = args?.get("fileName") as? String
        val tempFilePath = args?.get("tempFilePath") as? String
        if (fileName.isNullOrBlank() || tempFilePath.isNullOrBlank()) {
            result.error("bad_args", "Expected fileName and tempFilePath.", null)
            return
        }
        if (!File(tempFilePath).isFile) {
            result.error("missing_file", "Backup export file does not exist.", null)
            return
        }

        pendingDocumentExportResult = result
        pendingDocumentExportTempPath = tempFilePath
        pendingDocumentExportFileName = fileName

        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/octet-stream"
            putExtra(Intent.EXTRA_TITLE, fileName)
        }

        try {
            startActivityForResult(intent, DOCUMENT_EXPORT_REQUEST_CODE)
        } catch (e: Exception) {
            clearPendingDocumentExport()
            result.error("export_unavailable", e.message, null)
        }
    }

    private fun finishBackupDocumentExport(resultCode: Int, data: Intent?) {
        val result = pendingDocumentExportResult ?: return
        val tempFilePath = pendingDocumentExportTempPath
        val fileName = pendingDocumentExportFileName.orEmpty()
        clearPendingDocumentExport()

        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        if (tempFilePath.isNullOrBlank()) {
            result.error("missing_file", "Backup export file does not exist.", null)
            return
        }

        try {
            val input = File(tempFilePath).inputStream()
            val output = contentResolver.openOutputStream(uri, "wt")
                ?: throw IllegalStateException("Could not open the selected document.")
            input.use { source ->
                output.use { destination ->
                    source.copyTo(destination)
                }
            }
            result.success(mapOf("destination" to "android-documents:$fileName"))
        } catch (e: Exception) {
            result.error("export_failed", e.message, null)
        }
    }

    private fun clearPendingDocumentExport() {
        pendingDocumentExportResult = null
        pendingDocumentExportTempPath = null
        pendingDocumentExportFileName = null
    }

    /** REJECT is the platform's error haptic; older APIs report
     *  unhandled so Dart falls back to its own pattern. */
    private fun performErrorHaptic(): Boolean {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.R) {
            return false
        }
        return window.decorView.performHapticFeedback(
            android.view.HapticFeedbackConstants.REJECT
        )
    }

    private fun openAppSettings(): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", packageName, null)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun setSensitiveContentVisible(visible: Boolean) {
        if (visible) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE
            )
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    companion object {
        private const val CAMERA_PERMISSION_CHANNEL = "com.zcash.wallet/camera_permission"
        private const val DOCUMENT_EXPORT_CHANNEL = "com.zcash.wallet/document_export"
        private const val DOCUMENT_EXPORT_REQUEST_CODE = 46012
        private const val HAPTICS_CHANNEL = "com.zcash.wallet/haptics"
        private const val PRIVACY_SHIELD_CHANNEL = "com.zcash.wallet/privacy_shield"
    }
}
