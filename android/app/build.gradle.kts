import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 正式签名密钥配置：从 android/key.properties 读取（key.properties 与 keystore 均不入库，见 .gitignore）。
// 本地未配置时 release 回退 debug 签名，仅用于开发调试；正式发布由 CI 经 secrets 注入密钥后构建。
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.ushiomd"
    // T-BUILD：receive_sharing_intent 要求 compileSdk 37+；本机 SDK 以 android-37 目录提供该平台
    // （google 仓库当前无 hash 'android-37'，由 android-37.0 复制而来，见环境备注）。
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.ushiomd"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionName = flutter.versionName
        // 直接使用 pubspec 的 build number，保证版本码随发布单调递增。
        versionCode = flutter.versionCode
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            val storePassword = keystoreProperties["storePassword"] as String?
            val releaseKeyConfigured = keystoreProperties["storeFile"] != null && !storePassword.isNullOrEmpty()
            if (releaseKeyConfigured) {
                // T-10：正式签名 —— key.properties 由 CI secrets 注入或本地手工配置（均不入库）
                signingConfig = signingConfigs.getByName("release")
            } else {
                // 本地未配置 key.properties（或字段缺失）时回退 debug 签名，仅用于本地开发调试；
                // 正式发布流程中 CI 在构建前校验 secrets 并生成 key.properties，缺失会直接失败，不会静默发布 debug 签名产物。
                println("WARNING: release signing key not configured (android/key.properties missing or incomplete); falling back to debug signing for local development only.")
                signingConfig = signingConfigs.getByName("debug")
            }
            
            // 启用 R8 混淆以减小 APK 体积
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    // 多架构 APK 分包配置
    splits {
        abi {
            isEnable = true
            reset()
            include("armeabi-v7a", "arm64-v8a", "x86_64")
            isUniversalApk = true  // 同时生成通用 APK
        }
    }
}

flutter {
    source = "../.."
}
