plugins {
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.layout.buildDirectory = rootProject.layout.projectDirectory.dir("../build")

subprojects {
    project.layout.buildDirectory = rootProject.layout.buildDirectory.get().dir(project.name)
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
