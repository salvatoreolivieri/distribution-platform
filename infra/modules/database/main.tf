# RDS Postgres behind RDS Proxy. Each service connects as its own role through the proxy
# with IAM authentication; the proxy reaches the database with one Secrets Manager secret
# per role. The roles and grants themselves come from db/migrations/000_roles.sql; the
# passwords in these secrets are set on the roles by scripts/db-role-passwords.sh.
#
# Extensions (citext, pgcrypto, pg_trgm) are created by the migrations; all three are on
# the RDS allow-list, so no parameter-group change is needed.

locals {
  roles = toset(var.service_roles)
}

resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.subnet_ids
}

resource "aws_security_group" "db" {
  name        = "${var.name}-db"
  description = "Postgres: only from the RDS Proxy"
  vpc_id      = var.vpc_id
}

resource "aws_security_group" "proxy" {
  name        = "${var.name}-proxy"
  description = "RDS Proxy: Postgres from the Lambdas"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "db_from_proxy" {
  description                  = "Postgres from the RDS Proxy"
  security_group_id            = aws_security_group.db.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.proxy.id
}

resource "aws_vpc_security_group_ingress_rule" "proxy_from_clients" {
  for_each                     = toset(var.client_security_group_ids)
  description                  = "Postgres from service Lambdas"
  security_group_id            = aws_security_group.proxy.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = each.key
}

resource "aws_vpc_security_group_egress_rule" "proxy_to_db" {
  description                  = "Postgres to the database"
  security_group_id            = aws_security_group.proxy.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.db.id
}

resource "aws_db_parameter_group" "this" {
  name   = var.name
  family = "postgres${split(".", var.engine_version)[0]}"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
}

resource "aws_db_instance" "this" {
  identifier                          = var.name
  engine                              = "postgres"
  engine_version                      = var.engine_version
  instance_class                      = var.instance_class
  allocated_storage                   = var.allocated_storage
  storage_type                        = "gp3"
  storage_encrypted                   = true
  db_name                             = var.database_name
  username                            = "migrator"
  manage_master_user_password         = true
  db_subnet_group_name                = aws_db_subnet_group.this.name
  vpc_security_group_ids              = [aws_security_group.db.id]
  parameter_group_name                = aws_db_parameter_group.this.name
  multi_az                            = var.multi_az
  backup_retention_period             = var.backup_retention_days
  deletion_protection                 = var.deletion_protection
  skip_final_snapshot                 = !var.deletion_protection
  final_snapshot_identifier           = var.deletion_protection ? "${var.name}-final" : null
  performance_insights_enabled        = true
  auto_minor_version_upgrade          = true
  enabled_cloudwatch_logs_exports     = ["postgresql", "upgrade"]
  iam_database_authentication_enabled = true
  copy_tags_to_snapshot               = true
}

resource "random_password" "role" {
  for_each = local.roles
  length   = 32
  special  = false
}

resource "aws_secretsmanager_secret" "role" {
  for_each = local.roles
  name     = "${var.name}/db/${each.key}"
}

resource "aws_secretsmanager_secret_version" "role" {
  for_each  = local.roles
  secret_id = aws_secretsmanager_secret.role[each.key].id
  secret_string = jsonencode({
    username = each.key
    password = random_password.role[each.key].result
  })
}

data "aws_iam_policy_document" "proxy_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "proxy" {
  name               = "${var.name}-proxy"
  assume_role_policy = data.aws_iam_policy_document.proxy_trust.json
}

data "aws_iam_policy_document" "proxy" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [for s in aws_secretsmanager_secret.role : s.arn]
  }
}

resource "aws_iam_role_policy" "proxy" {
  role   = aws_iam_role.proxy.id
  policy = data.aws_iam_policy_document.proxy.json
}

resource "aws_db_proxy" "this" {
  name                   = var.name
  engine_family          = "POSTGRESQL"
  role_arn               = aws_iam_role.proxy.arn
  vpc_subnet_ids         = var.subnet_ids
  vpc_security_group_ids = [aws_security_group.proxy.id]
  require_tls            = true

  dynamic "auth" {
    for_each = local.roles
    content {
      auth_scheme = "SECRETS"
      iam_auth    = "REQUIRED"
      secret_arn  = aws_secretsmanager_secret.role[auth.key].arn
    }
  }
}

resource "aws_db_proxy_default_target_group" "this" {
  db_proxy_name = aws_db_proxy.this.name
  connection_pool_config {
    max_connections_percent = 90
  }
}

resource "aws_db_proxy_target" "this" {
  db_proxy_name          = aws_db_proxy.this.name
  target_group_name      = aws_db_proxy_default_target_group.this.name
  db_instance_identifier = aws_db_instance.this.identifier
}
