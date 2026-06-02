import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

android {
    namespace = "com.nestback.shouna"
    compileSdk = 36
    // compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.nestback.shouna"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36  // 必须设置为 31 或更高！
        // minSdk = flutter.minSdkVersion
        // targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

}

flutter {
    source = "../.."
}

tasks.register("renameApks") {
    doLast {
        val appName = "nestback"
        val versionName = android.defaultConfig.versionName!!
        val flutterApkDir = File(project.rootDir.parent, "build/app/outputs/flutter-apk")
        
        if (flutterApkDir.exists()) {
            flutterApkDir.listFiles { file -> file.isFile && file.name.endsWith(".apk") }?.forEach { apkFile ->
                val originalName = apkFile.name
                
                val abiMatch = Regex("app-(.+)-release\\.apk").find(originalName)
                val abi = abiMatch?.groupValues?.get(1)
                
                val newFileName = if (abi != null) {
                    "${appName}-${versionName}-${abi}-release.apk"
                } else if (originalName == "app-release.apk") {
                    "${appName}-${versionName}-release.apk"
                } else {
                    return@forEach
                }
                
                val newFile = File(flutterApkDir, newFileName)
                if (newFile.exists()) {
                    newFile.delete()
                }
                apkFile.renameTo(newFile)
                println("Renamed: $originalName -> $newFileName")
            }
        }
    }
}

afterEvaluate {
    tasks.findByName("assembleRelease")?.finalizedBy("renameApks")
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
