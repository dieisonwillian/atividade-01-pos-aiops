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

Retone apenas o arquivo.tf com comentarios indicando as informações que devem ser preenchidas/substituidas e um exemplo de uso.

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

Pronto. O módulo segue o mesmo estilo do seu VPC (`variable` com `description` em PT, `locals.common_tags` via `merge`, recurso nomeado `this` com prefixo `hvt-` e sufixo de ambiente).

Pontos de atenção do que precisa ser preenchido/decidido pelos times:

- **`owner`, `cost_center`, `logging_target_bucket`** são obrigatórios sem default — marcados com `>>> PREENCHER <<<` nos comentários.
- **AWS Provider v4+** é exigido: a partir dessa versão versioning/encryption/logging são recursos separados (por isso o bloco `terraform { required_providers }`). Se algum time ainda usa provider v3, o módulo não aplica.
- **Logging tem uma dependência externa:** o `logging_target_bucket` precisa de uma bucket policy de entrega de logs já configurada. Isso é responsabilidade do bucket de logging centralizado, não deste módulo — deixei um comentário no recurso explicando.
- **SSE-S3 é o default** (`AES256`), cumprindo o mínimo. Deixei `sse_algorithm`/`kms_key_id` opcionais para quem quiser subir para SSE-KMS sem quebrar o padrão.

Se quiser, posso quebrar isso em `variables.tf` / `main.tf` / `outputs.tf` separados, ou adicionar uma regra de lifecycle/retention nas versões antigas.

## Resultados

Deixei o arquivo .tf também no diretório.