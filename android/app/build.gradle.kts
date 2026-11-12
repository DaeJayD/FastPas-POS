import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseProperties = Properties()
val signingPropertiesFile = rootProject.file(
    providers.gradleProperty("fastpasSigningProperties").getOrElse("key.properties")
)
if (signingPropertiesFile.exists()) {
    signingPropertiesFile.inputStream().use { releaseProperties.load(it) }
}
val configuredApplicationId = providers.gradleProperty("fastpasApplicationId")
    .getOrElse("com.example.vasenizzpos")

android {
    namespace = "com.example.vasenizzpos"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = configuredApplicationId
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = releaseProperties.getProperty("storeFile")?.let { rootProject.file(it) }
            storePassword = releaseProperties.getProperty("storePassword")
            keyAlias = releaseProperties.getProperty("keyAlias")
            keyPassword = releaseProperties.getProperty("keyPassword")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

tasks.configureEach {
    if (name in listOf("validateSigningRelease", "signReleaseBundle", "packageRelease")) {
        doFirst {
            val required = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
            if (required.any { releaseProperties.getProperty(it).isNullOrBlank() }) {
                throw GradleException(
                    "Configure release signing in android/key.properties. See docs/RELEASE.md."
                )
            }
            if (configuredApplicationId.startsWith("com.example.") ||
                !configuredApplicationId.matches(Regex("[a-zA-Z][a-zA-Z0-9_]*(\\.[a-zA-Z][a-zA-Z0-9_]*)+"))) {
                throw GradleException(
                    "Set the final Android ID with ORG_GRADLE_PROJECT_fastpasApplicationId."
                )
            }
        }
    }
}

flutter {
    source = "../.."
}
