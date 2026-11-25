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
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Ensure older Flutter plugins (e.g. connectivity_plus) compile against the same
// Android SDK as :app so newer transitive AndroidX dependencies pass AAR checks.
subprojects {
    if (project.name != "app") {
        val configureLibrarySdk = {
            if (plugins.hasPlugin("com.android.library")) {
                extensions.configure<com.android.build.api.dsl.LibraryExtension> {
                    compileSdk = 36
                }
            }
        }
        if (state.executed) {
            configureLibrarySdk()
        } else {
            afterEvaluate { configureLibrarySdk() }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
