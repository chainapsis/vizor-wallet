package com.keplr.vizor

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileOutputStream
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.concurrent.locks.ReentrantLock
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlin.concurrent.withLock

internal interface IronwoodMigrationKeyProvider {
    fun getOrCreate(): SecretKey
    fun delete()
}

internal class AndroidKeystoreIronwoodMigrationKeyProvider(
    private val alias: String = KEY_ALIAS,
) : IronwoodMigrationKeyProvider {
    override fun getOrCreate(): SecretKey = KEYSTORE_LOCK.withLock {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (keyStore.getKey(alias, null) as? SecretKey)?.let { return it }

        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            ANDROID_KEYSTORE,
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                alias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(KEY_SIZE_BITS)
                .setRandomizedEncryptionRequired(true)
                .setUserAuthenticationRequired(false)
                .build(),
        )
        generator.generateKey()
    }

    override fun delete() = KEYSTORE_LOCK.withLock {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        if (keyStore.containsAlias(alias)) {
            keyStore.deleteEntry(alias)
        }
    }

    private companion object {
        const val ANDROID_KEYSTORE = "AndroidKeyStore"
        const val KEY_ALIAS = "com.keplr.vizor.ironwood-migration-native.v1"
        const val KEY_SIZE_BITS = 256
        val KEYSTORE_LOCK = ReentrantLock()
    }
}

internal class IronwoodMigrationAesGcm(
    private val keyProvider: IronwoodMigrationKeyProvider,
    private val random: SecureRandom = SecureRandom(),
) {
    fun seal(plaintext: ByteArray, recordId: String): ByteArray {
        val nonce = ByteArray(NONCE_SIZE).also(random::nextBytes)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
            Cipher.ENCRYPT_MODE,
            keyProvider.getOrCreate(),
            GCMParameterSpec(TAG_SIZE_BITS, nonce),
        )
        cipher.updateAAD(associatedData(recordId))
        val ciphertext = cipher.doFinal(plaintext)

        return ByteArrayOutputStream().use { bytes ->
            DataOutputStream(bytes).use { output ->
                output.writeInt(MAGIC)
                output.writeByte(FORMAT_VERSION)
                output.writeByte(nonce.size)
                output.writeInt(ciphertext.size)
                output.write(nonce)
                output.write(ciphertext)
            }
            bytes.toByteArray()
        }
    }

    fun open(envelope: ByteArray, recordId: String): ByteArray {
        val input = DataInputStream(ByteArrayInputStream(envelope))
        if (input.readInt() != MAGIC || input.readUnsignedByte() != FORMAT_VERSION) {
            throw IronwoodMigrationSecureStoreException("Unsupported encrypted record.")
        }
        val nonceSize = input.readUnsignedByte()
        val ciphertextSize = input.readInt()
        if (
            nonceSize != NONCE_SIZE ||
            ciphertextSize < TAG_SIZE_BYTES ||
            ciphertextSize > MAX_RECORD_BYTES ||
            input.available() != nonceSize + ciphertextSize
        ) {
            throw IronwoodMigrationSecureStoreException("Invalid encrypted record.")
        }
        val nonce = ByteArray(nonceSize).also(input::readFully)
        val ciphertext = ByteArray(ciphertextSize).also(input::readFully)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            keyProvider.getOrCreate(),
            GCMParameterSpec(TAG_SIZE_BITS, nonce),
        )
        cipher.updateAAD(associatedData(recordId))
        return try {
            cipher.doFinal(ciphertext)
        } catch (error: Exception) {
            throw IronwoodMigrationSecureStoreException(
                "Failed to authenticate encrypted migration data.",
                error,
            )
        }
    }

    private fun associatedData(recordId: String): ByteArray =
        "$ASSOCIATED_DATA_PREFIX:$recordId".toByteArray(Charsets.UTF_8)

    private companion object {
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val FORMAT_VERSION = 1
        const val MAGIC = 0x56494D31 // VIM1
        const val NONCE_SIZE = 12
        const val TAG_SIZE_BITS = 128
        const val TAG_SIZE_BYTES = TAG_SIZE_BITS / 8
        const val MAX_RECORD_BYTES = 64 * 1024 * 1024
        const val ASSOCIATED_DATA_PREFIX = "vizor-ironwood-native-store-v1"
    }
}

internal class IronwoodMigrationSecureStoreException(
    message: String,
    cause: Throwable? = null,
) : Exception(message, cause)

/**
 * Encrypted, account-scoped storage for native Ironwood migration work.
 *
 * Each file name is a SHA-256 digest of its logical record key. The encrypted
 * plaintext repeats that key and is bound to the file name through AES-GCM AAD,
 * allowing safe prefix revocation without exposing wallet scope in file names.
 */
