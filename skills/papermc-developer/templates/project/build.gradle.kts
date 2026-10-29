plugins {
    java
    id("xyz.jpenilla.run-paper") version "@@RUN_PAPER@@"
}

group = "@@GROUP@@"
version = "0.1.0"
description = "@@DESCRIPTION@@"

repositories {
    mavenCentral()
    maven("https://repo.papermc.io/repository/maven-public/")
}

dependencies {
    compileOnly("@@API_DEPENDENCY@@")
@@BEGIN:TESTS@@
    testImplementation("@@API_DEPENDENCY@@")
    testImplementation("org.mockbukkit.mockbukkit:@@MOCKBUKKIT_ARTIFACT@@:@@MOCKBUKKIT_VERSION@@")
    testImplementation(platform("org.junit:junit-bom:@@JUNIT@@"))
    testImplementation("org.junit.jupiter:junit-jupiter")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
@@END:TESTS@@
}

java {
    toolchain.languageVersion.set(JavaLanguageVersion.of(@@JAVA@@))
}

tasks.withType<JavaCompile>().configureEach {
    options.encoding = "UTF-8"
    // Shows uses of deprecated API; Paper deprecates old Bukkit API that still compiles.
    options.compilerArgs.addAll(listOf("-Xlint:deprecation", "-Xlint:unchecked"))
}

tasks.processResources {
    val props = mapOf("version" to project.version.toString())
    inputs.properties(props)
    filteringCharset = "UTF-8"
    filesMatching(listOf("plugin.yml", "paper-plugin.yml")) {
        expand(props)
    }
}
@@BEGIN:TESTS@@

tasks.test {
    useJUnitPlatform()
}
@@END:TESTS@@

tasks.runServer {
    // ./gradlew runServer starts a server with this plugin in run/ (interactive console).
    minecraftVersion("@@MINECRAFT@@")
}
