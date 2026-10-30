@@BEGIN:DATABASE@@
package @@PACKAGE@@;

import java.io.File;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import org.bukkit.configuration.ConfigurationSection;

/**
 * The plugin's database: SQLite (a file in the plugin folder) or MySQL, chosen in config.yml ("database").
 * Every query runs on this class's own thread, never on the server's main thread. The JDBC drivers come with
 * the server (Paper, Spigot and CraftBukkit include sqlite-jdbc and the MySQL connector).
 */
final class Database {

    private final ExecutorService executor = Executors.newSingleThreadExecutor(runnable -> {
        final Thread thread = new Thread(runnable, "@@PLUGIN_NAME@@ database");
        thread.setDaemon(true);
        return thread;
    });
    private final boolean mysql;
    private final String url;
    private final String user;
    private final String password;
    private final String description;
    private Connection connection;

    private Database(final boolean mysql, final String url, final String user, final String password, final String description) {
        this.mysql = mysql;
        this.url = url;
        this.user = user;
        this.password = password;
        this.description = description;
    }

    static Database fromConfig(final ConfigurationSection config, final File dataFolder) {
        final String type = config == null ? "sqlite" : config.getString("type", "sqlite");
        if ("mysql".equalsIgnoreCase(type)) {
            final ConfigurationSection m = config.getConfigurationSection("mysql");
            final String host = m == null ? "127.0.0.1" : m.getString("host", "127.0.0.1");
            final int port = m == null ? 3306 : m.getInt("port", 3306);
            final String database = m == null ? "minecraft" : m.getString("database", "minecraft");
            final String user = m == null ? "minecraft" : m.getString("user", "minecraft");
            final String password = m == null ? "" : m.getString("password", "");
            final String properties = m == null ? "" : m.getString("properties", "");
            final String url = "jdbc:mysql://" + host + ":" + port + "/" + database + (properties.isEmpty() ? "" : "?" + properties);
            return new Database(true, url, user, password, "mysql " + host + ":" + port + "/" + database);
        }
        final String name = config == null ? "data.db" : config.getString("sqlite-file", "data.db");
        final File file = new File(dataFolder, name);
        return new Database(false, "jdbc:sqlite:" + file.getAbsolutePath(), null, null, "sqlite " + file.getPath());
    }

    String describe() {
        return description;
    }

    /** Connects and creates the tables. Waits for it, so that a wrong setting shows up when the plugin is enabled. */
    void start() throws SQLException {
        try {
            executor.submit(() -> {
                connection();
                try (Statement statement = connection().createStatement()) {
                    statement.executeUpdate("CREATE TABLE IF NOT EXISTS hello_counts (name VARCHAR(64) NOT NULL PRIMARY KEY, count INT NOT NULL)");
                }
                return null;
            }).get(30, TimeUnit.SECONDS);
        } catch (final ExecutionException e) {
            throw e.getCause() instanceof SQLException ? (SQLException) e.getCause() : new SQLException(e.getCause());
        } catch (final Exception e) {
            throw new SQLException(e);
        }
    }

    /** Adds one to the hello count of a name and returns the new count. */
    CompletableFuture<Integer> countHello(final String name) {
        return CompletableFuture.supplyAsync(() -> {
            try {
                // UPDATE, then INSERT if there was no row: works on every SQLite and MySQL version (no upsert syntax).
                try (PreparedStatement update = connection().prepareStatement("UPDATE hello_counts SET count = count + 1 WHERE name = ?")) {
                    update.setString(1, name);
                    if (update.executeUpdate() == 0) {
                        try (PreparedStatement insert = connection().prepareStatement("INSERT INTO hello_counts (name, count) VALUES (?, 1)")) {
                            insert.setString(1, name);
                            insert.executeUpdate();
                        }
                    }
                }
                try (PreparedStatement select = connection().prepareStatement("SELECT count FROM hello_counts WHERE name = ?")) {
                    select.setString(1, name);
                    try (ResultSet result = select.executeQuery()) {
                        return result.next() ? result.getInt(1) : 0;
                    }
                }
            } catch (final SQLException e) {
                throw new CompletionException(e);
            }
        }, executor);
    }

    /** Closes the connection after the queries already queued. */
    void close() {
        executor.execute(() -> {
            try {
                if (connection != null) {
                    connection.close();
                }
            } catch (final SQLException ignored) {
                // closing anyway
            }
        });
        executor.shutdown();
        try {
            executor.awaitTermination(10, TimeUnit.SECONDS);
        } catch (final InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    // Only called on the database thread. Reconnects when MySQL dropped an idle connection.
    private Connection connection() throws SQLException {
        if (connection != null && connection.isValid(2)) {
            return connection;
        }
        loadDriver();
        connection = user == null ? DriverManager.getConnection(url) : DriverManager.getConnection(url, user, password);
        return connection;
    }

    private void loadDriver() {
        // Newer servers ship com.mysql.cj.jdbc.Driver, old ones com.mysql.jdbc.Driver.
        final String[] drivers = mysql ? new String[] {"com.mysql.cj.jdbc.Driver", "com.mysql.jdbc.Driver"} : new String[] {"org.sqlite.JDBC"};
        for (final String driver : drivers) {
            try {
                Class.forName(driver);
                return;
            } catch (final ClassNotFoundException ignored) {
                // try the next name
            }
        }
    }
}
@@END:DATABASE@@