internal class IronwoodMigrationSecureStore(
    private val keyProvider: IronwoodMigrationKeyProvider =
        AndroidKeystoreIronwoodMigrationKeyProvider(),
    directory: File,
    private val cipher: IronwoodMigrationAesGcm = IronwoodMigrationAesGcm(keyProvider),
) {
    constructor(context: Context) : this(
        directory = File(context.noBackupFilesDir, DIRECTORY_NAME),
    )

    private val lock = STORE_LOCK
    private val directory = directory.apply {
        if ((!exists() && !mkdirs()) || !isDirectory) {
            throw IronwoodMigrationSecureStoreException(
                "Failed to create the native migration storage directory.",
            )
        }
    }

    init {
        lock.withLock {
            recoverInterruptedWrites()
        }
    }

    fun writeManifest(
        network: String,
        accountUuid: String,
        manifestJson: String,
    ) = lock.withLock {
        val recordKey = manifestKey(network, accountUuid)
        val manifestKeys = readManifestKeysLocked()
        val addedToIndex = manifestKeys.add(recordKey)
        if (addedToIndex) {
            writeManifestKeysLocked(manifestKeys)
        }
        try {
            put(recordKey, manifestJson.toByteArray(Charsets.UTF_8))
        } catch (error: Exception) {
            if (addedToIndex) {
                manifestKeys.remove(recordKey)
                try {
                    writeManifestKeysLocked(manifestKeys)
                } catch (rollbackError: Exception) {
                    error.addSuppressed(rollbackError)
                }
            }
            throw error
        }
    }

    fun readManifest(network: String, accountUuid: String): String? =
        get(manifestKey(network, accountUuid))?.toString(Charsets.UTF_8)

    fun readAllManifests(): List<String> = lock.withLock {
        val manifestKeys = readManifestKeysLocked()
        val staleKeys = mutableSetOf<String>()
        val manifests = manifestKeys.mapNotNull { recordKey ->
            val payload = get(recordKey)
            if (payload == null) {
                staleKeys.add(recordKey)
                null
            } else {
                payload.toString(Charsets.UTF_8)
            }
        }
        if (staleKeys.isNotEmpty()) {
            manifestKeys.removeAll(staleKeys)
            writeManifestKeysLocked(manifestKeys)
        }
        manifests
    }

    fun deleteManifest(network: String, accountUuid: String) = lock.withLock {
        val recordKey = manifestKey(network, accountUuid)
        val manifestKeys = readManifestKeysLocked()
        remove(recordKey)
        if (manifestKeys.remove(recordKey)) {
            writeManifestKeysLocked(manifestKeys)
        }
    }

    fun writeOutboxBatch(
        network: String,
        accountUuid: String,
        batchId: String,
        encodedBatch: ByteArray,
    ) {
        put(outboxKey(network, accountUuid, batchId), encodedBatch)
    }

    fun readOutboxBatch(
        network: String,
        accountUuid: String,
        batchId: String,
    ): ByteArray? = get(outboxKey(network, accountUuid, batchId))

    fun revokeAccount(network: String, accountUuid: String) = lock.withLock {
        val recordKey = manifestKey(network, accountUuid)
        val manifestKeys = readManifestKeysLocked()
        remove(recordKey)
        if (manifestKeys.remove(recordKey)) {
            writeManifestKeysLocked(manifestKeys)
        }
        removePrefix("$RECORD_VERSION:outbox:$network:$accountUuid:")
    }

    fun revokeAll() = lock.withLock {
        directory.listFiles()
            ?.filter {
                it.isFile &&
                    (
                        it.name.endsWith(RECORD_SUFFIX) ||
                            it.name.endsWith(TEMP_SUFFIX) ||
                            it.name.endsWith(BACKUP_SUFFIX)
                        )
            }
            ?.forEach { file ->
                if (!file.delete() && file.exists()) {
                    throw IronwoodMigrationSecureStoreException(
                        "Failed to remove native migration data.",
                    )
                }
            }
        keyProvider.delete()
    }

    private fun put(recordKey: String, payload: ByteArray) = lock.withLock {
        require(payload.size <= MAX_PAYLOAD_BYTES) { "Migration record is too large." }
        val recordId = recordId(recordKey)
        val plaintext = encodeRecord(recordKey, payload)
        val encrypted = cipher.seal(plaintext, recordId)
        atomicWrite(fileFor(recordId), encrypted)
    }

    private fun get(recordKey: String): ByteArray? = lock.withLock {
        val recordId = recordId(recordKey)
        val file = fileFor(recordId)
        if (!file.exists()) return null
        val record = decodeRecord(cipher.open(file.readBytes(), recordId))
        if (record.first != recordKey) {
            throw IronwoodMigrationSecureStoreException(
                "Encrypted migration record scope does not match its file.",
            )
        }
        record.second
    }

    private fun remove(recordKey: String) = lock.withLock {
        val file = fileFor(recordId(recordKey))
        if (file.exists() && !file.delete()) {
            throw IronwoodMigrationSecureStoreException(
                "Failed to remove native migration data.",
            )
        }
    }

    private fun readManifestKeysLocked(): MutableSet<String> {
        get(MANIFEST_INDEX_KEY)?.let {
            return decodeManifestIndex(it)
        }

        // Upgrade path for stores created before the encrypted index existed.
        // This is the only path that opens non-manifest records.
        recoverInterruptedWrites()
        val recordFiles = directory.listFiles()
            ?.filter { it.isFile && it.name.endsWith(RECORD_SUFFIX) }
            .orEmpty()
        val manifestKeys = recordFiles
            .mapNotNull { file ->
                val recordId = file.name.removeSuffix(RECORD_SUFFIX)
                val record = decodeRecord(cipher.open(file.readBytes(), recordId))
                record.first.takeIf { it.startsWith(MANIFEST_PREFIX) }
            }
            .toMutableSet()
        if (recordFiles.isNotEmpty()) {
            writeManifestKeysLocked(manifestKeys)
        }
        return manifestKeys
    }

    private fun writeManifestKeysLocked(manifestKeys: Set<String>) {
        put(MANIFEST_INDEX_KEY, encodeManifestIndex(manifestKeys))
    }

    private fun encodeManifestIndex(manifestKeys: Set<String>): ByteArray =
        ByteArrayOutputStream().use { bytes ->
            DataOutputStream(bytes).use { output ->
                output.writeInt(MANIFEST_INDEX_MAGIC)
                output.writeInt(MANIFEST_INDEX_VERSION)
                output.writeInt(manifestKeys.size)
                manifestKeys.sorted().forEach { recordKey ->
                    val keyBytes = recordKey.toByteArray(Charsets.UTF_8)
                    output.writeInt(keyBytes.size)
                    output.write(keyBytes)
                }
            }
            bytes.toByteArray()
        }

    private fun decodeManifestIndex(payload: ByteArray): MutableSet<String> {
        val input = DataInputStream(ByteArrayInputStream(payload))
        if (
            input.readInt() != MANIFEST_INDEX_MAGIC ||
            input.readInt() != MANIFEST_INDEX_VERSION
        ) {
            throw IronwoodMigrationSecureStoreException(
                "Unsupported migration manifest index.",
            )
        }
        val count = input.readInt()
        if (count < 0 || count > MAX_MANIFEST_COUNT) {
            throw IronwoodMigrationSecureStoreException(
                "Invalid migration manifest index count.",
            )
        }
        val manifestKeys = linkedSetOf<String>()
        repeat(count) {
            val keySize = input.readInt()
            if (keySize <= 0 || keySize > MAX_KEY_BYTES || input.available() < keySize) {
                throw IronwoodMigrationSecureStoreException(
                    "Invalid migration manifest index entry.",
                )
            }
            val recordKey = ByteArray(keySize)
                .also(input::readFully)
                .toString(Charsets.UTF_8)
            if (!recordKey.startsWith(MANIFEST_PREFIX) || !manifestKeys.add(recordKey)) {
                throw IronwoodMigrationSecureStoreException(
                    "Invalid migration manifest index scope.",
                )
            }
        }
        if (input.available() != 0) {
            throw IronwoodMigrationSecureStoreException(
                "Invalid migration manifest index length.",
            )
        }
        return manifestKeys
    }

    private fun removePrefix(prefix: String) = lock.withLock {
        recoverInterruptedWrites()
        directory.listFiles()
            ?.filter { it.isFile && it.name.endsWith(RECORD_SUFFIX) }
            ?.forEach { file ->
                val recordId = file.name.removeSuffix(RECORD_SUFFIX)
                val recordKey = decodeRecord(cipher.open(file.readBytes(), recordId)).first
                if (recordKey.startsWith(prefix)) {
                    if (!file.delete()) {
                        throw IronwoodMigrationSecureStoreException(
                            "Failed to revoke native migration account data.",
                        )
                    }
                }
            }
    }

    private fun fileFor(recordId: String): File {
        // A previous atomic write can leave the last committed value in a
        // backup even while this store instance remains alive.
        recoverInterruptedWrites()
        return File(directory, "$recordId$RECORD_SUFFIX")
    }

    private fun recoverInterruptedWrites() {
        directory.listFiles()
            ?.filter { it.isFile && it.name.endsWith("$RECORD_SUFFIX$BACKUP_SUFFIX") }
            ?.forEach { backup ->
                val destination = File(directory, backup.name.removeSuffix(BACKUP_SUFFIX))
                val recovered = if (destination.exists()) {
                    backup.delete()
                } else {
                    backup.renameTo(destination)
                }
                if (!recovered) {
                    throw IronwoodMigrationSecureStoreException(
                        "Failed to recover native migration data.",
                    )
                }
            }
        directory.listFiles()
            ?.filter { it.isFile && it.name.endsWith("$RECORD_SUFFIX$TEMP_SUFFIX") }
            ?.forEach { temporary ->
                if (!temporary.delete()) {
                    throw IronwoodMigrationSecureStoreException(
                        "Failed to clear interrupted native migration data.",
                    )
                }
            }
    }

    private fun atomicWrite(destination: File, bytes: ByteArray) {
        val temporary = File(directory, "${destination.name}$TEMP_SUFFIX")
        val backup = File(directory, "${destination.name}$BACKUP_SUFFIX")
        try {
            FileOutputStream(temporary).use { output ->
                output.write(bytes)
                output.flush()
                output.fd.sync()
            }
            if (backup.exists() && !backup.delete()) {
                throw IronwoodMigrationSecureStoreException(
                    "Failed to clear a stale native migration backup.",
                )
            }
            if (destination.exists() && !destination.renameTo(backup)) {
                throw IronwoodMigrationSecureStoreException(
                    "Failed to back up native migration data.",
                )
            }
            if (!temporary.renameTo(destination)) {
                if (backup.exists() && !backup.renameTo(destination)) {
                    throw IronwoodMigrationSecureStoreException(
                        "Failed to commit or restore native migration data.",
                    )
                }
                throw IronwoodMigrationSecureStoreException(
                    "Failed to commit native migration data.",
                )
            }
            backup.delete()
        } finally {
            temporary.delete()
        }
    }

    private fun encodeRecord(recordKey: String, payload: ByteArray): ByteArray {
        val keyBytes = recordKey.toByteArray(Charsets.UTF_8)
        return ByteArrayOutputStream().use { bytes ->
            DataOutputStream(bytes).use { output ->
                output.writeInt(RECORD_MAGIC)
                output.writeInt(keyBytes.size)
                output.writeInt(payload.size)
                output.write(keyBytes)
                output.write(payload)
            }
            bytes.toByteArray()
        }
    }

    private fun decodeRecord(plaintext: ByteArray): Pair<String, ByteArray> {
        val input = DataInputStream(ByteArrayInputStream(plaintext))
        if (input.readInt() != RECORD_MAGIC) {
            throw IronwoodMigrationSecureStoreException("Invalid migration record.")
        }
        val keySize = input.readInt()
        val payloadSize = input.readInt()
        if (
            keySize <= 0 ||
            keySize > MAX_KEY_BYTES ||
            payloadSize < 0 ||
            payloadSize > MAX_PAYLOAD_BYTES ||
            input.available() != keySize + payloadSize
        ) {
            throw IronwoodMigrationSecureStoreException("Invalid migration record lengths.")
        }
        val key = ByteArray(keySize).also(input::readFully).toString(Charsets.UTF_8)
        val payload = ByteArray(payloadSize).also(input::readFully)
        return key to payload
    }

    private fun manifestKey(network: String, accountUuid: String) =
        "$MANIFEST_PREFIX$network:$accountUuid"

    private fun outboxKey(network: String, accountUuid: String, batchId: String) =
        "$RECORD_VERSION:outbox:$network:$accountUuid:$batchId"

    private fun recordId(recordKey: String): String =
        MessageDigest.getInstance("SHA-256")
            .digest(recordKey.toByteArray(Charsets.UTF_8))
            .joinToString(separator = "") { byte ->
                "%02x".format(byte.toInt() and 0xff)
            }

    private companion object {
        const val DIRECTORY_NAME = "ironwood-migration-native-v1"
        const val RECORD_VERSION = "v1"
        const val RECORD_SUFFIX = ".bin"
        const val TEMP_SUFFIX = ".tmp"
        const val BACKUP_SUFFIX = ".bak"
        const val RECORD_MAGIC = 0x56495231 // VIR1
        const val MANIFEST_INDEX_MAGIC = 0x56494D49 // VIMI
        const val MANIFEST_INDEX_VERSION = 1
        const val MAX_MANIFEST_COUNT = 10_000
        const val MAX_KEY_BYTES = 4 * 1024
        const val MAX_PAYLOAD_BYTES = 48 * 1024 * 1024
        const val MANIFEST_PREFIX = "$RECORD_VERSION:manifest:"
        const val MANIFEST_INDEX_KEY = "$RECORD_VERSION:index:manifests"
        val STORE_LOCK = ReentrantLock()
    }
}
