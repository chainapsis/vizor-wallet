package com.keplr.vizor

import android.content.Context
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], manifest = Config.NONE)
class NativeStringsTest {
    private val context: Context = RuntimeEnvironment.getApplication()

    @Test fun usesEnglishUntilDartSendsALanguage() {
        assertEquals("Use passcode", NativeStrings.text(context, NativeString.nativeBiometricUsePasscode))
    }

    @Test fun followsTheStoredAppLanguage() {
        NativeStrings.setLanguage(context, "ko")
        assertEquals("암호 사용", NativeStrings.text(context, NativeString.nativeBiometricUsePasscode))
        NativeStrings.setLanguage(context, "fr")
        assertEquals("Use passcode", NativeStrings.text(context, NativeString.nativeBiometricUsePasscode))
    }

    @Test fun fillsPlaceholders() {
        assertEquals(
            "Ledger 操作失败：Unknown",
            NativeStrings.text("zh", NativeString.nativeLedgerOperationFailed, "reason" to "Unknown"),
        )
    }
}
