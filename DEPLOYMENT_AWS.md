# Wdrożenie aplikacji do AWS

Instrukcja zakłada AWS Academy Learner Lab, PowerShell, AWS CLI, Terraform i Docker Desktop. Dla nowego wdrożenia wykonuj kroki po kolei.

## 1. Uruchom AWS i sprawdź Docker

Uruchom Learner Lab i skonfiguruj AWS CLI aktualnymi poświadczeniami z laboratorium. Nie używaj wygasłych kluczy sesyjnych.

```powershell
aws sts get-caller-identity
docker info
```

`docker info` powinno pokazać sekcję `Server` bez błędu.

## 2. Ustaw `terraform/terraform.tfvars`

Uzupełnij wartości dla swojego środowiska. Podaj poprawne ARN-y ról oraz adres e-mail dla powiadomień:

```hcl
aws_region = "us-east-1"
deploy_services = false
db_username = "appuser"
media_bucket_name = "NAZWA-ISTNIEJACEGO-BUCKETU"
ecs_execution_role_arn = "ARN-ROLI-ECS"
backend_task_role_arn = "ARN-ROLI-BACKEND"
alarm_notification_email = "twoj-adres@example.com"
alb_response_time_threshold_seconds = 3
```

Nazwa zmiennej to `backend_task_role_arn` (nie `backned_task_role_arn`). W Learner Lab bucket S3 musi już istnieć. Konfiguracja używa go jako istniejącego zasobu, ponieważ polityka SCP laboratorium blokuje Terraformowi odczyt konfiguracji Object Lock.

## 3. Utwórz infrastrukturę i repozytoria ECR

```powershell
Set-Location terraform
terraform init
terraform apply
```

Zatwierdź plan. Ten etap tworzy infrastrukturę, Cognito, Lambdę, CloudWatch, ALB i repozytoria ECR. Przy `deploy_services = false` nie uruchamia usług ECS.

## 4. Zaloguj Dockera do ECR i wypchnij obrazy

Wciąż w katalogu `terraform` pobierz adresy repozytoriów i region:

```powershell
$region = terraform output -raw aws_region
$backendRepo = terraform output -raw backend_ecr_repository_url
$frontendRepo = terraform output -raw frontend_ecr_repository_url
$registry = ($backendRepo -split "/")[0]

Set-Location ..
cmd /c "aws ecr get-login-password --region $region | docker login --username AWS --password-stdin $registry"
```

Użyj `cmd /c` do logowania. W tym środowisku potok PowerShell powodował błąd HTTP 400, a polecenie uruchomione przez `cmd` zadziałało.

Zbuduj i wypchnij obrazy z katalogu głównego projektu:

```powershell
docker build -t projekt1-backend ./backend
docker tag projekt1-backend:latest "${backendRepo}:latest"
docker push "${backendRepo}:latest"

docker build -t projekt1-frontend ./frontend
docker tag projekt1-frontend:latest "${frontendRepo}:latest"
docker push "${frontendRepo}:latest"
```

## 5. Uruchom usługi ECS

Zmień w `terraform/terraform.tfvars`:

```hcl
deploy_services = true
```

Następnie zastosuj konfigurację:

```powershell
Set-Location terraform
terraform apply
```

Potwierdź subskrypcję SNS przez link w wiadomości e-mail.

## 6. Sprawdź wdrożenie i otwórz aplikację

```powershell
$region = terraform output -raw aws_region
terraform output -raw application_url

aws ecs describe-services --cluster projekt1-cluster --services projekt1-backend projekt1-frontend --region $region --query "services[].{service:serviceName,desired:desiredCount,running:runningCount,pending:pendingCount}" --output table
```

Otwórz adres zwrócony przez `application_url`. Usługi powinny mieć `running = 1`.

## Wdrażanie kolejnych wersji obrazów

Po zbudowaniu i wypchnięciu nowego obrazu z tagiem `latest`, wymuś ponowne wdrożenie odpowiedniej usługi, aby ECS pobrał aktualny obraz:

```powershell
aws ecs update-service --cluster projekt1-cluster --service projekt1-backend --force-new-deployment --region $region
aws ecs update-service --cluster projekt1-cluster --service projekt1-frontend --force-new-deployment --region $region
```

Nie ustawiaj `deploy_services = false` w działającym wdrożeniu — Terraform usunie wtedy usługi ECS z konfiguracji.
