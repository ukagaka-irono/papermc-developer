plugins {
    java
    id("xyz.jpenilla.run-velocity") version "@@RUN_VELOCITY@@"
}

group = "@@GROUP@@"
version = "0.1.0"
description = "@@DESCRIPTION@@"

repositories {
    mavenCentral()
    maven("https://repo.papermc.io/repository/maven-public/")
}

dependencies {
    compileOnly("com.velocitypowered:velocity-api:@@VELOCITY@@")
    // Generates velocity-plugin.json from the @Plugin annotation.
    annotationProcessor("com.velocitypowered:velocity-api:@@VELOCITY@@")
}

java {
    toolchain.languageVersion.set(JavaLanguageVersion.of(@@JAVA@@))
}

// BuildConstants.VERSION is the version above, so @Plugin(version = ...) never needs editing.
val generateBuildConstants by tasks.registering {
    val outputDir = layout.buildDirectory.dir("generated/sources/buildConstants/java")
    val pluginVersion = project.version.toString()
    inputs.property("version", pluginVersion)
    outputs.dir(outputDir)
    doLast {
        val file = outputDir.get().file("@@PACKAGE_PATH@@/BuildConstants.java").asFile
        file.parentFile.mkdirs()
        file.writeText(
            "package @@PACKAGE@@;\n\n" +
                "final class BuildConstants {\n" +
                "    static final String VERSION = \"" + pluginVersion + "\";\n\n" +
                "    private BuildConstants() {\n    }\n}\n"
        )
    }
}

sourceSets.main {
    java.srcDir(generateBuildConstants)
}

tasks.withType<JavaCompile>().configureEach {
    options.encoding = "UTF-8"
    options.compilerArgs.addAll(listOf("-Xlint:deprecation", "-Xlint:unchecked"))
}

tasks.runVelocity {
    // ./gradlew runVelocity starts a proxy with this plugin in run/ (interactive console).
    velocityVersion("@@VELOCITY@@")
}
