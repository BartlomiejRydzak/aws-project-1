variable "db_username" {
  description = "Nazwa użytkownika bazy PostgreSQL"
  type        = string
  sensitive   = true
}

resource "aws_db_subnet_group" "main" {
  name       = "projekt1-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "projekt1-db-subnet-group"
  }
}

resource "aws_db_instance" "postgres" {
  identifier        = "projekt1-postgres"
  engine            = "postgres"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp3"

  db_name                     = "projekt1"
  username                    = var.db_username
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  storage_encrypted          = true
  auto_minor_version_upgrade = true

  backup_retention_period = 0
  deletion_protection     = false
  skip_final_snapshot     = true

  tags = {
    Name = "projekt1-postgres"
  }
}

