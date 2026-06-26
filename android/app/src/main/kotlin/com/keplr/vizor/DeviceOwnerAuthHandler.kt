package com.keplr.vizor

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Device-owner verification for destructive local actions.
 *
 * Passcode-only by design: this gate must never be satisfied by a fingerprint
 * or face scan, so it requests DEVICE_CREDENTIAL (device PIN / password /
 * pattern) exclusively, never BIOMETRIC_*. This does not touch the wallet
 * passcode escrow. Android 11+ shows the device-credential BiometricPrompt;
 * Android 10 and lower use the system device credential confirmation intent
 * because a DEVICE_CREDENTIAL-only BiometricPrompt is not supported there.
 */
class DeviceOwnerAuthHandler(private val activity: FragmentActivity) {
    private var pendingCredentialResult: MethodChannel.Result? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // Fallback mirrors the Dart canonical kWalletResetDeviceAuthReason;
            // the Dart side always sends "reason", so this default is defensive only.
            "verify" -> verify(
                call.argument<String>("reason") ?: "Confirm reset Vizor",
                result
            )
            else -> result.notImplemented()
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != DEVICE_CREDENTIAL_REQUEST_CODE) return false
        val result = pendingCredentialResult ?: return true
        pendingCredentialResult = null
        result.success(resultCode == Activity.RESULT_OK)
        return true
    }

    private fun verify(reason: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            verifyWithDeviceCredentialPrompt(reason, result)
        } else {
            verifyWithDeviceCredentialIntent(reason, result)
        }
    }

    private fun verifyWithDeviceCredentialPrompt(reason: String, result: MethodChannel.Result) {
        val authenticators = DEVICE_CREDENTIAL
        val status = BiometricManager.from(activity).canAuthenticate(authenticators)
        if (status != BiometricManager.BIOMETRIC_SUCCESS) {
            result.error("unavailable", "Device authentication is not available.", null)
            return
        }

        val replied = AtomicBoolean(false)
        fun replySuccess(value: Boolean) {
            if (replied.compareAndSet(false, true)) result.success(value)
        }
        fun replyError(code: String, message: String?) {
            if (replied.compareAndSet(false, true)) result.error(code, message, null)
        }

        val prompt = BiometricPrompt(
            activity,
            ContextCompat.getMainExecutor(activity),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(
                    authResult: BiometricPrompt.AuthenticationResult
                ) {
                    replySuccess(true)
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    when (errorCode) {
                        BiometricPrompt.ERROR_USER_CANCELED,
                        BiometricPrompt.ERROR_NEGATIVE_BUTTON,
                        BiometricPrompt.ERROR_CANCELED ->
                            replySuccess(false)
                        BiometricPrompt.ERROR_NO_DEVICE_CREDENTIAL,
                        BiometricPrompt.ERROR_NO_BIOMETRICS,
                        BiometricPrompt.ERROR_HW_NOT_PRESENT,
                        BiometricPrompt.ERROR_HW_UNAVAILABLE ->
                            replyError("unavailable", errString.toString())
                        else -> replyError("failed", errString.toString())
                    }
                }
            }
        )

        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(reason)
            .setAllowedAuthenticators(authenticators)
            .setConfirmationRequired(true)
            .build()
        prompt.authenticate(info)
    }

    private fun verifyWithDeviceCredentialIntent(reason: String, result: MethodChannel.Result) {
        val keyguard = activity.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        if (keyguard?.isDeviceSecure != true) {
            result.error("unavailable", "Device credential is not configured.", null)
            return
        }
        if (pendingCredentialResult != null) {
            result.error("failed", "Device authentication is already in progress.", null)
            return
        }
        val intent: Intent? = keyguard.createConfirmDeviceCredentialIntent(reason, null)
        if (intent == null) {
            result.error("unavailable", "Device credential prompt is not available.", null)
            return
        }

        pendingCredentialResult = result
        activity.startActivityForResult(intent, DEVICE_CREDENTIAL_REQUEST_CODE)
    }

    companion object {
        const val CHANNEL = "com.zcash.wallet/device_owner_auth"
        private const val DEVICE_CREDENTIAL_REQUEST_CODE = 9301
    }
}
