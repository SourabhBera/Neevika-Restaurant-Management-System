import org.gradle.api.tasks.Delete
import org.gradle.api.file.Directory
import com.android.build.gradle.BaseExtension
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile // Add this import at the top

buildscript {
    repositories {
        google()
        mavenCentral() // Fixed: was "maincentral"
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.9.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.1.20")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral() // Fixed: was "maincentral"
    }
}
// --- SUBPROJECTS BLOCK ---
subprojects {
    afterEvaluate {
        val project = this
        // 1. Fix for Java/Android compilation
        if (project.extensions.findByName("android") != null) {
            configure<BaseExtension> {
                compileSdkVersion(36)
                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
            }
        }
        
        // 2. THE FIX: Force Kotlin to match Java 17
        project.tasks.withType<KotlinCompile>().configureEach {
            kotlinOptions {
                jvmTarget = "17"
            }
        }
    }
}
// --- REPLACED SUBPROJECTS BLOCK END ---

plugins {
    id("com.google.gms.google-services") version "4.4.2" apply false
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// Ensure Flutter tooling can find the generated APKs by copying them
// to the Flutter project's expected build location after assemble.
tasks.register("copyApksToFlutterBuild") {
    doLast {
        val srcDir = file("app/build/outputs/flutter-apk")
        val destDir = file(rootProject.projectDir.parentFile.resolve("build/app/outputs/flutter-apk"))
        if (srcDir.exists()) {
            destDir.mkdirs()
            copy {
                from(srcDir)
                into(destDir)
            }
        }
    }
}

// Attach the copy task to subproject assemble tasks after projects are evaluated
gradle.projectsEvaluated {
    rootProject.subprojects.forEach { p ->
        p.tasks.matching { it.name == "assembleDebug" || it.name == "assembleRelease" }
            .configureEach {
                finalizedBy(tasks.named("copyApksToFlutterBuild"))
            }
    }
}