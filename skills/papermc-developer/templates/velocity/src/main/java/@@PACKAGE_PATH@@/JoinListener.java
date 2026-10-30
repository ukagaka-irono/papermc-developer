package @@PACKAGE@@;

import com.velocitypowered.api.event.Subscribe;
import com.velocitypowered.api.event.connection.PostLoginEvent;
import com.velocitypowered.api.proxy.Player;
import net.kyori.adventure.text.minimessage.MiniMessage;
import net.kyori.adventure.text.minimessage.tag.resolver.Placeholder;

final class JoinListener {

    @Subscribe
    public void onPostLogin(final PostLoginEvent event) {
        final Player player = event.getPlayer();
        player.sendMessage(MiniMessage.miniMessage().deserialize(
            "<green>Welcome to the proxy, <player>!", Placeholder.unparsed("player", player.getUsername())));
    }
}
