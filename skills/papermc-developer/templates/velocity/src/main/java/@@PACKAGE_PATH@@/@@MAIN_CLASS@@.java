package @@PACKAGE@@;

import com.google.inject.Inject;
import com.velocitypowered.api.command.CommandManager;
import com.velocitypowered.api.command.CommandMeta;
import com.velocitypowered.api.event.Subscribe;
import com.velocitypowered.api.event.proxy.ProxyInitializeEvent;
import com.velocitypowered.api.plugin.Plugin;
import com.velocitypowered.api.proxy.ProxyServer;
import org.slf4j.Logger;

// velocity-plugin.json is generated from this annotation when the project is compiled.
@Plugin(
    id = "@@VELOCITY_ID@@",
    name = "@@PLUGIN_NAME@@",
    version = BuildConstants.VERSION,
    description = "@@DESCRIPTION_JAVA@@",
    authors = {@@AUTHORS_JAVA@@}
)
public final class @@MAIN_CLASS@@ {

    private final ProxyServer server;
    private final Logger logger;

    @Inject
    public @@MAIN_CLASS@@(final ProxyServer server, final Logger logger) {
        this.server = server;
        this.logger = logger;
    }

    @Subscribe
    public void onProxyInitialize(final ProxyInitializeEvent event) {
        server.getEventManager().register(this, new JoinListener());

        final CommandManager commands = server.getCommandManager();
        final CommandMeta meta = commands.metaBuilder("hello").plugin(this).build();
        commands.register(meta, HelloCommand.create());

        logger.info("Registered /hello");
    }
}
