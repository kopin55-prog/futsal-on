import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// --dart-define(-from-file) 값은 Flutter 가 base64 로 묶어 "dart-defines" 속성으로 넘긴다.
// 카카오 로그인 리다이렉트 스킴(kakao{네이티브 앱 키})을 AndroidManifest 에 넣기 위해 읽는다.
// 값은 app/config/dev.json (git 제외) 에서 오며 저장소에 넣지 않는다.
val dartDefines: Map<String, String> =
    (project.findProperty("dart-defines") as String?)
        ?.split(",")
        ?.mapNotNull { encoded ->
            val decoded = String(Base64.getDecoder().decode(encoded), Charsets.UTF_8)
            val i = decoded.indexOf('=')
            if (i <= 0) null else decoded.substring(0, i) to decoded.substring(i + 1)
        }
        ?.toMap()
        ?: emptyMap()

android {
    namespace = "com.example.futsal_on"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // 임시 앱 식별자 (Q-025 보류).
        applicationId = "com.example.futsal_on"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["kakaoNativeAppKey"] = dartDefines["KAKAO_NATIVE_APP_KEY"] ?: "missing"
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
