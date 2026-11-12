package app.speedll.connect

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.ImageFormat
import android.graphics.SurfaceTexture
import android.graphics.drawable.GradientDrawable
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.ImageReader
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.common.HybridBinarizer
import java.util.EnumMap
import java.util.concurrent.atomic.AtomicBoolean

class QrScannerActivity : Activity() {

    companion object {
        const val EXTRA_QR_RESULT = "extra_qr_result"
        const val EXTRA_ERROR_MESSAGE = "extra_error_message"
        private const val REQUEST_CAMERA_PERMISSION = 3001
        private const val TAG = "QrScannerActivity"
    }

    private lateinit var textureView: TextureView
    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var imageReader: ImageReader? = null
    private var backgroundThread: HandlerThread? = null
    private var backgroundHandler: Handler? = null
    private val hasScannedResult = AtomicBoolean(false)
    private var cameraPermissionRequested = false

    private val qrReader = MultiFormatReader().apply {
        val hints = EnumMap<DecodeHintType, Any>(DecodeHintType::class.java)
        hints[DecodeHintType.POSSIBLE_FORMATS] = listOf(BarcodeFormat.QR_CODE)
        hints[DecodeHintType.CHARACTER_SET] = "UTF-8"
        hints[DecodeHintType.TRY_HARDER] = true
        setHints(hints)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
        }

        textureView = TextureView(this)
        root.addView(
            textureView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )

