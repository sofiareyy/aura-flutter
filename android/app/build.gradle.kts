import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Credenciales de firma. Viven en android/key.properties, que está en
// .gitignore junto con el .jks: NUNCA se commitean. El keystore en si esta
// fuera del repo (ver storeFile).
//
// Si el archivo no esta (otra maquina, CI sin secretos), el release queda SIN
// FIRMAR a proposito. Antes caia a `signingConfigs.getByName("debug")`, que
// compilaba igual y recien fallaba al subirlo a Play; un release sin firmar
// falla antes y no se puede confundir con uno bueno.
val keystorePropertiesFile = rootProject.file("key.properties")
val hasKeystore = keystorePropertiesFile.exists()
val keystoreProperties = Properties().apply {
    if (hasKeystore) FileInputStream(keystorePropertiesFile).use { load(it) }
}

android {
    namespace = "com.aura.aura_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Requerido por flutter_local_notifications (usa APIs de java.time).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Identificador definitivo en Play. Igual al bundle de iOS.
        //
        // NO se puede cambiar despues de publicar: cambiarlo es una app nueva,
        // sin reseñas ni usuarios. Si se toca, hay que actualizar tambien
        // `package_name` en web/.well-known/assetlinks.json.
        //
        // Ojo: `namespace` (arriba) sigue siendo com.aura.aura_app a proposito.
        // Es el paquete Java/Kotlin de MainActivity, no tiene que coincidir con
        // el applicationId, y cambiarlo obligaria a mover el archivo de carpeta.
        applicationId = "app.somosaura.aura"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Clave de SUBIDA (upload key). Con Play App Signing activado,
            // Google guarda la clave de firma final y re-firma los APKs.
            signingConfig = if (hasKeystore) signingConfigs.getByName("release") else null
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Core library desugaring: habilita APIs modernas de Java (java.time, etc.)
    // en minSdk bajos. Lo exige flutter_local_notifications.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
