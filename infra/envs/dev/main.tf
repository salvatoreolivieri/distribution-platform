# Composes the modules for one environment. envs/prod links to this file; the environments
# differ only in terraform.tfvars and backend.tf.

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project     = "docbridge"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  name     = "docbridge-${var.environment}"
  dist     = "${path.root}/../../../dist"
  account  = data.aws_caller_identity.current.account_id
  staging  = "${local.name}-staging"
  in_vpc   = { subnet_ids = module.network.private_subnet_ids, security_group_ids = [module.network.lambda_security_group_id] }
  db_user  = "arn:aws:rds-db:${var.region}:${local.account}:dbuser:${module.database.proxy_resource_id}"
  db_url   = "postgres://%s@${module.database.proxy_endpoint}:5432/${module.database.database_name}?sslmode=require"
  jwt_env  = { JWKS_URL = module.api.jwks_url, JWT_ISSUER = module.api.jwt_issuer, JWT_AUDIENCE = var.jwt_audience }
  base_env = { APP_ENV = var.environment, LOG_LEVEL = var.log_level, DB_IAM_AUTH = "true" }
}

# ---------------------------------------------------------------- foundation

module "network" {
  source             = "../../modules/network"
  name               = local.name
  cidr_block         = var.vpc_cidr
  single_nat_gateway = var.single_nat_gateway
}

module "database" {
  source                    = "../../modules/database"
  name                      = local.name
  vpc_id                    = module.network.vpc_id
  subnet_ids                = module.network.private_subnet_ids
  client_security_group_ids = [module.network.lambda_security_group_id]
  instance_class            = var.db_instance_class
  multi_az                  = var.db_multi_az
  deletion_protection       = var.db_deletion_protection
}

module "processing" {
  source             = "../../modules/processing"
  name               = local.name
  staging_bucket_arn = "arn:aws:s3:::${local.staging}"
  retry_budget       = var.retry_budget
  upload_handler_arn = module.fn["upload-handler"].alias_arn
  worker_arn         = module.worker.alias_arn
  dlq_handler_arn    = module.fn["dlq-handler"].alias_arn
  watchdog_arn       = module.fn["watchdog"].alias_arn
}

module "storage" {
  source                  = "../../modules/storage"
  name                    = local.name
  cors_allowed_origins    = var.web_origins
  upload_events_queue_arn = module.processing.upload_events_queue_arn
  force_destroy           = var.environment != "prod"
}

module "auth" {
  source = "../../modules/auth"
  name   = local.name
}

# ---------------------------------------------------------------- Go Lambdas

locals {
  functions = {
    auth = {
      env = merge(local.jwt_env, {
        JWT_ISSUER         = module.api.jwt_issuer
        JWT_KMS_KEY_ID     = module.auth.jwt_key_arn
        CLIENT_SECRET_ARNS = jsonencode(module.auth.client_secret_arns)
        DATABASE_URL       = format(local.db_url, "auth_svc")
      })
      statements = [
        { actions = ["kms:Sign", "kms:GetPublicKey", "kms:DescribeKey"], resources = [module.auth.jwt_key_arn] },
        { actions = ["secretsmanager:GetSecretValue"], resources = values(module.auth.client_secret_arns) },
        { actions = ["rds-db:connect"], resources = ["${local.db_user}/auth_svc"] },
      ]
    }
    platform = {
      env = merge(local.jwt_env, {
        PLATFORM_REGION  = var.platform_region
        DATABASE_URL     = format(local.db_url, "platform_svc")
        DOCUMENTS_BUCKET = module.storage.documents_bucket
        STAGING_BUCKET   = module.storage.staging_bucket
      })
      statements = [
        { actions = ["s3:GetObject", "s3:GetObjectAttributes"], resources = ["${module.storage.staging_bucket_arn}/staging/*"] },
        { actions = ["s3:PutObject", "s3:GetObject"], resources = ["${module.storage.documents_bucket_arn}/*"] },
        { actions = ["kms:Decrypt"], resources = [module.storage.staging_kms_key_arn] },
        { actions = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey"], resources = [module.storage.documents_kms_key_arn] },
        { actions = ["rds-db:connect"], resources = ["${local.db_user}/platform_svc"] },
      ]
    }
    api = {
      env = merge(local.jwt_env, {
        DATABASE_URL   = format(local.db_url, "docbridge_svc")
        STAGING_BUCKET = module.storage.staging_bucket
      })
      statements = [
        { actions = ["s3:PutObject", "s3:GetObject"], resources = ["${module.storage.staging_bucket_arn}/staging/*"] },
        { actions = ["kms:GenerateDataKey", "kms:Decrypt"], resources = [module.storage.staging_kms_key_arn] },
        { actions = ["rds-db:connect"], resources = ["${local.db_user}/docbridge_svc"] },
      ]
    }
    upload-handler = {
      env = {
        DATABASE_URL    = format(local.db_url, "docbridge_svc")
        STAGING_BUCKET  = module.storage.staging_bucket
        TASKS_QUEUE_URL = module.processing.tasks_queue_url
      }
      statements = [
        { actions = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], resources = [module.processing.upload_events_queue_arn] },
        { actions = ["sqs:SendMessage"], resources = [module.processing.tasks_queue_arn] },
        { actions = ["s3:GetObject", "s3:GetObjectAttributes"], resources = ["${module.storage.staging_bucket_arn}/staging/*"] },
        { actions = ["kms:Decrypt"], resources = [module.storage.staging_kms_key_arn] },
        { actions = ["rds-db:connect"], resources = ["${local.db_user}/docbridge_svc"] },
      ]
    }
    dlq-handler = {
      env = { DATABASE_URL = format(local.db_url, "docbridge_svc") }
      statements = [
        { actions = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], resources = [module.processing.tasks_dlq_arn] },
        { actions = ["rds-db:connect"], resources = ["${local.db_user}/docbridge_svc"] },
      ]
    }
    watchdog = {
      env = {
        DATABASE_URL    = format(local.db_url, "docbridge_svc")
        TASKS_QUEUE_URL = module.processing.tasks_queue_url
      }
      statements = [
        { actions = ["sqs:SendMessage"], resources = [module.processing.tasks_queue_arn] },
        { actions = ["rds-db:connect"], resources = ["${local.db_user}/docbridge_svc"] },
      ]
    }
    ws = {
      env = merge(local.jwt_env, {
        DATABASE_URL        = format(local.db_url, "docbridge_svc")
        MANAGEMENT_ENDPOINT = module.websocket.management_endpoint
      })
      statements = [
        { actions = ["execute-api:ManageConnections"], resources = [module.websocket.connections_arn] },
        { actions = ["rds-db:connect"], resources = ["${local.db_user}/docbridge_svc"] },
      ]
    }
  }
}

