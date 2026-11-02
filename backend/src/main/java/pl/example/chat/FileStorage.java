package pl.example.chat;

import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.InputStreamResource;
import org.springframework.core.io.Resource;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.HeadObjectRequest;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Base64;
import java.util.UUID;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import pl.example.chat.Models.FileInfo;

@Service
public class FileStorage {
    private final Path dir;
    private final String bucket;
    private final S3Client s3;
    private final Map<String, FileInfo> localIndex = new ConcurrentHashMap<>();

    public FileStorage(@Value("${app.upload-dir}") String uploadDir,
                       @Value("${app.s3.bucket:}") String bucket,
                       ObjectProvider<S3Client> s3Provider) throws IOException {
        this.dir = Path.of(uploadDir).toAbsolutePath().normalize();
        Files.createDirectories(dir);
        this.bucket = bucket;
        this.s3 = s3Provider.getIfAvailable();
        if (!bucket.isBlank() && s3 == null) {
            throw new IllegalStateException("S3_BUCKET ustawiono, ale klient S3 nie jest skonfigurowany.");
        }
    }

    public FileInfo save(MultipartFile file) throws IOException {
        String type = file.getContentType() == null ? "" : file.getContentType();
        if (!(type.startsWith("image/") || type.startsWith("video/") || type.startsWith("audio/"))) {
            throw new IllegalArgumentException("Dozwolone są tylko pliki obrazów, wideo i audio.");
        }
        String id = UUID.randomUUID().toString();
        String name = file.getOriginalFilename() == null ? "plik" : Path.of(file.getOriginalFilename()).getFileName().toString();
        if (usesS3()) {
            String encodedName = Base64.getUrlEncoder().withoutPadding().encodeToString(name.getBytes(StandardCharsets.UTF_8));
            s3.putObject(PutObjectRequest.builder().bucket(bucket).key(id).contentType(type)
                            .metadata(java.util.Map.of("original-name", encodedName)).build(),
                    RequestBody.fromInputStream(file.getInputStream(), file.getSize()));
        } else {
            file.transferTo(dir.resolve(id));
        }
        FileInfo info = new FileInfo(id, name, type, file.getSize());
        if (!usesS3()) localIndex.put(id, info);
        return info;
    }

    public FileInfo info(String id) {
        if (!validId(id)) return null;
        if (usesS3()) {
            try {
                var head = s3.headObject(HeadObjectRequest.builder().bucket(bucket).key(id).build());
                String encodedName = head.metadata().get("original-name");
                String name = encodedName == null ? "plik" : new String(Base64.getUrlDecoder().decode(encodedName), StandardCharsets.UTF_8);
                return new FileInfo(id, name, head.contentType(), head.contentLength());
            } catch (software.amazon.awssdk.services.s3.model.S3Exception e) {
                if (e.statusCode() == 404) return null;
                throw e;
            }
        }
        return localIndex.get(id);
    }

    public Resource load(String id) {
        if (info(id) == null) return null;
        if (usesS3()) {
            ResponseInputStream<?> stream = s3.getObject(GetObjectRequest.builder().bucket(bucket).key(id).build());
            return new InputStreamResource(stream);
        }
        return new FileSystemResource(dir.resolve(id));
    }

    private boolean usesS3() { return !bucket.isBlank(); }
    private boolean validId(String id) {
        try { UUID.fromString(id); return true; } catch (RuntimeException e) { return false; }
    }
}
