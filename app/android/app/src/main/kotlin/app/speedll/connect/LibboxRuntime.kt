package app.speedll.connect

import android.content.Context
import android.os.Build
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.SetupOptions
import org.json.JSONObject
import java.io.File

object LibboxRuntime {
    @Volatile
    private var configured = false

    @Synchronized
    fun ensureSetup(context: Context) {
        if (configured) return

        val appContext = context.applicationContext
        val baseDir = appContext.filesDir.apply { mkdirs() }
        val workingDir = File(appContext.filesDir, "libbox").apply { mkdirs() }
        val tempDir = appContext.cacheDir.apply { mkdirs() }
        val packageInfo = appContext.packageManager.getPackageInfo(appContext.packageName, 0)
        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            packageInfo.versionCode.toLong()
        }

        val options = SetupOptions().apply {
            basePath = baseDir.absolutePath
            workingPath = workingDir.absolutePath
            tempPath = tempDir.absolutePath
            fixAndroidStack = true
            logMaxLines = 1000
            debug = false
            appVersion = versionCode.toString()
            appMarketingVersion = packageInfo.versionName.orEmpty()
            oomKillerEnabled = false
            oomKillerDisabled = true
            oomMemoryLimit = 0
            powerReportEnabled = false
            platformMetadata = JSONObject().apply {
                put("os", "Android ${Build.VERSION.RELEASE}")
                put("sdk", Build.VERSION.SDK_INT)
                put("manufacturer", Build.MANUFACTURER)
                put("model", Build.MODEL)
            }.toString()
        }

        Libbox.setup(options)
        configured = true
    }
}
