buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // FIXED: Aligned to 4.3.15 to prevent conflict with underlying dependency constraints
        classpath("com.google.gms:google-services:4.3.15")
    }
}

plugins {
    // This is already updated from our last step:
    id("com.android.application") version "8.11.1" apply false
    
    // FIXED: Upgrade this version from "1.8.22" to "2.2.20" to match the active classpath
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
    
    // This is already aligned from earlier:
    id("com.google.gms.google-services") version "4.3.15" apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()

rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir =
        newBuildDir.dir(project.name)

    project.layout.buildDirectory.value(
        newSubprojectBuildDir,
    )
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}