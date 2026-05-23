# Atividade 3
Questão 03 - Relatório de redução de custos cloud
Goldie apresentou a meta do próximo trimestre à diretoria: 15% de redução no custo cloud até o fim do período, sem degradar SLA. Doc Brown pegou o breakdown de custos AWS do último mês e repassou a análise inicial para o time. O CSV está abaixo.

servico,categoria,custo_mensal_usd,uso_medio_pct,observacao
EC2 reservada,compute,4200,72,contrato de 1 ano
EC2 on-demand,compute,8200,45,workloads variaveis
EKS,compute,6700,58,3 clusters
RDS PostgreSQL,databases,8200,62,multi-AZ
ElastiCache Redis,databases,2100,40,cluster de producao
S3 Standard,storage,3100,,5 buckets principais
EBS gp3,storage,1600,68,volumes de producao
CloudWatch Logs,observability,2800,,retencao de 90 dias
CloudWatch Metrics,observability,900,,
Data Transfer Out,network,1900,,trafego entre regioes
NAT Gateway,network,1200,,3 gateways ativos
Lambda,compute,900,30,~12M invocacoes/mes
O relatório que vai voltar pra Goldie precisa trazer as oportunidades de economia priorizadas por impacto, quanto cada uma representa em percentual da conta total, o esforço de implementação (baixo, médio, alto) e os riscos ou pré-requisitos envolvidos em cada uma.

Tarefa. Aplicando o framework T-A-G, escrever o prompt de IA que, a partir do CSV acima, produza esse relatório alinhado à meta de 15%.

Entregue. Prompt, modelo, output e justificativa mostrando como Task, Action e Goal aparecem no prompt.
## Justificativa

Seguindo a mesma lógica anterior, tendo deixar bem separado cada etapa

### Task
Analise de relatório de custos cloud visando uma redução de 15% sem impactos de SLA.

### Action
Avalie a estrutura CSV abaixo com a finalidade de localizar ponto prioritários para redução de economia priorizadas por impacto

servico,categoria,custo_mensal_usd,uso_medio_pct,observacao
EC2 reservada,compute,4200,72,contrato de 1 ano
EC2 on-demand,compute,8200,45,workloads variaveis
EKS,compute,6700,58,3 clusters
RDS PostgreSQL,databases,8200,62,multi-AZ
ElastiCache Redis,databases,2100,40,cluster de producao
S3 Standard,storage,3100,,5 buckets principais
EBS gp3,storage,1600,68,volumes de producao
CloudWatch Logs,observability,2800,,retencao de 90 dias
CloudWatch Metrics,observability,900,,
Data Transfer Out,network,1900,,trafego entre regioes
NAT Gateway,network,1200,,3 gateways ativos
Lambda,compute,900,30,~12M invocacoes/mes

### Goal
Gere um relatório em PDF mostrando a representatividade de cada um frente ao cuto total e um esforço de implementação (Baixo, Médio, Alto) e eleque os riscos e pré-requisitos envolvidos.




## Modelo
Gemini 3.5 Flash (Conta Free)
## Prompt

Analise de relatório de custos cloud visando uma redução de 15% sem impactos de SLA.

Avalie a estrutura CSV abaixo com a finalidade de localizar ponto prioritários para redução de economia priorizadas por impacto

servico,categoria,custo_mensal_usd,uso_medio_pct,observacao
EC2 reservada,compute,4200,72,contrato de 1 ano
EC2 on-demand,compute,8200,45,workloads variaveis
EKS,compute,6700,58,3 clusters
RDS PostgreSQL,databases,8200,62,multi-AZ
ElastiCache Redis,databases,2100,40,cluster de producao
S3 Standard,storage,3100,,5 buckets principais
EBS gp3,storage,1600,68,volumes de producao
CloudWatch Logs,observability,2800,,retencao de 90 dias
CloudWatch Metrics,observability,900,,
Data Transfer Out,network,1900,,trafego entre regioes
NAT Gateway,network,1200,,3 gateways ativos
Lambda,compute,900,30,~12M invocacoes/mes

Gere um relatório em PDF mostrando a representatividade de cada um frente ao cuto total e um esforço de implementação (Baixo, Médio, Alto) e eleque os riscos e pré-requisitos envolvidos.


## Saida do Prompt (Chat)

O seu relatório analítico em formato PDF está pronto para download. O documento foi estruturado seguindo as melhores práticas globais de **FinOps (Financial Operations)** para identificar desperdícios de forma cirúrgica e atingir a meta estipulada de redução de custos sem comprometer nenhum Acordo de Nível de Serviço (SLA).

