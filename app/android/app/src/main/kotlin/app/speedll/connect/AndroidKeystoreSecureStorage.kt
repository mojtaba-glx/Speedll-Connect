package app.speedll.connect

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import java.nio.ByteBuffer
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Hardware-backed Android Keystore (AES-256-GCM) encrypted storage provider
 * backing the FlutterSecureStorage MethodChannel.
 */
class AndroidKeystoreSecureStorage(private val context: Context) {

    companion object {
        private const val TAG = "SpeedllSecureStorage"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val KEY_ALIAS = "app.speedll.connect.master_aes_gcm_key"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val DEFAULT_PREFS_NAME = "FlutterSecureStorage"
        private const val GCM_TAG_BITS = 128
    }

    private fun getPreferences(prefsName: String?): SharedPreferences {
        val name = if (prefsName.isNullOrBlank()) DEFAULT_PREFS_NAME else prefsName
        return context.getSharedPreferences(name, Context.MODE_PRIVATE)
    }

    @Synchronized
    private fun getOrCreateSecretKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply {
            load(null)
        }

        val existingEntry = keyStore.getEntry(KEY_ALIAS, null)
        if (existingEntry is KeyStore.SecretKeyEntry) {
            return existingEntry.secretKey
        }

        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            ANDROID_KEYSTORE
        )
        val spec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setRandomizedEncryptionRequired(true)
            .build()

        keyGenerator.init(spec)
        return keyGenerator.generateKey()
    }

    private fun encrypt(plaintext: String): String {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateSecretKey())
        val iv = cipher.iv
        val ciphertext = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))

        val buffer = ByteBuffer.allocate(1 + iv.size + ciphertext.size)
        buffer.put(iv.size.toByte())
        buffer.put(iv)
        buffer.put(ciphertext)
        return Base64.encodeToString(buffer.array(), Base64.NO_WRAP)
    }

    private fun decrypt(encodedPayload: String): String {
        val raw = Base64.decode(encodedPayload, Base64.NO_WRAP)
        val buffer = ByteBuffer.wrap(raw)
        val ivLength = buffer.get().toInt() and 0xFF
        require(ivLength in 12..16 && raw.size > 1 + ivLength) {
            "Invalid encrypted payload format"
        }

        val iv = ByteArray(ivLength)
        buffer.get(iv)
        val ciphertext = ByteArray(buffer.remaining())
        buffer.get(ciphertext)

        val cipher = Cipher.getInstance(TRANSFORMATION)
        val spec = GCMParameterSpec(GCM_TAG_BITS, iv)
        cipher.init(Cipher.DECRYPT_MODE, getOrCreateSecretKey(), spec)
        val decrypted = cipher.doFinal(ciphertext)
        return String(decrypted, Charsets.UTF_8)
    }

    fun write(key: String, value: String, prefsName: String? = null) {
        val encrypted = encrypt(value)
        getPreferences(prefsName).edit().putString(key, encrypted).apply()
    }

    fun read(key: String, prefsName: String? = null, resetOnError: Boolean = true): String? {
        val prefs = getPreferences(prefsName)
        val encoded = prefs.getString(key, null) ?: return null
        return try {
            decrypt(encoded)
        } catch (e: Exception) {
            Log.e(TAG, "Decryption failed for key: $key")
            if (resetOnError) {
                prefs.edit().remove(key).apply()
            }
            null
        }
    }

    fun containsKey(key: String, prefsName: String? = null): Boolean {
        return getPreferences(prefsName).contains(key)
    }

    fun delete(key: String, prefsName: String? = null) {
        getPreferences(prefsName).edit().remove(key).apply()
    }

    fun readAll(prefsName: String? = null, resetOnError: Boolean = true): Map<String, String> {
        val prefs = getPreferences(prefsName)
        val result = mutableMapOf<String, String>()
        for ((k, v) in prefs.all) {
            if (v is String) {
                try {
                    result[k] = decrypt(v)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to decrypt entry during readAll: $k")
                    if (resetOnError) {
                        prefs.edit().remove(k).apply()
                    }
                }
            }
        }
        return result
    }

    fun deleteAll(prefsName: String? = null) {
        getPreferences(prefsName).edit().clear().apply()
    }
}
