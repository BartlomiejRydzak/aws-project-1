# Uruchomienie i wdrożenie na macOS

Instrukcja obejmuje dwa sposoby uruchomienia projektu na Macu:

1. lokalnie przez Docker Compose;
2. w AWS przez Terraform, Docker i Amazon ECR.

Komendy są przeznaczone dla Terminala macOS (zsh). W przypadku Apple Silicon obrazy do AWS są budowane jako `linux/amd64`, zgodnie z domyślną architekturą zadań Fargate w tym projekcie.

## 1. Wymagane narzędzia

Zainstaluj Homebrew, jeśli nie jest zainstalowane: <https://brew.sh/>. Następnie w Terminalu:

```bash
brew install --cask docker
brew install awscli
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

Uruchom Docker Desktop:

```bash
open -a Docker
```

Poczekaj, aż Docker Desktop pokaże, że silnik działa, i sprawdź narzędzia:

```bash
docker info
aws --version
terraform version
```

## 2. Uruchomienie lokalne przez Docker Compose

W katalogu głównym projektu uruchom:

```bash
docker compose up --build
```

Otwórz frontend pod adresem <http://localhost:4200>. Backend jest dostępny lokalnie pod <http://localhost:8080>.

Zatrzymaj aplikację przez `Ctrl+C`. Aby usunąć kontenery i sieć Compose:

```bash
docker compose down
```

Pliki przesłane lokalnie są przechowywane w wolumenie Dockera `uploads`. Zwykłe `docker compose down` go zachowuje.

## 3. Przygotuj dostęp do AWS

### AWS Academy Learner Lab

1. Uruchom Learner Lab i poczekaj, aż jego status będzie aktywny.
2. Otwórz panel **AWS Details** i skopiuj aktualne dane tymczasowe do AWS CLI.
3. W tym samym oknie Terminala ustaw dane środowiskowe. Wstaw wartości z panelu laboratorium:

```bash
export AWS_ACCESS_KEY_ID='WARTOSC_ACCESS_KEY_ID'
export AWS_SECRET_ACCESS_KEY='WARTOSC_SECRET_ACCESS_KEY'
export AWS_SESSION_TOKEN='WARTOSC_SESSION_TOKEN'
export AWS_DEFAULT_REGION='us-east-1'
```

Nie pomijaj `AWS_SESSION_TOKEN`: poświadczenia Learner Lab są tymczasowe. Po wygaśnięciu sesji skopiuj aktualne wartości i ustaw je ponownie.

### Zwykłe konto AWS

Dla standardowego profilu skonfiguruj AWS CLI poleceniem `aws configure` i podaj dane dostępowe tego profilu. Nie używaj tego sposobu dla tymczasowych danych Learner Lab, jeśli nie masz również session token.

Sprawdź, czy CLI widzi konto:

```bash
aws sts get-caller-identity
```

Polecenie powinno zwrócić identyfikator konta i ARN aktywnej tożsamości. Jeśli pojawi się błąd poświadczeń, nie przechodź dalej — najpierw odśwież dane dostępu.

## 4. Uzupełnij konfigurację Terraform

W AWS musi już istnieć bucket S3 na multimedia. Zapisz jego nazwę. Potrzebne są również ARN-y ról IAM: execution role dla ECS oraz task role backendu z dostępem do tego bucketu.

Otwórz `terraform/terraform.tfvars` (jeśli go nie masz, skopiuj `terraform/terraform.tfvars.example`) i wpisz wartości dla swojego konta:

```hcl
aws_region                         = "us-east-1"
frontend_origin                    = "*"
image_tag                          = "latest"
deploy_services                    = false
db_username                        = "appuser"
media_bucket_name                  = "DOKLADNA_NAZWA_ISTNIEJACEGO_BUCKETU"
alarm_notification_email           = "twoj-adres@example.com"
alb_response_time_threshold_seconds = 3
ecs_execution_role_arn             = "ARN_ROLI_EXECUTION_DLA_ECS"
backend_task_role_arn               = "ARN_ROLI_TASK_BACKENDU_Z_DOSTEPEM_DO_S3"
```

Zastąp trzy wartości wskazane wielkimi literami. Nazwa bucketu musi być dokładna, a ARN-y muszą pochodzić z tego samego konta AWS, na którym wdrażasz aplikację. Plik `terraform.tfvars` zawiera konfigurację lokalną i nie należy go publikować.

## 5. Utwórz infrastrukturę i repozytoria ECR

Z katalogu głównego projektu:

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

Przejrzyj plan i zatwierdź `apply`, wpisując `yes`, gdy Terraform o to poprosi. Pierwsze zastosowanie tworzy infrastrukturę, bazę, konfigurację Cognito, Lambdę, monitoring oraz repozytoria ECR. Przy `deploy_services = false` nie tworzy jeszcze usług ECS.

## 6. Zbuduj obrazy i wypchnij je do ECR

Pozostań w katalogu `terraform` i pobierz adresy repozytoriów z outputów Terraform:

```bash
REGION="$(terraform output -raw aws_region)"
BACKEND_REPO="$(terraform output -raw backend_ecr_repository_url)"
FRONTEND_REPO="$(terraform output -raw frontend_ecr_repository_url)"
REGISTRY="${BACKEND_REPO%%/*}"
```

Zaloguj Dockera do ECR:

```bash
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"
```

Wróć do katalogu głównego repozytorium. Zbuduj obrazy dla architektury Fargate i wypchnij je:

```bash
cd ..

