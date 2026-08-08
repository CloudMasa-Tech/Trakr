package com.yourcompany.qrattendance

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning

class MainActivity : FlutterActivity() {
    private val channelName = "attendqr/google_code_scanner"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "scanQr" -> scanQr(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun scanQr(result: MethodChannel.Result) {
        val options = GmsBarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
            .enableAutoZoom()
            .build()
        val scanner = GmsBarcodeScanning.getClient(this, options)

        scanner.startScan()
            .addOnSuccessListener { barcode ->
                result.success(barcode.rawValue)
            }
            .addOnCanceledListener {
                result.success(null)
            }
            .addOnFailureListener { exception ->
                result.error(
                    "GOOGLE_SCANNER_FAILED",
                    exception.localizedMessage ?: "Google Code Scanner failed to scan.",
                    null
                )
            }
    }
}
