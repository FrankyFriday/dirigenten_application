package com.example.dirigenten_application

import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

class MainActivity : FlutterActivity() {

    private val CHANNEL = "app.signature"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->

            when (call.method) {

                // =====================================================
                // SIGNATUR DER INSTALLIERTEN APP
                // =====================================================
                "getInstalledSignature" -> {

                    try {

                        val packageInfo =
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {

                                packageManager.getPackageInfo(
                                    packageName,
                                    PackageManager.GET_SIGNING_CERTIFICATES
                                )

                            } else {

                                @Suppress("DEPRECATION")
                                packageManager.getPackageInfo(
                                    packageName,
                                    PackageManager.GET_SIGNATURES
                                )
                            }

                        val signatures = if (
                            Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
                        ) {

                            packageInfo.signingInfo
                                ?.apkContentsSigners

                        } else {

                            @Suppress("DEPRECATION")
                            packageInfo.signatures
                        }

                        val signature = signatures?.firstOrNull()

                        if (signature == null) {

                            result.error(
                                "NO_SIGNATURE",
                                "Keine Signatur gefunden",
                                null
                            )

                            return@setMethodCallHandler
                        }

                        val sha256 =
                            sha256(signature.toByteArray())

                        result.success(sha256)

                    } catch (e: Exception) {

                        result.error(
                            "SIGNATURE_ERROR",
                            e.message,
                            null
                        )
                    }
                }


                // =====================================================
                // SIGNATUR DER HERUNTERGELADENEN APK
                // =====================================================
                "getApkSignature" -> {

                    try {

                        val apkPath =
                            call.argument<String>("path")

                        if (apkPath == null) {

                            result.error(
                                "NO_PATH",
                                "Kein APK-Pfad angegeben",
                                null
                            )

                            return@setMethodCallHandler
                        }

                        val packageInfo =
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {

                                packageManager.getPackageArchiveInfo(
                                    apkPath,
                                    PackageManager.GET_SIGNING_CERTIFICATES
                                )

                            } else {

                                @Suppress("DEPRECATION")
                                packageManager.getPackageArchiveInfo(
                                    apkPath,
                                    PackageManager.GET_SIGNATURES
                                )
                            }

                        if (packageInfo == null) {

                            result.error(
                                "INVALID_APK",
                                "APK konnte nicht gelesen werden",
                                null
                            )

                            return@setMethodCallHandler
                        }

                        val signatures = if (
                            Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
                        ) {

                            packageInfo.signingInfo
                                ?.apkContentsSigners

                        } else {

                            @Suppress("DEPRECATION")
                            packageInfo.signatures
                        }

                        val signature = signatures?.firstOrNull()

                        if (signature == null) {

                            result.error(
                                "NO_SIGNATURE",
                                "Keine Signatur in APK gefunden",
                                null
                            )

                            return@setMethodCallHandler
                        }

                        val sha256 =
                            sha256(signature.toByteArray())

                        result.success(
                            mapOf(
                                "packageName" to packageInfo.packageName,
                                "versionName" to packageInfo.versionName,
                                "versionCode" to packageInfo.longVersionCode,
                                "signature" to sha256
                            )
                        )

                    } catch (e: Exception) {

                        result.error(
                            "APK_SIGNATURE_ERROR",
                            e.message,
                            null
                        )
                    }
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }


    // =============================================================
    // SHA-256 DER SIGNATUR
    // =============================================================
    private fun sha256(data: ByteArray): String {

        val digest =
            MessageDigest.getInstance("SHA-256")

        val hash =
            digest.digest(data)

        return hash.joinToString(":") {
            "%02X".format(it)
        }
    }
}