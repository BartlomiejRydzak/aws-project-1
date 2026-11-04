terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "Region AWS, w którym tworzymy zasoby"
  type        = string
  default     = "us-east-1"
}

variable "image_tag" {
  description = "Tag obu obrazów opublikowanych w ECR"
  type        = string
  default     = "latest"
}

variable "deploy_services" {
  description = "Włącz po opublikowaniu obrazów w repozytoriach ECR"
  type        = bool
  default     = false
}

variable "frontend_origin" {
  description = "Origin frontendu do konfiguracji CORS backendu"
  type        = string
  default     = "*"
}

variable "ecs_execution_role_arn" {
  description = "ARN gotowej roli laboratorium dla uruchamiania kontenerów ECS"
  type        = string
}

variable "backend_task_role_arn" {
  description = "ARN gotowej roli laboratorium z dostępem backendu do S3"
  type        = string
}

variable "media_bucket_name" {
  description = "Istniejący bucket S3 utworzony w AWS; w Learner Lab zarządzany jako data source z powodu SCP"
  type        = string
}

variable "alarm_notification_email" {
  description = "Adres email odbierający powiadomienia alarmów CloudWatch; subskrypcję trzeba potwierdzić z wiadomości SNS"
  type        = string
}

variable "alb_response_time_threshold_seconds" {
  description = "Próg średniego czasu odpowiedzi backendu ALB w sekundach"
  type        = number
  default     = 3
}

data "aws_caller_identity" "current" {}

output "aws_account_id" {
  description = "ID konta AWS"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  value = var.aws_region
}
