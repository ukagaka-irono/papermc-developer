package @@PACKAGE@@;

import io.papermc.paper.plugin.lifecycle.event.types.LifecycleEvents;
import org.bukkit.plugin.java.JavaPlugin;

// Not final: MockBukkit subclasses the main class to load it in tests.
public class @@MAIN_CLASS@@ extends JavaPlugin {

    @Override
    public void onEnable() {
        saveDefaultConfig();

        getServer().getPluginManager().registerEvents(new JoinListener(this), this);

        // Commands are registered with Brigadier through the lifecycle API (no "commands:" in the yml).
        getLifecycleManager().registerEventHandler(LifecycleEvents.COMMANDS, event ->
            event.registrar().register(HelloCommand.create(this), "Says hello"));
    }

    @Override
    public void onDisable() {
    }
}