docker build --platform linux/amd64 -t projekt1-backend ./backend
docker tag projekt1-backend:latest "${BACKEND_REPO}:latest"
docker push "${BACKEND_REPO}:latest"

docker build --platform linux/amd64 -t projekt1-frontend ./frontend
docker tag projekt1-frontend:latest "${FRONTEND_REPO}:latest"
docker push "${FRONTEND_REPO}:latest"
```

Jeśli Mac ma procesor Intel, ta sama komenda `--platform linux/amd64` również zadziała.

## 7. Uruchom usługi ECS

Otwórz `terraform/terraform.tfvars` i zmień:

```hcl
deploy_services = true
```

Wróć do Terraform i zastosuj zmianę:

```bash
cd terraform
terraform apply
```

Potwierdź plan, wpisując `yes`. Gdy otrzymasz wiadomość od SNS, potwierdź subskrypcję przez link w e-mailu.

## 8. Sprawdź wdrożenie

Pobierz publiczny adres aplikacji:

```bash
terraform output -raw application_url
```

Sprawdź stan usług ECS:

```bash
REGION="$(terraform output -raw aws_region)"
aws ecs describe-services \
  --cluster projekt1-cluster \
  --services projekt1-backend projekt1-frontend \
  --region "$REGION" \
  --query 'services[].{service:serviceName,desired:desiredCount,running:runningCount,pending:pendingCount}' \
  --output table
```

Obie usługi powinny mieć `running = 1`. Targety w obu grupach docelowych ALB powinny być `Healthy`. Otwórz adres `application_url` w przeglądarce.

## 9. Wdrożenie kolejnej wersji

Po zmianie kodu przebuduj i wypchnij odpowiedni obraz z tagiem `latest`, a następnie wymuś nowe wdrożenie usługi. Przykład dla backendu:

```bash
cd ..
docker build --platform linux/amd64 -t projekt1-backend ./backend
docker tag projekt1-backend:latest "${BACKEND_REPO}:latest"
docker push "${BACKEND_REPO}:latest"

cd terraform
aws ecs update-service \
  --cluster projekt1-cluster \
  --service projekt1-backend \
  --force-new-deployment \
  --region "$REGION"
```

Dla frontendu wykonaj analogiczne polecenia, używając `projekt1-frontend`, `$FRONTEND_REPO` i usługi `projekt1-frontend`.

Powyższe polecenia zakładają, że używasz tego samego okna Terminala, w którym ustawiono zmienne `REGION`, `BACKEND_REPO` i `FRONTEND_REPO`. W nowym oknie ustaw je ponownie, wykonując w katalogu `terraform`:

```bash
REGION="$(terraform output -raw aws_region)"
BACKEND_REPO="$(terraform output -raw backend_ecr_repository_url)"
FRONTEND_REPO="$(terraform output -raw frontend_ecr_repository_url)"
```

Nie ustawiaj `deploy_services = false` w działającym wdrożeniu, ponieważ Terraform usunie wtedy usługi ECS.

## Gdzie sprawdzić błędy

- **ECS → Clusters → projekt1-cluster → Services → Events** — błędy uruchamiania zadań.
- **CloudWatch → Log groups → `/ecs/projekt1-backend`** — logi backendu.
- **CloudWatch → Log groups → `/ecs/projekt1-frontend`** — logi frontendu.
- **EC2 → Target Groups** — stan `Healthy` lub przyczyna nieudanego health checku.
- **RDS → Databases → projekt1-postgres** — stan bazy i endpoint.

Jeśli Learner Lab wygaśnie, odśwież tymczasowe poświadczenia AWS CLI. Sama zmiana tokena nie wymaga ponownego budowania obrazów.
