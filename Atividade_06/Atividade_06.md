## Questão 06 - Módulo Terraform no padrão interno
Strickland, que fecha a ponta de segurança e compliance, publicou o padrão interno de IaC que todo módulo Terraform novo precisa seguir:

Tags obrigatórias em todo recurso: Owner, CostCenter, Environment.
Prefixo hvt- nos nomes de recursos.
Todo bucket S3 com: encryption habilitada (SSE-S3 mínimo), versioning ativo, block public access total, logging configurado.
Variáveis de entrada em variables.tf com description e type obrigatórios.
Doc Brown pediu um módulo Terraform reutilizável pra criar buckets S3 aderentes a esse padrão. O módulo vai ser consumido por todos os times da empresa, então precisa vir com exemplo de uso. Como referência de estilo, o módulo de VPC que já existe na empresa:

variable "environment" {
  description = "Nome do ambiente (dev, staging, production)"
  type        = string
}

locals {
  common_tags = {
    Owner       = var.owner
    CostCenter  = var.cost_center
    Environment = var.environment
  }
}

resource "aws_vpc" "this" {
  cidr_block = var.cidr_block
  tags = merge(local.common_tags, {
    Name = "hvt-vpc-${var.environment}"
  })
}
Tarefa. Aplicando o framework C-A-R-E, escrever o prompt de IA que produza o módulo Terraform S3 aderente ao padrão, no mesmo estilo do exemplo.

Entregue. Prompt, modelo, output e justificativa mostrando como Context, Action, Result e Example aparecem no prompt.


- Context - Define o cenário
- Action - Define a tarefa: tem que ser bem especifico
- Result - Define o formato 
- Example - Mostra o padrão correto



## Justificativa
Montei o prompt separando com base no padrão CARE, focando em deixar bem definido e de uma forma pontual cada comando, passando o contexto inicialmente, após a ação a ser feita, na sequencia solicitei o arquivo .tf e passei o exemplo do .tf da VPC.

## Modelo
Opus 4.7

## Prompt

Implementação de um padronização interna de iac para garantir segurança e compliance.

Crie um modelo terraform para criação de buckets S3 que será utilizado por todos os times, o modelo deve contemplar essas regras:

 - Tags obrigatórias em todo recurso: Owner, CostCenter, Environment.
 - Prefixo hvt- nos nomes de recursos.
 - Todo bucket S3 com: encryption habilitada (SSE-S3 mínimo), versioning ativo, block public access total, logging configurado.

Retone apenas o arquivo.tf com comentarios indicando as informações que devem ser preenchidas/substituidas.

Siga o padrão utilizado no modulo de VPC abaixo:

variable "environment" {
  description = "Nome do ambiente (dev, staging, production)"
  type        = string
}

locals {
  common_tags = {
    Owner       = var.owner
    CostCenter  = var.cost_center
    Environment = var.environment
  }
}

resource "aws_vpc" "this" {
  cidr_block = var.cidr_block
  tags = merge(local.common_tags, {
    Name = "hvt-vpc-${var.environment}"
  })
}

## Saida do Prompt (Chat)

```hcl
# =============================================================================
# Módulo Terraform - S3 Bucket (Padrão Interno HVT)
# =============================================================================
# Este módulo cria buckets S3 seguindo o padrão de compliance interno:
# - Tags obrigatórias: Owner, CostCenter, Environment
# - Prefixo hvt- em todos os recursos
# - Encryption SSE-S3 (mínimo) habilitada
# - Versioning ativo
# - Block public access total
# - Logging configurado
# =============================================================================


# -----------------------------------------------------------------------------
# Variáveis
# -----------------------------------------------------------------------------

variable "environment" {
  description = "Nome do ambiente (dev, staging, production)"
  type        = string
  # PREENCHER: informar o ambiente alvo (ex: "dev", "staging", "production")
}

variable "owner" {
  description = "Responsável pelo recurso (time ou e-mail)"
  type        = string
  # PREENCHER: nome do time ou e-mail responsável (ex: "team-data@hvt.com")
}

variable "cost_center" {
  description = "Centro de custo para billing"
  type        = string
  # PREENCHER: identificador do centro de custo (ex: "CC-1234")
}

variable "bucket_name" {
  description = "Nome do bucket (será prefixado automaticamente com 'hvt-')"
  type        = string
  # PREENCHER: sufixo do nome do bucket (ex: "app-logs", "data-lake")
  # Resultado final: hvt-<bucket_name>-<environment>
}

variable "logging_target_bucket" {
  description = "Nome do bucket de destino para armazenamento dos logs de acesso"
  type        = string
  # PREENCHER: nome do bucket que receberá os logs (deve existir previamente)
  # Recomenda-se um bucket centralizado de logs (ex: "hvt-access-logs-prod")
}

variable "logging_target_prefix" {
  description = "Prefixo das chaves de log dentro do bucket de destino"
  type        = string
  default     = "s3-access-logs/"
  # OPCIONAL: alterar caso queira organizar logs em outro caminho
}


# -----------------------------------------------------------------------------
# Locals
# -----------------------------------------------------------------------------

locals {
  common_tags = {
    Owner       = var.owner
    CostCenter  = var.cost_center
    Environment = var.environment
  }

  bucket_full_name = "hvt-${var.bucket_name}-${var.environment}"
}


# -----------------------------------------------------------------------------
# Bucket S3
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "this" {
  bucket = local.bucket_full_name

  tags = merge(local.common_tags, {
    Name = local.bucket_full_name
  })
}


# -----------------------------------------------------------------------------
# Versioning (obrigatório: ativo)
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}


# -----------------------------------------------------------------------------
# Server-Side Encryption (obrigatório: SSE-S3 mínimo)
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
      # ALTERAR para "aws:kms" caso o time precise utilizar SSE-KMS
      # Nesse caso, adicionar também: kms_master_key_id = "<arn-da-chave-kms>"
    }
    bucket_key_enabled = true
  }
}


# -----------------------------------------------------------------------------
# Block Public Access (obrigatório: bloqueio total)
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


# -----------------------------------------------------------------------------
# Logging (obrigatório: configurado)
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_logging" "this" {
  bucket = aws_s3_bucket.this.id

  target_bucket = var.logging_target_bucket
  target_prefix = "${var.logging_target_prefix}${local.bucket_full_name}/"
}


# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "bucket_id" {
  description = "ID (nome) do bucket S3 criado"
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN do bucket S3 criado"
  value       = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  description = "Domínio do bucket S3"
  value       = aws_s3_bucket.this.bucket_domain_name
}
```

## Resultados

Deixei o arquivo .tf também no diretório.