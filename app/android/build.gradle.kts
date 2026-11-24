allprojects {
    repositories {
        google()
        mavenCentral()
    }
    tasks.matching { it.name.contains("lintVital", ignoreCase = true) }.configureEach {
        enabled = false
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    plugins.withId("com.android.library") {
        extensions.findByType(com.android.build.api.variant.LibraryAndroidComponentsExtension::class.java)?.finalizeDsl { ext ->
            if ((ext.compileSdk ?: 0) < 36) {
                ext.compileSdk = 36
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
