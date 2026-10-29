package @@PACKAGE@@;

@@BEGIN:BRIGADIER@@
import com.mojang.brigadier.Command;
import com.mojang.brigadier.tree.LiteralCommandNode;
import io.papermc.paper.command.brigadier.CommandSourceStack;
import io.papermc.paper.command.brigadier.Commands;
import net.kyori.adventure.text.minimessage.MiniMessage;

final class HelloCommand {

    private HelloCommand() {
    }

    static LiteralCommandNode<CommandSourceStack> create(final @@MAIN_CLASS@@ plugin) {
        return Commands.literal("hello")
            .requires(source -> source.getSender().hasPermission("@@PERMISSION_PREFIX@@.hello"))
            .executes(context -> {
                final String message = plugin.getConfig().getString("hello-message", "<green>Hello!");
                context.getSource().getSender().sendMessage(MiniMessage.miniMessage().deserialize(message));
                return Command.SINGLE_SUCCESS;
            })
            .build();
    }
}
@@END:BRIGADIER@@
@@BEGIN:LEGACY_COMMANDS@@
@@BEGIN:MINIMESSAGE@@
import net.kyori.adventure.text.minimessage.MiniMessage;
@@END:MINIMESSAGE@@
@@BEGIN:LEGACY_TEXT@@
import org.bukkit.ChatColor;
@@END:LEGACY_TEXT@@
import org.bukkit.command.Command;
import org.bukkit.command.CommandExecutor;
import org.bukkit.command.CommandSender;

// Runs /hello. The permission is checked by the server ("permission:" under the command in plugin.yml).
final class HelloCommand implements CommandExecutor {

    private final @@MAIN_CLASS@@ plugin;

    HelloCommand(final @@MAIN_CLASS@@ plugin) {
        this.plugin = plugin;
    }

    @Override
    public boolean onCommand(final CommandSender sender, final Command command, final String label, final String[] args) {
@@BEGIN:MINIMESSAGE@@
        final String message = plugin.getConfig().getString("hello-message", "<green>Hello!");
        sender.sendMessage(MiniMessage.miniMessage().deserialize(message));
@@END:MINIMESSAGE@@
@@BEGIN:LEGACY_TEXT@@
        final String message = plugin.getConfig().getString("hello-message", "&aHello!");
        sender.sendMessage(ChatColor.translateAlternateColorCodes('&', message));
@@END:LEGACY_TEXT@@
        return true;
    }
}
@@END:LEGACY_COMMANDS@@
