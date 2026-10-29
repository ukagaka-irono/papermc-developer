@@BEGIN:DATABASE@@
package @@PACKAGE@@;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.nio.file.Path;
import org.bukkit.configuration.file.YamlConfiguration;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class DatabaseTest {

    @TempDir
    Path folder;

    @Test
    void countsHellosPerName() throws Exception {
        final YamlConfiguration config = new YamlConfiguration();
        config.set("type", "sqlite");
        config.set("sqlite-file", "test.db");
        final Database database = Database.fromConfig(config, folder.toFile());
        database.start();
        try {
            assertEquals(1, database.countHello("Steve").get());
            assertEquals(2, database.countHello("Steve").get());
            assertEquals(1, database.countHello("Alex").get());
        } finally {
            database.close();
        }
    }
}
@@END:DATABASE@@
