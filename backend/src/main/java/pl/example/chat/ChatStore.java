package pl.example.chat;

import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.jdbc.support.KeyHolder;
import org.springframework.stereotype.Service;

import java.sql.PreparedStatement;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.List;

import pl.example.chat.Models.*;

/** Dane czatu są zapisywane w relacyjnej bazie wskazanej przez konfigurację Spring JDBC. */
@Service
public class ChatStore {
    private final JdbcTemplate jdbc;

    public ChatStore(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public Message addMessage(String author, String text, FileInfo file) {
        Instant created = Instant.now();
        KeyHolder key = new GeneratedKeyHolder();
        jdbc.update(connection -> {
            PreparedStatement ps = connection.prepareStatement(
                    "INSERT INTO chat_messages (author, message_text, file_id, file_name, file_content_type, file_size, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    new String[] {"id"});
            ps.setString(1, author);
            ps.setString(2, text);
            ps.setString(3, file == null ? null : file.id());
            ps.setString(4, file == null ? null : file.name());
            ps.setString(5, file == null ? null : file.contentType());
            if (file == null) ps.setObject(6, null); else ps.setLong(6, file.size());
            ps.setTimestamp(7, Timestamp.from(created));
            return ps;
        }, key);
        Number id = key.getKey();
        return new Message(id.longValue(), author, text, file, created);
    }

    public List<Message> messagesAfter(long afterId) {
        return jdbc.query("SELECT * FROM chat_messages WHERE id > ? ORDER BY id", (rs, row) -> {
            String fileId = rs.getString("file_id");
            FileInfo file = fileId == null ? null : new FileInfo(fileId, rs.getString("file_name"),
                    rs.getString("file_content_type"), rs.getLong("file_size"));
            return new Message(rs.getLong("id"), rs.getString("author"), rs.getString("message_text"), file,
                    rs.getTimestamp("created_at").toInstant());
        }, afterId);
    }

    public User findByCognitoSub(String cognitoSub) {
        if (cognitoSub == null || cognitoSub.isBlank()) return null;
        List<User> users = jdbc.query("SELECT username, joined_at FROM chat_users WHERE cognito_sub = ?",
                (rs, row) -> new User(rs.getString("username"), rs.getTimestamp("joined_at").toInstant()),
                cognitoSub);
        return users.isEmpty() ? null : users.get(0);
    }

    /** Returns the account's assigned name, or null when another account owns the requested name. */
    public User join(String username, String cognitoSub) {
        User existingAccount = findByCognitoSub(cognitoSub);
        if (existingAccount != null) return existingAccount;

        String key = username.toLowerCase();
        if (cognitoSub != null && !cognitoSub.isBlank()) {
            int claimed = jdbc.update("UPDATE chat_users SET cognito_sub = ? WHERE username_key = ? AND cognito_sub IS NULL",
                    cognitoSub, key);
            if (claimed > 0) return findByCognitoSub(cognitoSub);
        }

        Instant now = Instant.now();
        try {
            jdbc.update("INSERT INTO chat_users (username_key, username, joined_at, cognito_sub) VALUES (?, ?, ?, ?)",
                    key, username, Timestamp.from(now), cognitoSub);
            return new User(username, now);
        } catch (DuplicateKeyException e) {
            return null;
        }
    }

    public boolean exists(String username) {
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM chat_users WHERE username_key = ?",
                Integer.class, username.toLowerCase());
        return count != null && count > 0;
    }

    public List<User> users() {
        return jdbc.query("SELECT username, joined_at FROM chat_users ORDER BY joined_at", (rs, row) ->
                new User(rs.getString("username"), rs.getTimestamp("joined_at").toInstant()));
    }
}
