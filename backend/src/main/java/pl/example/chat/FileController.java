package pl.example.chat;

import org.springframework.core.io.Resource;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.server.ResponseStatusException;

import java.io.IOException;

import pl.example.chat.Models.FileInfo;

@RestController
@RequestMapping("/api/files")
public class FileController {

    private final FileStorage storage;

    public FileController(FileStorage storage) {
        this.storage = storage;
    }

    /** POST (multimedia): przesłanie pliku (multipart/form-data, pole "file"). */
    @PostMapping(consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<FileInfo> upload(@RequestParam("file") MultipartFile file) throws IOException {
        if (file.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Plik jest pusty.");
        }
        try {
            return ResponseEntity.status(HttpStatus.CREATED).body(storage.save(file));
        } catch (IllegalArgumentException e) {
            throw new ResponseStatusException(HttpStatus.UNSUPPORTED_MEDIA_TYPE, e.getMessage());
        }
    }

    /** GET (multimedia): pobranie / wyświetlenie pliku po ID. */
    @GetMapping("/{id}")
    public ResponseEntity<Resource> download(@PathVariable String id) {
        FileInfo info = storage.info(id);
        Resource res = storage.load(id);
        if (info == null || res == null) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Nie znaleziono pliku.");
        }
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(info.contentType()))
                .header(HttpHeaders.CONTENT_DISPOSITION,
                        ContentDisposition.inline().filename(info.name()).build().toString())
                .body(res);
    }
}
