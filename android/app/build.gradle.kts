plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")

    id("com.google.gms.google-services")
}

android {

    namespace = "com.neelsavsani.samvibhag"

    compileSdk = flutter.compileSdkVersion

    ndkVersion = flutter.ndkVersion

    compileOptions {

        sourceCompatibility =
            JavaVersion.VERSION_17

        targetCompatibility =
            JavaVersion.VERSION_17

        // VERY IMPORTANT
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {

        jvmTarget = "17"
    }

    defaultConfig {

        applicationId =
            "com.neelsavsani.samvibhag"

        minSdk = flutter.minSdkVersion

        targetSdk =
            flutter.targetSdkVersion

        versionCode =
            flutter.versionCode

        versionName =
            flutter.versionName
    }

    buildTypes {

        release {

            signingConfig =
                signingConfigs.getByName(
                    "debug"
                )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {

    // REQUIRED
    coreLibraryDesugaring(
        "com.android.tools:desugar_jdk_libs:2.1.5"
    )
}
