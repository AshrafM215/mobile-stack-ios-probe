// Candidate A adapter to the G1 common native module (Android) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.g1bench.g1native"
    compileSdk = 36
    defaultConfig {
        minSdk = 24
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    // the common module is included by the app's settings.gradle.kts as ":g1-native-common"
    implementation(project(":g1-native-common"))
}
