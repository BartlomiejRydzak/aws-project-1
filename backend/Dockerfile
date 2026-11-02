# --- build ---
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /build
COPY pom.xml .
RUN mvn -q -B dependency:go-offline
COPY src ./src
RUN mvn -q -B package -DskipTests

# --- run ---
FROM eclipse-temurin:17-jre
WORKDIR /app
COPY --from=build /build/target/chat-backend.jar app.jar
RUN mkdir -p /data/uploads
ENV APP_UPLOAD_DIR=/data/uploads \
    CORS_ORIGINS=http://localhost:4200
VOLUME /data/uploads
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
