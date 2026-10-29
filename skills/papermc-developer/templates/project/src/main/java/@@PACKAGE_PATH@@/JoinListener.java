package @@PACKAGE@@;

@@BEGIN:MINIMESSAGE@@
import net.kyori.adventure.text.minimessage.MiniMessage;
import net.kyori.adventure.text.minimessage.tag.resolver.Placeholder;
@@END:MINIMESSAGE@@
@@BEGIN:LEGACY_TEXT@@
import org.bukkit.ChatColor;
@@END:LEGACY_TEXT@@
import org.bukkit.entity.Player;
import org.bukkit.event.EventHandler;
import org.bukkit.event.Listener;
import org.bukkit.event.player.PlayerJoinEvent;

final class JoinListener implements Listener {

    private final @@MAIN_CLASS@@ plugin;

    JoinListener(final @@MAIN_CLASS@@ plugin) {
        this.plugin = plugin;
    }

    @EventHandler
    public void onJoin(final PlayerJoinEvent event) {
        final Player player = event.getPlayer();
@@BEGIN:MINIMESSAGE@@
        final String format = plugin.getConfig().getString("join-message", "<green>Welcome, <player>!");
        player.sendMessage(MiniMessage.miniMessage().deserialize(format, Placeholder.component("player", player.name())));
@@END:MINIMESSAGE@@
@@BEGIN:LEGACY_TEXT@@
        final String format = plugin.getConfig().getString("join-message", "&aWelcome, {player}!");
        player.sendMessage(ChatColor.translateAlternateColorCodes('&', format.replace("{player}", player.getName())));
@@END:LEGACY_TEXT@@
    }
}
