package com.keplr.vizor

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Passcode escrow behind the current biometric set — the Android
 * counterpart of the iOS keychain item. The passcode is AES-GCM
 * encrypted with a Keystore key that requires BiometricPrompt
 * authentication per use and is permanently invalidated when the
 * biometric enrollment changes; the ciphertext lives in app-private
 * SharedPreferences (the key, not the file, carries the protection).
 */
class BiometricUnlockHandler(private val activity: FragmentActivity) {
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "availability" -> result.success(availability())
            "enable" -> {
                val passcode = call.argument<String>("passcode")
                if (passcode.isNullOrEmpty()) {
                    result.error("failed", "passcode is required", null)
                } else {
                    enable(passcode, result)
                }
            }
            "disable" -> disable(result)
            "read" -> read(call.argument<String>("reason") ?: "Unlock your wallet", result)
            else -> result.notImplemented()
        }
    }

    private fun availability(): Map<String, Any> {
        val status = BiometricManager.from(activity).canAuthenticate(BIOMETRIC_STRONG)
        val supported = status != BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE &&
            status != BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE &&
            status != BiometricManager.BIOMETRIC_ERROR_UNSUPPORTED
        val enrolled = status == BiometricManager.BIOMETRIC_SUCCESS
        // Android does not expose the sensor modality; fingerprint is
        // the overwhelmingly common case and drives copy only.
        val kind = if (supported) "fingerprint" else "none"
        return mapOf("supported" to supported, "enrolled" to enrolled, "kind" to kind)
    }

    private fun prefs() =
        activity.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun keyStore(): KeyStore =
        KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    private fun createKey(): SecretKey {
        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore"
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setUserAuthenticationRequired(true)
                .setInvalidatedByBiometricEnrollment(true)
                .build()
        )
        return generator.generateKey()
    }

    private fun loadKey(): SecretKey? =
        keyStore().getKey(KEY_ALIAS, null) as? SecretKey

    private fun deleteKey() {
        val store = keyStore()
        if (store.containsAlias(KEY_ALIAS)) store.deleteAlias(KEY_ALIAS)
    }

    private fun enable(passcode: String, result: MethodChannel.Result) {
        try {
            // Fresh key per enable so a previously invalidated key never
            // lingers; encryption itself needs a prompt too, so wrap the
            // init cipher in BiometricPrompt below.
            deleteKey()
            val key = createKey()
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, key)

            authenticate(
                title = "Enable biometric unlock",
                cipher = cipher,
                result = result
            ) { authedCipher ->
                val ciphertext = authedCipher.doFinal(passcode.toByteArray(Charsets.UTF_8))
                prefs().edit()
                    .putString(PREF_CIPHERTEXT, Base64.encodeToString(ciphertext, Base64.NO_WRAP))
                    .putString(PREF_IV, Base64.encodeToString(authedCipher.iv, Base64.NO_WRAP))
                    .apply()
                result.success(null)
            }
        } catch (e: Exception) {
            result.error("failed", e.message, null)
        }
    }

    private fun disable(result: MethodChannel.Result) {
        try {
            prefs().edit().clear().apply()
            deleteKey()
            result.success(null)
        } catch (e: Exception) {
            result.error("failed", e.message, null)
        }
    }

    private fun read(reason: String, result: MethodChannel.Result) {
        val stored = prefs().getString(PREF_CIPHERTEXT, null)
        val ivRaw = prefs().getString(PREF_IV, null)
        if (stored == null || ivRaw == null) {
            result.error("invalidated", null, null)
            return
        }

        val cipher: Cipher
        try {
            val key = loadKey()
            if (key == null) {
                result.error("invalidated", null, null)
                return
            }
            cipher = Cipher.getInstance(TRANSFORMATION)
            val iv = Base64.decode(ivRaw, Base64.NO_WRAP)
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv))
        } catch (e: KeyPermanentlyInvalidatedException) {
            // Biometric enrollment changed; the escrow is gone for good.
            prefs().edit().clear().apply()
            deleteKey()
            result.error("invalidated", null, null)
            return
        } catch (e: Exception) {
            result.error("failed", e.message, null)
            return
        }

        authenticate(title = reason, cipher = cipher, result = result) { authedCipher ->
            val ciphertext = Base64.decode(stored, Base64.NO_WRAP)
            val passcode = String(authedCipher.doFinal(ciphertext), Charsets.UTF_8)
            result.success(passcode)
        }
    }

    /** Shows BiometricPrompt bound to [cipher]; [onAuthed] runs with the
     *  authorized cipher on success. Failure paths reply on [result]. */
    private fun authenticate(
        title: String,
        cipher: Cipher,
        result: MethodChannel.Result,
        onAuthed: (Cipher) -> Unit,
    ) {
        val replied = java.util.concurrent.atomic.AtomicBoolean(false)
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
                    if (!replied.compareAndSet(false, true)) return
                    val authedCipher = authResult.cryptoObject?.cipher
                    if (authedCipher == null) {
                        result.error("failed", "missing crypto object", null)
                        return
                    }
                    try {
                        onAuthed(authedCipher)
                    } catch (e: Exception) {
                        result.error("failed", e.message, null)
                    }
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    when (errorCode) {
                        BiometricPrompt.ERROR_USER_CANCELED,
                        BiometricPrompt.ERROR_NEGATIVE_BUTTON,
                        BiometricPrompt.ERROR_CANCELED ->
                            replyError("cancelled", null)
                        BiometricPrompt.ERROR_LOCKOUT,
                        BiometricPrompt.ERROR_LOCKOUT_PERMANENT ->
                            replyError("lockedOut", errString.toString())
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
            .setTitle(title)
            .setAllowedAuthenticators(BIOMETRIC_STRONG)
            // The in-app passcode numpad is the fallback path.
            .setNegativeButtonText("Use passcode")
            .build()
        prompt.authenticate(info, BiometricPrompt.CryptoObject(cipher))
    }

    companion object {
        const val CHANNEL = "com.zcash.wallet/biometric_unlock"
        private const val PREFS_NAME = "vizor_biometric_unlock"
        private const val PREF_CIPHERTEXT = "escrow_ciphertext"
        private const val PREF_IV = "escrow_iv"
        private const val KEY_ALIAS = "vizor-biometric-unlock-escrow"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
    }
}