Seu relatório em PDF está pronto:


### 📊 Sumário Executivo das Descobertas e Metas

A análise detalhada da sua planilha de dados revelou um custo atual total de **USD 41.800,00/mês**.

* **Sua meta de 15% de redução:** **USD 6.270,00/mês**
* **Economia total mapeada pelo plano:** **USD 7.115,00/mês** (uma redução real de **17,02%**), fornecendo uma margem de segurança operacional para sua infraestrutura.

Abaixo, veja o resumo da estratégia de priorização (detalhada no PDF) para as principais frentes de economia:

1. **EC2 On-Demand (Gasto: USD 8.200 | Representatividade: 19,62%)**
* **Ação:** Migração de workloads estáveis (base/baseline) para **Compute Savings Plans** (compromisso de 1 ano).
* **Economia Estimada:** **USD 2.050,00/mês** (25% de redução no ativo on-demand).
* **Esforço:** Baixo.
* **Impacto no SLA:** **Nulo.** É uma alteração exclusivamente comercial e de faturamento; nenhuma instância é reiniciada.


2. **RDS PostgreSQL (Gasto: USD 8.200 | Representatividade: 19,62%)**
* **Ação:** Aquisição de **Instâncias Reservadas (RI)** para o banco de dados de produção.
* **Economia Estimada:** **USD 1.230,00/mês** (15% de economia).
* **Esforço:** Baixo.
* **Impacto no SLA:** **Nulo.** A arquitetura Multi-AZ essencial para a alta disponibilidade e resiliência do SLA de produção permanece intocada e protegida.


3. **CloudWatch Logs (Gasto: USD 2.800 | Representatividade: 6,70%)**
* **Ação:** Ajuste de retenção na console de 90 para 30 dias, criando políticas de ciclo de vida automáticas para exportar logs frios legados para o **S3 Glacier**.
* **Economia Estimada:** **USD 1.120,00/mês** (40% de redução nesta linha).
* **Esforço:** Baixo.
* **Impacto no SLA:** **Nulo.** Os logs continuam sendo coletados normalmente para monitoramento ativo e alarmes em tempo real.


4. **EKS Clusters (Gasto: USD 6.700 | Representatividade: 16,03%)**
* **Ação:** Consolidação de nós e uso de autoscaling moderno com **Karpenter** para remover o desperdício (visto que o uso médio atual reportado é de apenas 58%).
* **Economia Estimada:** **USD 1.005,00/mês** (15% de eficiência).
* **Esforço:** Médio.
* **Impacto no SLA:** **Blindado.** A aplicação de regras rígidas de *PodDisruptionBudgets (PDB)* e a distribuição multi-AZ garantem que o cluster seja otimizado sem causar indisponibilidade nas aplicações.


5. **S3 Standard (Gasto: USD 3.100 | Representatividade: 7,42%)**
* **Ação:** Ativação de **S3 Intelligent-Tiering** nos 5 buckets principais para movimentação automatizada de dados frios.
* **Economia Estimada:** **USD 930,00/mês** (30% de economia de storage).
* **Esforço:** Baixo.
* **Impacto no SLA:** **Nulo.** O Intelligent-Tiering mantém os tempos de acesso em milissegundos idênticos ao S3 Standard nas camadas frequentes e infrequentes.



---

### 📅 Cronograma Recomendado de Execução (Ondas de Entrega)

Para mitigar riscos, o plano foi segmentado no PDF em duas ondas:

* **Onda 1 (Semana 1) - FinOps Comercial & Quick Wins:** Aplicação de Savings Plans (EC2), Reserva de RDS, e regras do S3 e CloudWatch. Garante de imediato **USD 5.330,00/mês** com esforço mínimo de engenharia.
* **Onda 2 (Semanas 2 e 3) - Otimização Arquitetural:** Ajustes finos de infraestrutura como o Karpenter no EKS e implementação de VPC Endpoints (reduzindo tráfego pago que passa desnecessariamente pelo NAT Gateway). Garante os **USD 1.785,00/mês** adicionais.

O documento PDF gerado contém tabelas limpas de representatividade, gráficos analíticos visuais das fatias de custos, detalhamento completo de riscos mitigados e os pré-requisitos técnicos exigidos para cada item do plano.



## Resultados

Arquivo pdf Relatorio_Analise_Custos_Cloud_FinOps.pdf