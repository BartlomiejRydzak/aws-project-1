resource "aws_ecs_cluster" "main" {
  name = "projekt1-cluster"
}

resource "aws_ecr_repository" "backend" {
  name                 = "projekt1-backend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration { scan_on_push = true }
}

resource "aws_ecr_repository" "frontend" {
  name                 = "projekt1-frontend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration { scan_on_push = true }
}

locals {
  backend_image  = "${aws_ecr_repository.backend.repository_url}:${var.image_tag}"
  frontend_image = "${aws_ecr_repository.frontend.repository_url}:${var.image_tag}"
  db_secret_arn  = aws_db_instance.postgres.master_user_secret[0].secret_arn
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/projekt1-backend"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/projekt1-frontend"
  retention_in_days = 14
}

resource "aws_sns_topic" "api_latency" {
  name = "projekt1-api-latency"
}

resource "aws_sns_topic_subscription" "api_latency_email" {
  topic_arn = aws_sns_topic.api_latency.arn
  protocol  = "email"
  endpoint  = var.alarm_notification_email
}

resource "aws_lb" "app" {
  name               = "projekt1-app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
}

resource "aws_lb_target_group" "backend" {
  name        = "projekt1-backend-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path    = "/actuator/health"
    matcher = "200"
  }
}

resource "aws_cloudwatch_metric_alarm" "backend_response_time" {
  alarm_name          = "projekt1-backend-response-time-high"
  alarm_description   = "Średni czas odpowiedzi backendu ALB przekroczył skonfigurowany próg."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = var.alb_response_time_threshold_seconds
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.api_latency.arn]
  ok_actions          = [aws_sns_topic.api_latency.arn]

  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
    TargetGroup  = aws_lb_target_group.backend.arn_suffix
  }
}

resource "aws_lb_target_group" "frontend" {
  name        = "projekt1-frontend-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path    = "/"
    matcher = "200-399"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

resource "aws_lb_listener_rule" "backend" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
  condition {
    path_pattern { values = ["/api/*"] }
  }
}

resource "aws_ecs_task_definition" "backend" {
  family                   = "projekt1-backend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = var.ecs_execution_role_arn
  task_role_arn            = var.backend_task_role_arn
  container_definitions = jsonencode([{
    name         = "backend", image = local.backend_image, essential = true,
    portMappings = [{ containerPort = 8080, protocol = "tcp" }],
    environment = [
      { name = "CORS_ORIGINS", value = var.frontend_origin },
      { name = "APP_UPLOAD_DIR", value = "/tmp/uploads" },
      { name = "AWS_REGION", value = var.aws_region },
      { name = "S3_BUCKET", value = data.aws_s3_bucket.media.bucket },
      { name = "S3_ENABLED", value = "true" },
      { name = "DB_HOST", value = aws_db_instance.postgres.address },
      { name = "DB_PORT", value = "5432" },
      { name = "DB_NAME", value = aws_db_instance.postgres.db_name },
      { name = "SPRING_DATASOURCE_URL", value = "jdbc:postgresql://${aws_db_instance.postgres.address}:5432/${aws_db_instance.postgres.db_name}" },
      { name = "AUTH_ENABLED", value = "true" },
      { name = "COGNITO_CLIENT_ID", value = aws_cognito_user_pool_client.frontend.id },
      { name = "COGNITO_ISSUER_URI", value = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.app_users.id}" }
    ],
    secrets = [
      { name = "DB_USERNAME", valueFrom = "${local.db_secret_arn}:username::" },
      { name = "DB_PASSWORD", valueFrom = "${local.db_secret_arn}:password::" }
    ],
    logConfiguration = { logDriver = "awslogs", options = { "awslogs-group" = aws_cloudwatch_log_group.backend.name, "awslogs-region" = var.aws_region, "awslogs-stream-prefix" = "backend" } }
  }])
}

resource "aws_ecs_task_definition" "frontend" {
  family                   = "projekt1-frontend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = var.ecs_execution_role_arn
  container_definitions = jsonencode([{
    name         = "frontend", image = local.frontend_image, essential = true,
    portMappings = [{ containerPort = 80, protocol = "tcp" }],
    environment = [
      { name = "API_URL", value = "/api" },
      { name = "COGNITO_REGION", value = var.aws_region },
      { name = "COGNITO_USER_POOL_ID", value = aws_cognito_user_pool.app_users.id },
      { name = "COGNITO_CLIENT_ID", value = aws_cognito_user_pool_client.frontend.id }
    ],
    logConfiguration = { logDriver = "awslogs", options = { "awslogs-group" = aws_cloudwatch_log_group.frontend.name, "awslogs-region" = var.aws_region, "awslogs-stream-prefix" = "frontend" } }
  }])
}

resource "aws_ecs_service" "backend" {
  count           = var.deploy_services ? 1 : 0
  name            = "projekt1-backend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.backend.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend"
    container_port   = 8080
  }
  depends_on = [aws_lb_listener.http]
}

resource "aws_ecs_service" "frontend" {
  count           = var.deploy_services ? 1 : 0
  name            = "projekt1-frontend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.frontend.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "frontend"
    container_port   = 80
  }
  depends_on = [aws_lb_listener.http]
}

output "application_url" {
  value = "http://${aws_lb.app.dns_name}"
}

output "backend_ecr_repository_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "frontend_ecr_repository_url" {
  value = aws_ecr_repository.frontend.repository_url
}

output "api_latency_alarm_name" {
  value = aws_cloudwatch_metric_alarm.backend_response_time.alarm_name
}

output "api_latency_sns_topic_arn" {
  value = aws_sns_topic.api_latency.arn
}
