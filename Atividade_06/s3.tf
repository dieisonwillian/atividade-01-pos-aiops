###############################################################################
# Módulo padrão interno HVT - Criação de Buckets S3
#
# Garante por construção (não é opcional para os times):
#   - Tags obrigatórias: Owner, CostCenter, Environment
#   - Prefixo "hvt-" em todos os nomes de recursos
#   - Criptografia server-side habilitada (SSE-S3 no mínimo)
#   - Versionamento ativo
#   - Block public access TOTAL
#   - Logging de acesso configurado
###############################################################################

# Provider AWS v4+ é obrigatório: nesta versão a configuração do bucket é
# dividida em recursos separados (versioning, encryption, etc.).
terraform {
  required_version = ">= 1.3"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }
}

#------------------------------------------------------------------------------
# Variáveis obrigatórias (PREENCHER no consumo do módulo)
#------------------------------------------------------------------------------

variable "bucket_name" {
  description = "Nome lógico do bucket SEM prefixo. O prefixo 'hvt-' e o sufixo de ambiente são aplicados automaticamente. Ex.: 'app-logs' -> 'hvt-app-logs-production'"
  type        = string
}

variable "owner" {
  description = "Responsável pelo recurso (time ou e-mail). >>> PREENCHER <<<"
  type        = string
}

variable "cost_center" {
  description = "Centro de custo para rateio financeiro. >>> PREENCHER <<<"
  type        = string
}

variable "environment" {
  description = "Nome do ambiente (dev, staging, production)."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "environment deve ser um de: dev, staging, production."
  }
}

variable "logging_target_bucket" {
  description = "Nome do bucket de destino dos logs de acesso (bucket de logging centralizado JÁ EXISTENTE). >>> PREENCHER <<<"
  type        = string
}

#------------------------------------------------------------------------------
# Variáveis opcionais (têm default seguro - alterar só se necessário)
#------------------------------------------------------------------------------

variable "logging_target_prefix" {
  description = "Prefixo (pasta) onde os logs de acesso serão gravados no bucket de destino."
  type        = string
  default     = "s3-access-logs/"
}

variable "sse_algorithm" {
  description = "Algoritmo de criptografia server-side. 'AES256' = SSE-S3 (mínimo exigido) | 'aws:kms' = SSE-KMS."
  type        = string
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "aws:kms"], var.sse_algorithm)
    error_message = "sse_algorithm deve ser 'AES256' ou 'aws:kms'."
  }
}

variable "kms_key_id" {
  description = "ARN/ID da chave KMS. Obrigatório SOMENTE quando sse_algorithm = 'aws:kms'."
  type        = string
  default     = null
}

#------------------------------------------------------------------------------
# Locals - tags comuns e padrão de nomenclatura
#------------------------------------------------------------------------------

locals {
  common_tags = {
    Owner       = var.owner
    CostCenter  = var.cost_center
    Environment = var.environment
  }

  bucket_name = "hvt-${var.bucket_name}-${var.environment}"
}

#------------------------------------------------------------------------------
# Bucket
#------------------------------------------------------------------------------

resource "aws_s3_bucket" "this" {
  bucket = local.bucket_name

  tags = merge(local.common_tags, {
    Name = local.bucket_name
  })
}

# Versionamento ativo
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Criptografia server-side (SSE-S3 por padrão, SSE-KMS opcional)
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.sse_algorithm
      kms_master_key_id = var.sse_algorithm == "aws:kms" ? var.kms_key_id : null
    }
    # Reduz custos de chamadas ao KMS quando SSE-KMS está em uso
    bucket_key_enabled = var.sse_algorithm == "aws:kms" ? true : null
  }
}

# Block public access TOTAL
resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Logging de acesso
# OBS: o bucket de destino (logging_target_bucket) precisa ter a policy de
# entrega de logs já configurada. Isso é responsabilidade do bucket de
# logging centralizado, não deste módulo.
resource "aws_s3_bucket_logging" "this" {
  bucket        = aws_s3_bucket.this.id
  target_bucket = var.logging_target_bucket
  target_prefix = "${var.logging_target_prefix}${local.bucket_name}/"
}

#------------------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------------------

output "bucket_id" {
  description = "ID/Nome do bucket criado."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN do bucket criado."
  value       = aws_s3_bucket.this.arn
}

###############################################################################
# EXEMPLO DE USO
###############################################################################
# module "bucket_app_logs" {
#   source = "git::https://git.interno.hvt/iac-modules/s3.git?ref=v1.0.0"
#
#   bucket_name           = "app-logs"                  # -> hvt-app-logs-production
#   owner                 = "time-plataforma"           # >>> PREENCHER
#   cost_center           = "CC-1234"                   # >>> PREENCHER
#   environment           = "production"
#   logging_target_bucket = "hvt-central-logs-production" # >>> PREENCHER
#
#   # Opcional: usar SSE-KMS no lugar do SSE-S3 padrão
#   # sse_algorithm = "aws:kms"
#   # kms_key_id    = "arn:aws:kms:us-east-1:111122223333:key/abcd-1234-..."
# }
#
# # Acessando os outputs:
# # module.bucket_app_logs.bucket_id
# # module.bucket_app_logs.bucket_arn
###############################################################################