        // Viewfinder reticle box in center
        val boxSizePx = dpToPx(250f)
        val reticleView = View(this).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(20f).toFloat()
                setStroke(dpToPx(3f), Color.parseColor("#4DA3FF"))
                setColor(Color.TRANSPARENT)
            }
        }
        root.addView(
            reticleView,
            FrameLayout.LayoutParams(boxSizePx, boxSizePx, Gravity.CENTER)
        )

        // Overlay header & cancel button
        val overlayLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dpToPx(24f), dpToPx(48f), dpToPx(24f), dpToPx(36f))
        }

        val titleText = TextView(this).apply {
            text = "اسکن بارکد QR کانفیگ یا اشتراک"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            gravity = Gravity.CENTER
        }

        val subtitleText = TextView(this).apply {
            text = "بارکد QR را داخل کادر آبی قرار دهید"
            setTextColor(Color.parseColor("#D0D7DE"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            gravity = Gravity.CENTER
            setPadding(0, dpToPx(8f), 0, 0)
        }

        overlayLayout.addView(titleText)
        overlayLayout.addView(subtitleText)

        root.addView(
            overlayLayout,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.TOP
            )
        )

        val cancelButton = Button(this).apply {
            text = "انصراف و بازگشت"
            setTextColor(Color.WHITE)
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(14f).toFloat()
                setColor(Color.parseColor("#CC1F2937"))
            }
            setPadding(dpToPx(28f), dpToPx(12f), dpToPx(28f), dpToPx(12f))
            setOnClickListener {
                setResult(RESULT_CANCELED)
                finish()
            }
        }

        val bottomParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
        ).apply {
            bottomMargin = dpToPx(48f)
        }
        root.addView(cancelButton, bottomParams)

        setContentView(root)
    }

    override fun onResume() {
        super.onResume()
        startBackgroundThread()
        if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            cameraPermissionRequested = false
            if (textureView.isAvailable) {
                openCamera()
            } else {
                textureView.surfaceTextureListener = surfaceTextureListener
            }
        } else if (!cameraPermissionRequested) {
            cameraPermissionRequested = true
            requestPermissions(arrayOf(Manifest.permission.CAMERA), REQUEST_CAMERA_PERMISSION)
        }
    }

    override fun onPause() {
        closeCamera()
        stopBackgroundThread()
        super.onPause()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_CAMERA_PERMISSION) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                if (textureView.isAvailable) {
                    openCamera()
                } else {
                    textureView.surfaceTextureListener = surfaceTextureListener
                }
            } else {
                val data = Intent().apply {
                    putExtra(EXTRA_ERROR_MESSAGE, "مجوز دسترسی به دوربین برای اسکن QR داده نشد.")
                }
                setResult(RESULT_CANCELED, data)
                finish()
            }
        }
    }

    private val surfaceTextureListener = object : TextureView.SurfaceTextureListener {
        override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) {
            openCamera()
        }

        override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) {}
        override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean = true
        override fun onSurfaceTextureUpdated(surface: SurfaceTexture) {}
    }

    private fun openCamera() {
        val manager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
        try {
            val cameraId = manager.cameraIdList.firstOrNull { id ->
                val chars = manager.getCameraCharacteristics(id)
                chars.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
            } ?: manager.cameraIdList.firstOrNull()

            if (cameraId == null) {
                finishWithError("دوربین فعالی روی دستگاه یافت نشد.")
                return
            }

            if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
                return
            }

            imageReader = ImageReader.newInstance(640, 480, ImageFormat.YUV_420_888, 2).apply {
                setOnImageAvailableListener({ reader ->
                    val image = reader.acquireLatestImage() ?: return@setOnImageAvailableListener
                    try {
                        if (!hasScannedResult.get()) {
                            val plane = image.planes[0]
                            val buffer = plane.buffer
                            val rowStride = plane.rowStride
                            val width = image.width
                            val height = image.height
                            val yBytes = ByteArray(width * height)

                            if (rowStride == width) {
                                buffer.get(yBytes, 0, width * height)
                            } else {
                                val rowBuffer = ByteArray(rowStride)
                                for (row in 0 until height) {
                                    val length = if (row == height - 1) width else rowStride
                                    buffer.get(rowBuffer, 0, length.coerceAtMost(buffer.remaining()))
                                    System.arraycopy(rowBuffer, 0, yBytes, row * width, width)
                                }
                            }

                            decodeLuminanceFrame(yBytes, width, height)
                        }
                    } catch (e: Exception) {
                        Log.d(TAG, "Frame decode skipped: ${e.message}")
                    } finally {
                        image.close()
                    }
                }, backgroundHandler)
            }

            manager.openCamera(cameraId, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    cameraDevice = camera
                    startPreviewSession()
                }

                override fun onDisconnected(camera: CameraDevice) {
                    camera.close()
                    cameraDevice = null
                }

                override fun onError(camera: CameraDevice, error: Int) {
                    camera.close()
                    cameraDevice = null
                    finishWithError("خطا در راه‌اندازی دوربین (کد $error).")
                }
            }, backgroundHandler)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open camera: $e")
            finishWithError("خطا در باز کردن دوربین گوشی.")
        }
    }

    private fun startPreviewSession() {
        val device = cameraDevice ?: return
        val texture = textureView.surfaceTexture ?: return
        val readerSurface = imageReader?.surface ?: return

        try {
            texture.setDefaultBufferSize(1280, 720)
            val previewSurface = Surface(texture)

            val requestBuilder = device.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                addTarget(previewSurface)
                addTarget(readerSurface)
                set(
                    CaptureRequest.CONTROL_AF_MODE,
                    CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE
                )
            }

            @Suppress("DEPRECATION")
            device.createCaptureSession(
                listOf(previewSurface, readerSurface),
                object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(session: CameraCaptureSession) {
                        if (cameraDevice == null) return
                        captureSession = session
                        try {
                            session.setRepeatingRequest(
                                requestBuilder.build(),
                                null,
                                backgroundHandler
                            )
                        } catch (e: Exception) {
                            Log.e(TAG, "Preview repeating request error: $e")
                        }
                    }

                    override fun onConfigureFailed(session: CameraCaptureSession) {
                        finishWithError("تنظیم تصویر دوربین ناموفق بود.")
                    }
                },
                backgroundHandler
            )
        } catch (e: Exception) {
            Log.e(TAG, "startPreviewSession error: $e")
        }
    }

    private fun decodeLuminanceFrame(yBytes: ByteArray, width: Int, height: Int) {
        val source = PlanarYUVLuminanceSource(
            yBytes,
            width,
            height,
            0,
            0,
            width,
            height,
            false
        )
        val bitmap = BinaryBitmap(HybridBinarizer(source))
        try {
            val result = qrReader.decodeWithState(bitmap)
            val text = result.text?.trim()
            if (!text.isNullOrEmpty() && hasScannedResult.compareAndSet(false, true)) {
                runOnUiThread {
                    val data = Intent().apply {
                        putExtra(EXTRA_QR_RESULT, text)
                    }
                    setResult(RESULT_OK, data)
                    finish()
                }
            }
        } catch (_: Exception) {
            // Try rotated 90 degrees for portrait camera sensor orientation
            try {
                val rotated = ByteArray(yBytes.size)
                for (y in 0 until height) {
                    for (x in 0 until width) {
                        rotated[x * height + height - y - 1] = yBytes[y * width + x]
                    }
                }
                val rotatedSource = PlanarYUVLuminanceSource(
                    rotated,
                    height,
                    width,
                    0,
                    0,
                    height,
                    width,
                    false
                )
                val rotatedResult =
                    qrReader.decodeWithState(BinaryBitmap(HybridBinarizer(rotatedSource)))
                val text = rotatedResult.text?.trim()
                if (!text.isNullOrEmpty() && hasScannedResult.compareAndSet(false, true)) {
                    runOnUiThread {
                        val data = Intent().apply {
                            putExtra(EXTRA_QR_RESULT, text)
                        }
                        setResult(RESULT_OK, data)
                        finish()
                    }
                }
            } catch (_: Exception) {
                // No QR code in current frame
            }
        } finally {
            qrReader.reset()
        }
    }

    private fun finishWithError(message: String) {
        runOnUiThread {
            val data = Intent().apply {
                putExtra(EXTRA_ERROR_MESSAGE, message)
            }
            setResult(RESULT_CANCELED, data)
            finish()
        }
    }

    private fun closeCamera() {
        try {
            captureSession?.close()
            captureSession = null
            cameraDevice?.close()
            cameraDevice = null
            imageReader?.close()
            imageReader = null
        } catch (e: Exception) {
            Log.e(TAG, "Error closing camera: $e")
        }
    }

    private fun startBackgroundThread() {
        backgroundThread = HandlerThread("QrScannerCameraThread").also { it.start() }
        backgroundHandler = Handler(backgroundThread!!.looper)
    }

    private fun stopBackgroundThread() {
        backgroundThread?.quitSafely()
        try {
            backgroundThread?.join()
            backgroundThread = null
            backgroundHandler = null
        } catch (_: InterruptedException) {}
    }

    private fun dpToPx(dp: Float): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            dp,
            resources.displayMetrics
        ).toInt()
    }
}
