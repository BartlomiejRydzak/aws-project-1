resource "aws_cognito_user_pool" "app_users" {
  name = "projekt1-user-pool"

  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  username_attributes = ["email"]

  lambda_config {
    pre_sign_up = aws_lambda_function.auto_confirm_signup.arn
  }

  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  tags = {
    Project = "Projekt1"
  }
}

resource "aws_lambda_function" "auto_confirm_signup" {
  function_name    = "projekt1-cognito-auto-confirm"
  role             = var.ecs_execution_role_arn
  handler          = "cognito_pre_signup.handler"
  runtime          = "python3.12"
  filename         = "${path.module}/cognito_pre_signup.zip"
  source_code_hash = filebase64sha256("${path.module}/cognito_pre_signup.zip")
}

resource "aws_lambda_permission" "cognito_pre_signup" {
  statement_id  = "AllowCognitoPreSignup"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auto_confirm_signup.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.app_users.arn
}

resource "aws_cognito_user_pool_client" "frontend" {
  name         = "projekt1-frontend-client"
  user_pool_id = aws_cognito_user_pool.app_users.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  prevent_user_existence_errors = "ENABLED"

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 5

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}

output "cognito_user_pool_id" {
  description = "ID puli użytkowników Cognito"
  value       = aws_cognito_user_pool.app_users.id
}

output "cognito_user_pool_client_id" {
  description = "Publiczny identyfikator klienta frontendowego"
  value       = aws_cognito_user_pool_client.frontend.id
}

output "cognito_region" {
  description = "Region AWS dla Cognito"
  value       = var.aws_region
}
