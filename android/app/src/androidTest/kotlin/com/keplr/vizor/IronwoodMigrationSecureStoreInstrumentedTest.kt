package com.keplr.vizor

import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

class IronwoodMigrationSecureStoreInstrumentedTest {
    private lateinit var directory: File
    private lateinit var keyProvider: AndroidKeystoreIronwoodMigrationKeyProvider

    @Before
    fun setUp() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        directory = File(
            context.noBackupFilesDir,
            "ironwood-secure-store-test-${UUID.randomUUID()}",
        )
        keyProvider = AndroidKeystoreIronwoodMigrationKeyProvider(
            alias = "com.keplr.vizor.ironwood-migration-test.${UUID.randomUUID()}",
        )
    }

    @After
    fun tearDown() {
        directory.deleteRecursively()
        keyProvider.delete()
    }

    @Test
    fun manifestRoundTripsWithRandomizedEncryptionRequiredKey() {
        val store = IronwoodMigrationSecureStore(
            keyProvider = keyProvider,
            directory = directory,
        )
        val manifest = """{"network":"test","credentialHex":"super-secret"}"""

        store.writeManifest("test", "account-1", manifest)

        assertEquals(manifest, store.readManifest("test", "account-1"))
    }
}
