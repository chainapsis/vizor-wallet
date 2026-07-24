package com.keplr.vizor

import java.nio.file.Files
import javax.crypto.SecretKey
import javax.crypto.spec.SecretKeySpec
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class IronwoodMigrationSecureStoreTest {
    private lateinit var directory: java.io.File
    private lateinit var keyProvider: TestKeyProvider
    private lateinit var store: IronwoodMigrationSecureStore

    @Before
    fun setUp() {
        directory = Files.createTempDirectory("ironwood-secure-store").toFile()
        keyProvider = TestKeyProvider()
        store = IronwoodMigrationSecureStore(
            keyProvider = keyProvider,
            directory = directory,
        )
    }

    @After
    fun tearDown() {
        directory.deleteRecursively()
    }

    @Test
    fun manifestAndOutboxRoundTripWithoutPlaintextOnDisk() {
        val manifest = """{"network":"test","credentialHex":"super-secret"}"""
        val outbox = byteArrayOf(1, 3, 3, 7, 9)

        store.writeManifest("test", "account-1", manifest)
        store.writeOutboxBatch("test", "account-1", "batch-1", outbox)

        assertEquals(manifest, store.readManifest("test", "account-1"))
        assertArrayEquals(
            outbox,
            store.readOutboxBatch("test", "account-1", "batch-1"),
        )
        val diskBytes = directory.listFiles()!!.flatMap { it.readBytes().asIterable() }
            .toByteArray()
        assertFalse(
            diskBytes.toString(Charsets.UTF_8).contains("super-secret"),
        )
    }

    @Test
    fun authenticatedEncryptionRejectsTamperedCiphertext() {
        store.writeManifest("test", "account-1", """{"value":"one"}""")
        val file = directory.listFiles()!!.single { it.name.endsWith(".bin") }
        val tampered = file.readBytes()
        tampered[tampered.lastIndex] = (tampered.last().toInt() xor 1).toByte()
        file.writeBytes(tampered)

        assertThrows(IronwoodMigrationSecureStoreException::class.java) {
            store.readManifest("test", "account-1")
        }
    }

    @Test
    fun accountRevocationRemovesOnlyTheExactScope() {
        store.writeManifest("test", "account-1", """{"value":"one"}""")
        store.writeOutboxBatch("test", "account-1", "batch-1", byteArrayOf(1))
        store.writeManifest("test", "account-10", """{"value":"ten"}""")
        store.writeOutboxBatch("main", "account-1", "batch-2", byteArrayOf(2))

        store.revokeAccount("test", "account-1")

        assertNull(store.readManifest("test", "account-1"))
        assertNull(store.readOutboxBatch("test", "account-1", "batch-1"))
        assertEquals("""{"value":"ten"}""", store.readManifest("test", "account-10"))
        assertArrayEquals(
            byteArrayOf(2),
            store.readOutboxBatch("main", "account-1", "batch-2"),
        )
    }

    @Test
    fun revokeAllDeletesRecordsAndCryptographicKey() {
        store.writeManifest("test", "account-1", """{"value":"one"}""")

        store.revokeAll()

        assertTrue(directory.listFiles().isNullOrEmpty())
        assertTrue(keyProvider.deleted)
    }

    @Test
    fun liveStoreRecoversInterruptedBackupBeforeAccountRevocation() {
        store.writeOutboxBatch("test", "account-1", "batch-1", byteArrayOf(1))
        val record = directory.listFiles()!!.single { it.name.endsWith(".bin") }
        assertTrue(record.renameTo(java.io.File(directory, "${record.name}.bak")))

        store.revokeAccount("test", "account-1")

        assertTrue(directory.listFiles().isNullOrEmpty())
    }

    @Test
    fun outboxCodecPreservesBinaryPayload() {
        val encoded = encodeIronwoodOutboxMap(
            mapOf(
                "batchId" to "batch-1",
                "items" to listOf(mapOf("rawTransaction" to byteArrayOf(1, 2, 3))),
            ),
        )

        assertTrue(encoded.isNotEmpty())
        val decoded = decodeIronwoodOutboxMap(encoded)
        val items = decoded["items"] as List<*>
        val item = items.single() as Map<*, *>
        assertArrayEquals(byteArrayOf(1, 2, 3), item["rawTransaction"] as ByteArray)
    }

    private class TestKeyProvider : IronwoodMigrationKeyProvider {
        private val key = SecretKeySpec(ByteArray(32) { it.toByte() }, "AES")
        var deleted = false

        override fun getOrCreate(): SecretKey = key

        override fun delete() {
            deleted = true
        }
    }
}
