package pl.example.chat;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;

import java.util.List;

import pl.example.chat.Models.*;

@RestController
@RequestMapping("/api")
public class ChatController {

    private final ChatStore store;
    private final FileStorage files;

    public ChatController(ChatStore store, FileStorage files) {
        this.store = store;
        this.files = files;
    }

    /** GET 1: wiadomości (opcjonalnie tylko nowsze niż ?after=ID – używane przy odpytywaniu). */
    @GetMapping("/messages")
    public List<Message> messages(
            @RequestParam(defaultValue = "0") long after,
            @RequestParam(defaultValue = "0") long delayMs) {
        // Deliberate latency hook for the CloudWatch alarm exercise. Cap it to 15 seconds.
        long boundedDelayMs = Math.max(0, Math.min(delayMs, 15_000));
        if (boundedDelayMs > 0) {
            try {
                Thread.sleep(boundedDelayMs);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "Request interrupted.");
            }
        }
        return store.messagesAfter(after);
    }

    /** GET 2: lista osób w pokoju. */
    @GetMapping("/users")
    public List<User> users() {
        return store.users();
    }

    @GetMapping("/users/me")
    public User currentUser(@AuthenticationPrincipal Jwt jwt) {
        User user = jwt == null ? null : store.findByCognitoSub(jwt.getSubject());
        if (user == null) throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Nie ustawiono jeszcze nazwy czatu.");
        return user;
    }

    /** POST 1: dołączenie do czatu. */
    @PostMapping("/users")
    public ResponseEntity<User> join(@RequestBody JoinRequest req, @AuthenticationPrincipal Jwt jwt) {
        String name = req.username() == null ? "" : req.username().trim();
        if (name.isEmpty() || name.length() > 24) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Nazwa musi mieć od 1 do 24 znaków.");
        }
        User user = store.join(name, jwt == null ? null : jwt.getSubject());
        if (user == null) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Ta nazwa jest już zajęta.");
        }
        return ResponseEntity.status(HttpStatus.CREATED).body(user);
    }

    /** POST 2: wysłanie wiadomości (tekst i/lub wcześniej przesłany plik). */
    @PostMapping("/messages")
    public ResponseEntity<Message> send(@RequestBody MessageRequest req) {
        if (req.author() == null || !store.exists(req.author())) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Najpierw dołącz do czatu.");
        }
        String text = req.text() == null ? "" : req.text().trim();
        FileInfo file = req.fileId() == null ? null : files.info(req.fileId());
        if (text.isEmpty() && file == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Wiadomość jest pusta.");
        }
        if (text.length() > 2000) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Wiadomość jest za długa (max 2000 znaków).");
        }
        return ResponseEntity.status(HttpStatus.CREATED).body(store.addMessage(req.author(), text, file));
    }
}
