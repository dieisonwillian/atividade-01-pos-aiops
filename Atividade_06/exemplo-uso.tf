###############################################################################
# EXEMPLO DE USO - Módulo padrão de Buckets S3 (HVT)
#
# Este arquivo representa o repositório de um time CONSUMINDO o módulo.
# Substitua os valores marcados com >>> PREENCHER <<< pelos dados reais.
###############################################################################

#------------------------------------------------------------------------------
# Provider
#------------------------------------------------------------------------------

provider "aws" {
  region = "us-east-1" # >>> PREENCHER: região da conta/ambiente
}

#------------------------------------------------------------------------------
# Exemplo 1 - Bucket simples (criptografia padrão SSE-S3)
#------------------------------------------------------------------------------
# Nome final gerado: hvt-app-uploads-production

module "bucket_uploads" {
  source = "git::https://git.interno.hvt/iac-modules/s3.git?ref=v1.0.0"

  bucket_name           = "app-uploads"
  owner                 = "time-plataforma"            # >>> PREENCHER
  cost_center           = "CC-1234"                    # >>> PREENCHER
  environment           = "production"
  logging_target_bucket = "hvt-central-logs-production" # >>> PREENCHER
}

#------------------------------------------------------------------------------
# Exemplo 2 - Bucket com SSE-KMS (dados sensíveis)
#------------------------------------------------------------------------------
# Nome final gerado: hvt-faturamento-dados-production

module "bucket_faturamento" {
  source = "git::https://git.interno.hvt/iac-modules/s3.git?ref=v1.0.0"

  bucket_name           = "faturamento-dados"
  owner                 = "time-financeiro"            # >>> PREENCHER
  cost_center           = "CC-9988"                    # >>> PREENCHER
  environment           = "production"
  logging_target_bucket = "hvt-central-logs-production" # >>> PREENCHER

  # Sobe a criptografia para SSE-KMS
  sse_algorithm = "aws:kms"
  kms_key_id    = "arn:aws:kms:us-east-1:111122223333:key/abcd-1234-..." # >>> PREENCHER
}

#------------------------------------------------------------------------------
# Consumindo os outputs do módulo
#------------------------------------------------------------------------------

output "uploads_bucket_arn" {
  description = "ARN do bucket de uploads (útil para policies de IAM, por exemplo)."
  value       = module.bucket_uploads.bucket_arn
}

output "faturamento_bucket_id" {
  value = module.bucket_faturamento.bucket_id
}
