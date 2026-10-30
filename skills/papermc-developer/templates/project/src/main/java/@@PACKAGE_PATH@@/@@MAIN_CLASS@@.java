package @@PACKAGE@@;

@@BEGIN:BRIGADIER@@
import io.papermc.paper.plugin.lifecycle.event.types.LifecycleEvents;
@@END:BRIGADIER@@
import org.bukkit.plugin.java.JavaPlugin;

// Not final: MockBukkit subclasses the main class to load it in tests.
public class @@MAIN_CLASS@@ extends JavaPlugin {
@@BEGIN:DATABASE@@

    private Database database;
@@END:DATABASE@@

    @Override
    public void onEnable() {
        saveDefaultConfig();
@@BEGIN:DATABASE@@

        // config.yml "database": SQLite by default, MySQL when type is mysql.
        database = Database.fromConfig(getConfig().getConfigurationSection("database"), getDataFolder());
        try {
            database.start();
        } catch (final Exception e) {
            getLogger().severe("Cannot open the database (" + database.describe() + "): " + e.getMessage());
            database = null;
            getServer().getPluginManager().disablePlugin(this);
            return;
        }
        getLogger().info("Database: " + database.describe());
@@END:DATABASE@@

        getServer().getPluginManager().registerEvents(new JoinListener(this), this);

@@BEGIN:BRIGADIER@@
        // Commands are registered with Brigadier through the lifecycle API (no "commands:" in the yml).
        getLifecycleManager().registerEventHandler(LifecycleEvents.COMMANDS, event ->
            event.registrar().register(HelloCommand.create(this), "Says hello"));
@@END:BRIGADIER@@
@@BEGIN:LEGACY_COMMANDS@@
        // The command is declared under "commands:" in plugin.yml; getCommand returns null otherwise.
        getCommand("hello").setExecutor(new HelloCommand(this));
@@END:LEGACY_COMMANDS@@
    }

    @Override
    public void onDisable() {
@@BEGIN:DATABASE@@
        if (database != null) {
            database.close();
        }
@@END:DATABASE@@
    }
@@BEGIN:DATABASE@@

    Database database() {
        return database;
    }
@@END:DATABASE@@
}
