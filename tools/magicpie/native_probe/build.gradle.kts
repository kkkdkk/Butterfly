plugins {
    id("com.android.application") version "8.13.2"
}
val copyStylusInput by tasks.registering(Sync::class) {
    from("../../../app/android/app/src/main/java/dev/linwood/butterfly/BufferedStylusInput.java")
    into(layout.buildDirectory.dir("generated/stylusInput/dev/linwood/butterfly"))
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
        testInstrumentationRunner = "dev.linwood.butterfly.BufferedStylusInputTest"
    }

    sourceSets.getByName("main").java.srcDir(layout.buildDirectory.dir("generated/stylusInput"))

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
tasks.named("preBuild").configure { dependsOn(copyStylusInput) }
