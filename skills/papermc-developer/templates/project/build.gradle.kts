@@BEGIN:CRAFTBUKKIT@@
// papermc-developer: platform=craftbukkit (Bukkit API only: no player.spigot(), no net.md_5.bungee)
@@END:CRAFTBUKKIT@@
plugins {
    java
@@BEGIN:PAPER@@
    id("xyz.jpenilla.run-paper") version "@@RUN_PAPER@@"
@@END:PAPER@@
}

group = "@@GROUP@@"
version = "0.1.0"
description = "@@DESCRIPTION@@"

repositories {
    mavenCentral()
@@BEGIN:PAPER@@
    maven("https://repo.papermc.io/repository/maven-public/")
@@END:PAPER@@
@@BEGIN:SPIGOT_REPO@@
    maven("https://hub.spigotmc.org/nexus/content/repositories/snapshots/")
@@END:SPIGOT_REPO@@
}

dependencies {
    compileOnly("@@API_DEPENDENCY@@")
@@BEGIN:TESTS@@
    testImplementation("@@API_DEPENDENCY@@")
    testImplementation("org.mockbukkit.mockbukkit:@@MOCKBUKKIT_ARTIFACT@@:@@MOCKBUKKIT_VERSION@@")
    testImplementation(platform("org.junit:junit-bom:@@JUNIT@@"))
    testImplementation("org.junit.jupiter:junit-jupiter")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
@@BEGIN:DATABASE@@
    // The server provides the JDBC drivers; the tests need SQLite's themselves.
    testRuntimeOnly("org.xerial:sqlite-jdbc:@@SQLITE_JDBC@@")
@@END:DATABASE@@
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
@@BEGIN:PAPER@@

tasks.runServer {
    // ./gradlew runServer starts a server with this plugin in run/ (interactive console).
    minecraftVersion("@@MINECRAFT@@")
}
@@END:PAPER@@