data "aws_iam_policy_document" "fn" {
  for_each = local.functions
  dynamic "statement" {
    for_each = each.value.statements
    content {
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }
}

module "fn" {
  source             = "../../modules/lambda-function"
  for_each           = local.functions
  name               = "${local.name}-${each.key}"
  runtime_kind       = "go"
  artifact_path      = "${local.dist}/${each.key}.zip"
  environment        = merge(local.base_env, each.value.env)
  policy_json        = data.aws_iam_policy_document.fn[each.key].json
  subnet_ids         = local.in_vpc.subnet_ids
  security_group_ids = local.in_vpc.security_group_ids
}

# ---------------------------------------------------------------- Python worker

data "aws_iam_policy_document" "worker" {
  statement {
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:ChangeMessageVisibility", "sqs:GetQueueAttributes"]
    resources = [module.processing.tasks_queue_arn]
  }
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [module.auth.client_secret_arns["task-worker"]]
  }
  statement {
    actions   = ["rds-db:connect"]
    resources = ["${local.db_user}/worker_svc"]
  }
}

module "worker" {
  source             = "../../modules/lambda-function"
  name               = "${local.name}-task-worker"
  runtime_kind       = "python"
  handler            = "task_worker.bootstrap.handler.handle"
  artifact_path      = "${local.dist}/task-worker.zip"
  snapstart          = true
  memory_size        = 512
  timeout            = 60
  policy_json        = data.aws_iam_policy_document.worker.json
  subnet_ids         = local.in_vpc.subnet_ids
  security_group_ids = local.in_vpc.security_group_ids
  environment = merge(local.base_env, {
    DATABASE_URL      = format(local.db_url, "worker_svc")
    CLIENT_SECRET_ARN = module.auth.client_secret_arns["task-worker"]
    AUTH_TOKEN_URL    = "${module.api.api_endpoint}/v1/auth/token"
    PLATFORM_API_URL  = module.api.api_endpoint
  })
}

# ---------------------------------------------------------------- edges

module "api" {
  source               = "../../modules/api"
  name                 = local.name
  jwt_audience         = var.jwt_audience
  cors_allowed_origins = var.web_origins
  route_backends       = var.route_backends
  backends = {
    for k in ["auth", "platform", "api"] : k => {
      function_name = module.fn[k].function_name
      alias_name    = module.fn[k].alias_name
      invoke_arn    = module.fn[k].invoke_arn
    }
  }
}

module "websocket" {
  source           = "../../modules/websocket"
  name             = "${local.name}-ws"
  ws_function_name = module.fn["ws"].function_name
  ws_alias_name    = module.fn["ws"].alias_name
  ws_invoke_arn    = module.fn["ws"].invoke_arn
}
