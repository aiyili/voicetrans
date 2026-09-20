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

// google_mlkit_translation 0.15+ 的 Android 端依赖 AGP 内建 Kotlin，
// 而 Flutter 模板设置 android.builtInKotlin=false，需为其显式应用 Kotlin 插件，
// 否则插件的 Kotlin 原生代码不会编译进 AAR（运行时 MissingPluginException）。
subprojects {
    if (name == "google_mlkit_translation") {
        apply(plugin = "org.jetbrains.kotlin.android")
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
