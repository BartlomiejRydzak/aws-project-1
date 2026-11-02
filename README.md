# Pokój – czat grupowy (Spring Boot + Angular)

Dwa niezależne moduły: `backend/` (Java 17, Spring Boot) i `frontend/` (Angular 17).

## Endpointy backendu (`/api`)
| Metoda | Ścieżka | Opis |
|---|---|---|
| GET | `/messages?after=ID` | lista wiadomości (opcjonalnie tylko nowsze) |
| GET | `/users` | lista użytkowników w pokoju |
| POST | `/users` | dołączenie do czatu `{ "username": "Ala" }` |
| POST | `/messages` | wysłanie wiadomości `{ "author", "text", "fileId" }` |
| POST | `/files` | upload pliku multimedialnego (multipart, pole `file`) |
| GET | `/files/{id}` | pobranie / wyświetlenie pliku |

## Uruchomienie – oddzielnie
```bash
# backend
cd backend
docker build -t chat-backend .
docker run -p 8080:8080 -e CORS_ORIGINS=http://localhost:4200 -v chat-uploads:/data/uploads chat-backend

# frontend (API_URL = publiczny adres backendu)
cd frontend
docker build -t chat-frontend .
docker run -p 4200:80 -e API_URL=http://localhost:8080/api chat-frontend
```
Otwórz http://localhost:4200

## Uruchomienie – razem
`docker compose up --build`

## Bez Dockera
- backend: `cd backend && mvn spring-boot:run`
- frontend: `cd frontend && npm install && npm start` (http://localhost:4200)

Hostując na różnych serwerach ustaw `CORS_ORIGINS` (backend) na adres frontendu oraz `API_URL` (frontend) na adres backendu.

## AWS (punkty 1–9)

W chmurze aplikacja korzysta z Cognito (rejestracja i logowanie; nowi użytkownicy są automatycznie potwierdzani przez trigger Lambda, bez weryfikacji adresu e-mail), PostgreSQL RDS (użytkownicy i wiadomości), S3 (multimedia) oraz dwóch niezależnych usług ECS Fargate (frontend i backend). W zwykłym koncie Terraform tworzy role IAM. W AWS Academy Learner Lab użyj dostarczonej przez laboratorium roli, jeśli jej trust policy pozwala na `ecs-tasks.amazonaws.com` i ma wymagane uprawnienia.

Wdrożenie jest dwuetapowe, bo repozytoria ECR muszą istnieć przed wysłaniem obrazów, a usługi Fargate przed startem muszą mieć obrazy. W Learner Lab bucket S3 jest przekazywany jako istniejący data source, aby ominąć zablokowany przez SCP odczyt Object Lock; jego utworzenie może wymagać konsoli AWS. Ustaw jego nazwę i oba ARN-y ról w `terraform.tfvars`.

1. Skonfiguruj bieżące poświadczenia Learner Lab w AWS CLI. W `terraform/terraform.tfvars` ustaw region, nazwę użytkownika bazy, nazwę istniejącego bucketu oraz ARN-y gotowych ról. Hasło nie jest przechowywane w pliku; RDS generuje je i przechowuje w Secrets Manager.
2. Uruchom `terraform init` i `terraform apply` w katalogu `terraform/`. Pierwsze zastosowanie tworzy infrastrukturę, Cognito i repozytoria ECR, ale jeszcze nie uruchamia serwisów.
3. Zaloguj Dockera do ECR i wypchnij oba obrazy (komendy wykonaj z katalogu głównego repozytorium):
   ```bash
   cd terraform
   aws ecr get-login-password --region "$(terraform output -raw aws_region)" | docker login --username AWS --password-stdin "$(terraform output -raw backend_ecr_repository_url | cut -d/ -f1)"
   cd ..
   docker build -t projekt1-backend ./backend
   docker tag projekt1-backend:latest "$(cd terraform && terraform output -raw backend_ecr_repository_url):latest"
   docker push "$(cd terraform && terraform output -raw backend_ecr_repository_url):latest"
   docker build -t projekt1-frontend ./frontend
   docker tag projekt1-frontend:latest "$(cd terraform && terraform output -raw frontend_ecr_repository_url):latest"
   docker push "$(cd terraform && terraform output -raw frontend_ecr_repository_url):latest"
   ```
4. Wróć do katalogu `terraform/`, ustaw `deploy_services = true` w `terraform.tfvars` i uruchom `terraform apply` ponownie. Zachowaj tę wartość przy kolejnych zastosowaniach Terraform. Wyjście `application_url` wskazuje frontend. ALB kieruje `/api/*` do odrębnego serwisu backendu.

Terraform tworzy serwisy w publicznych podsieciach z publicznym adresem IP, aby mogły pobrać obrazy ECR bez NAT Gateway. RDS pozostaje w podsieciach prywatnych; port 5432 jest dostępny tylko z grupy bezpieczeństwa backendu. ALB udostępnia HTTP, więc to wdrożenie laboratoryjne i nie powinno przenosić prawdziwych haseł użytkowników bez dodania HTTPS.

Lokalne uruchomienie zachowuje H2 i lokalny katalog plików. Cognito oraz S3 włączają się przez zmienne konfiguracyjne w kontenerach AWS; nie potrzeba poświadczeń AWS w kodzie ani w obrazie.
