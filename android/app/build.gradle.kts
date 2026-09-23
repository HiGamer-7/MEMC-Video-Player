plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

configure<com.android.build.api.dsl.ApplicationExtension> {
    namespace = "com.example.memc_video_player"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.example.memc_video_player"
        minSdk = 21
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

flutter {
    source = "../.."
}
