import java.util.Properties

val keystoreProperties = Properties().apply {
    load(rootProject.file("key.properties").inputStream())
}

plugins {
    id("com.android.application")
    kotlin("android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

dependencies {

    implementation(platform("com.google.firebase:firebase-bom:33.13.0"))
    implementation("com.google.firebase:firebase-analytics")

    implementation("com.google.android.material:material:1.14.0-alpha01")

    // ✅ ADD THIS LINE
    implementation("androidx.multidex:multidex:2.0.1")
}


    android {
        namespace = "com.tobasu.Neevika"
        compileSdk = flutter.compileSdkVersion

        ndkVersion = "27.0.12077973"

        defaultConfig {
        applicationId = "com.tobasu.Neevika"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        multiDexEnabled = true   // ✅ ADD THIS

        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a")
        }
    }


    packaging {
        jniLibs {
            // Required for Play Store 16 KB page size compliance
            useLegacyPackaging = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = true
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}