package @@PACKAGE@@;

@@BEGIN:BRIGADIER@@
import com.mojang.brigadier.Command;
import com.mojang.brigadier.tree.LiteralCommandNode;
import io.papermc.paper.command.brigadier.CommandSourceStack;
import io.papermc.paper.command.brigadier.Commands;
@@BEGIN:DATABASE@@
import java.util.logging.Level;
@@END:DATABASE@@
import net.kyori.adventure.text.minimessage.MiniMessage;
import org.bukkit.command.CommandSender;

final class HelloCommand {

    private HelloCommand() {
    }

    static LiteralCommandNode<CommandSourceStack> create(final @@MAIN_CLASS@@ plugin) {
        return Commands.literal("hello")
            .requires(source -> source.getSender().hasPermission("@@PERMISSION_PREFIX@@.hello"))
            .executes(context -> {
                final CommandSender sender = context.getSource().getSender();
                final String format = plugin.getConfig().getString("hello-message", "<green>Hello!");
@@BEGIN:NO_DATABASE@@
                send(sender, format);
@@END:NO_DATABASE@@
@@BEGIN:DATABASE@@
                // The count comes from the database thread; sendMessage may be called from any thread.
                plugin.database().countHello(sender.getName()).whenComplete((count, error) -> {
                    if (error != null) {
                        plugin.getLogger().log(Level.WARNING, "Cannot count the hellos", error);
                        send(sender, format);
                        return;
                    }
                    plugin.getLogger().info(sender.getName() + " said hello " + count + " time(s)");
                    send(sender, format + " (#" + count + ")");
                });
@@END:DATABASE@@
                return Command.SINGLE_SUCCESS;
            })
            .build();
    }

    private static void send(final CommandSender sender, final String text) {
        sender.sendMessage(MiniMessage.miniMessage().deserialize(text));
    }
}
@@END:BRIGADIER@@
@@BEGIN:LEGACY_COMMANDS@@
@@BEGIN:DATABASE@@
import java.util.logging.Level;
@@END:DATABASE@@
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
        final String format = plugin.getConfig().getString("hello-message", "<green>Hello!");
@@END:MINIMESSAGE@@
@@BEGIN:LEGACY_TEXT@@
        final String format = plugin.getConfig().getString("hello-message", "&aHello!");
@@END:LEGACY_TEXT@@
@@BEGIN:NO_DATABASE@@
        send(sender, format);
@@END:NO_DATABASE@@
@@BEGIN:DATABASE@@
        // The count comes from the database thread; sendMessage may be called from any thread.
        plugin.database().countHello(sender.getName()).whenComplete((count, error) -> {
            if (error != null) {
                plugin.getLogger().log(Level.WARNING, "Cannot count the hellos", error);
                send(sender, format);
                return;
            }
            plugin.getLogger().info(sender.getName() + " said hello " + count + " time(s)");
            send(sender, format + " (#" + count + ")");
        });
@@END:DATABASE@@
        return true;
    }

    private static void send(final CommandSender sender, final String text) {
@@BEGIN:MINIMESSAGE@@
        sender.sendMessage(MiniMessage.miniMessage().deserialize(text));
@@END:MINIMESSAGE@@
@@BEGIN:LEGACY_TEXT@@
        sender.sendMessage(ChatColor.translateAlternateColorCodes('&', text));
@@END:LEGACY_TEXT@@
    }
}
@@END:LEGACY_COMMANDS@@
