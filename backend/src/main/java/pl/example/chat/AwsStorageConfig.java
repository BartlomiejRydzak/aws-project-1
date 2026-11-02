package pl.example.chat;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;

@Configuration
public class AwsStorageConfig {
    @Bean
    @ConditionalOnProperty(name = "app.s3.enabled", havingValue = "true")
    S3Client s3Client(@Value("${AWS_REGION:us-east-1}") String region) {
        return S3Client.builder().region(Region.of(region)).build();
    }
}
