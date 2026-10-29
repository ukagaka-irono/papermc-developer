package @@PACKAGE@@;

import com.mojang.brigadier.Command;
import com.mojang.brigadier.tree.LiteralCommandNode;
import com.velocitypowered.api.command.BrigadierCommand;
import com.velocitypowered.api.command.CommandSource;
import net.kyori.adventure.text.minimessage.MiniMessage;

// /hello on the proxy. Velocity has no default permissions for players: a check such as
// source.hasPermission("@@VELOCITY_ID@@.hello") needs a permissions plugin (e.g. LuckPerms) to grant it.
final class HelloCommand {

    private HelloCommand() {
    }

    static BrigadierCommand create() {
        final LiteralCommandNode<CommandSource> node = BrigadierCommand.literalArgumentBuilder("hello")
            .executes(context -> {
                context.getSource().sendMessage(MiniMessage.miniMessage().deserialize("<green>Hello from the proxy!"));
                return Command.SINGLE_SUCCESS;
            })
            .build();
        return new BrigadierCommand(node);
    }
}
