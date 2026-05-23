
Questão 07 - Runbook para alerta recorrente

Toda semana, em média 4 vezes, o Beacon dispara o mesmo alerta no canal de plantão: [CRITICAL] High memory usage on Chronos API pods (>85% for 10min). Quem assume o plantão gasta de 30 a 40 minutos até resolver, e o tempo varia muito porque não existe procedimento documentado. Lorraine quer um runbook que qualquer plantonista consiga seguir de ponta a ponta sem depender de quem conhece o sistema. O ambiente que o runbook precisa considerar:

Chronos roda no EKS, namespace production, 6 réplicas com HPA configurado (min 4, max 12, CPU target 70%).
Deploy via Argo CD a partir do repositório hvt/chronos-api.
Dependências diretas: Ledger (PostgreSQL) e Reactor (filas SQS).
Observabilidade: métricas expostas em /metrics, logs centralizados no Beacon, dashboards em Grafana.
Ferramentas disponíveis para o plantão: kubectl, aws cli, argocd cli.
Canal de plantão: #oncall-chronos no Slack.
Time sênior de escalação: @chronos-core (SLA de resposta: 15 minutos em horário comercial, 30 fora).
O runbook precisa cobrir os passos iniciais de diagnóstico (com os comandos específicos a rodar), a verificação esperada ao final de cada passo, os critérios objetivos para escalar para o time sênior e o critério para encerrar o incidente.

Tarefa. Aplicando o framework R-I-S-E, escrever o prompt de IA que produza esse runbook procedural completo.

Entregue. Prompt, modelo, output e justificativa mostrando como Role, Input, Steps e Expectation aparecem no prompt.

## Justificativa


## Modelo
Sommet 4.6
## Prompt

SRE senior, devops, especialista em kubernetes e AWS

Chronos roda no EKS, namespace production, 6 réplicas com HPA configurado (min 4, max 12, CPU target 70%).
Deploy via Argo CD a partir do repositório hvt/chronos-api.
Dependências diretas: Ledger (PostgreSQL) e Reactor (filas SQS).
Observabilidade: métricas expostas em /metrics, logs centralizados no Beacon, dashboards em Grafana.
Ferramentas disponíveis para o plantão: kubectl, aws cli, argocd cli.
Canal de plantão: #oncall-chronos no Slack.


Criar um runbook em markdown para virar uma documentação, com os seguintes passos.
1. Verificar o Alerta.
2. Acessar o ambiente kubernetes.
3. Aistar os logs do Chornos API que está acusando o alerta.
4. Avaliar a cusa raiz.
5. Aplicar correções.

Use comando Kubectl, PronQL para logs e construa as possibilidade de correção.


## Saida do Prompt (Chat)

O usuário quer um runbook em markdown — não um `.docx`. Vou criar diretamente o arquivo `.md`.Runbook gerado. Aqui está o que foi coberto em cada seção:

**1. Verificar o Alerta** — tabela com as categorias mais comuns (`HighErrorRate5xx`, `PodCrashLooping`, `HPAMaxReplicasReached`, etc.) com prioridade e provável causa, mais um checklist de metadados para anotar antes de agir.

**2. Acessar o Ambiente** — sequência completa: `aws eks update-kubeconfig`, verificação de contexto, estado do Deployment, HPA e eventos do namespace.

**3. Listar Logs** — três camadas:
- `kubectl logs` com flags úteis (`--previous`, `--prefix`, label selector)
- Queries **LogQL** (Loki/Beacon) para erros, trace_id, volume por pod, e erros específicos de Ledger e Reactor
- Queries **PromQL** para taxa de 5xx, latência p99, pods not-ready, CPU e réplicas

**4. Avaliar a Causa Raiz** — árvore de decisão visual + subseções para cada categoria: CrashLoop/OOM, erros de aplicação, degradação de dependência e problemas de capacidade/rollout.

**5. Aplicar Correções** — 7 cenários cobertos: restart de pods, ajuste de memory limit, rollback via Argo CD, escala manual de réplicas, problemas com Ledger/SQS, forçar sync no Argo CD e renovação de credenciais ECR.

## Resultados

Gerado o arquivo runbook-chronos-api.md
