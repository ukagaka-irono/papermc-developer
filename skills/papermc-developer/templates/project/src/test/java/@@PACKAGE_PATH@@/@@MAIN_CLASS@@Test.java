package @@PACKAGE@@;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import net.kyori.adventure.text.Component;
import net.kyori.adventure.text.serializer.plain.PlainTextComponentSerializer;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockbukkit.mockbukkit.MockBukkit;
import org.mockbukkit.mockbukkit.ServerMock;
import org.mockbukkit.mockbukkit.entity.PlayerMock;

class @@MAIN_CLASS@@Test {

    private ServerMock server;
    private @@MAIN_CLASS@@ plugin;

    @BeforeEach
    void setUp() {
        server = MockBukkit.mock();
        plugin = MockBukkit.load(@@MAIN_CLASS@@.class);
    }

    @AfterEach
    void tearDown() {
        MockBukkit.unmock();
    }

    @Test
    void enables() {
        assertTrue(plugin.isEnabled());
    }

    @Test
    void greetsPlayerOnJoin() {
        final PlayerMock player = server.addPlayer();
        final Component message = player.nextComponentMessage();
        assertNotNull(message);
        assertTrue(PlainTextComponentSerializer.plainText().serialize(message).contains(player.getName()));
    }
}
