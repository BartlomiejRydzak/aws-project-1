#!/bin/sh
# Zapisuje adres API i publiczne ustawienia klienta Cognito przy starcie kontenera.
printf '{ "apiUrl": "%s", "cognitoRegion": "%s", "userPoolId": "%s", "clientId": "%s" }\n' \
  "${API_URL:-http://localhost:8080/api}" \
  "${COGNITO_REGION:-}" \
  "${COGNITO_USER_POOL_ID:-}" \
  "${COGNITO_CLIENT_ID:-}" > /usr/share/nginx/html/assets/config.json
