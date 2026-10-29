package @@PACKAGE@@;

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
