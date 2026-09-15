plugins {
    id("com.android.application") version "8.13.2"
}
android {
    namespace = "dev.linwood.butterfly.magicpie.probe"
    compileSdk = 35

    defaultConfig {
        applicationId = "dev.linwood.butterfly.magicpie.probe"
        minSdk = 27
        targetSdk = 27
        versionCode = 1
        versionName = "0.1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
