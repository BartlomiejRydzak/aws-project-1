package pl.example.chat;

import java.time.Instant;

public final class Models {
    private Models() {}

    public record User(String username, Instant joinedAt) {}

    public record FileInfo(String id, String name, String contentType, long size) {}

    public record Message(long id, String author, String text, FileInfo file, Instant timestamp) {}

    public record JoinRequest(String username) {}

    public record MessageRequest(String author, String text, String fileId) {}
}
