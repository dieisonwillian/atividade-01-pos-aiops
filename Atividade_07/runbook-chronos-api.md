# Runbook — Chronos API
**Namespace:** `production` | **Repositório:** `hvt/chronos-api` | **Canal de plantão:** `#oncall-chronos`

---

## Índice

1. [Verificar o Alerta](#1-verificar-o-alerta)
2. [Acessar o Ambiente Kubernetes](#2-acessar-o-ambiente-kubernetes)
3. [Listar Logs do Chronos API](#3-listar-logs-do-chronos-api)
4. [Avaliar a Causa Raiz](#4-avaliar-a-causa-raiz)
   - 4.1 [Avaliar Necessidade de Escalação](#41-avaliar-necessidade-de-escalação)
5. [Aplicar Correções](#5-aplicar-correções)
   - 5.1 [Avaliar Encerramento do Caso](#51-avaliar-encerramento-do-caso)

---

## 1. Verificar o Alerta

### 1.1 Identificar a origem

Alertas do Chronos chegam por três canais principais:

| Canal | Ferramenta | O que verificar |
|---|---|---|
| Grafana | Dashboard `chronos-api` | Gráficos de latência, error rate, saturação |
| Beacon | Logs centralizados | Mensagens de erro, stack traces, padrões recentes |
| Kubernetes / HPA | `kubectl` | Estado dos pods, eventos de escalonamento |

### 1.2 Classificar a severidade

Antes de agir, responda:

- **O que está falhando?** (endpoint, worker, dependência)
- **Desde quando?** (início do alerta vs. último deploy)
- **Qual o impacto?** (usuários afetados, degradação parcial ou indisponibilidade total)
- **Houve mudança recente?** (deploy no Argo CD, alteração em infra)

### 1.3 Conferir o último deploy no Argo CD

```bash
argocd app get chronos-api
argocd app history chronos-api
```

Verifique se o status é `Healthy` e `Synced`. Se houver `Degraded` ou `OutOfSync`, anote o timestamp do último sync.

---

## 2. Acessar o Ambiente Kubernetes

### 2.1 Configurar contexto EKS

```bash
# Atualizar kubeconfig para o cluster EKS
aws eks update-kubeconfig --region <REGION> --name <CLUSTER_NAME>

# Confirmar contexto ativo
kubectl config current-context
```

### 2.2 Verificar estado geral da aplicação

```bash
# Listar todos os pods do Chronos
kubectl get pods -n production -l app=chronos-api

# Verificar detalhes dos pods (status, restarts, age)
kubectl get pods -n production -l app=chronos-api -o wide

# Verificar o HPA (escalonamento horizontal)
kubectl get hpa -n production chronos-api
kubectl describe hpa -n production chronos-api
```

**O que observar no HPA:**

| Campo | Sinal de problema |
|---|---|
| `REPLICAS` próximo a `MAXPODS` (12) | Possível gargalo de CPU/memória |
| `TARGETS` de CPU acima de 70% | Carga acima do threshold configurado |
| `CONDITIONS` com `AbleToScale: False` | Problema no escalonamento |

### 2.3 Verificar eventos recentes do namespace

```bash
kubectl get events -n production --sort-by='.lastTimestamp' | grep chronos-api | tail -30
```

### 2.4 Verificar os pods com problemas

```bash
# Pods em CrashLoopBackOff, OOMKilled, Pending, etc.
kubectl get pods -n production -l app=chronos-api --field-selector=status.phase!=Running

# Descrever um pod específico para ver eventos e condições
kubectl describe pod <POD_NAME> -n production
```

---

## 3. Listar Logs do Chronos API

### 3.1 Logs em tempo real (kubectl)

```bash
# Logs de todos os pods simultaneamente
kubectl logs -n production -l app=chronos-api --all-containers --prefix --timestamps -f

# Logs de um pod específico
kubectl logs -n production <POD_NAME> --timestamps -f

# Logs das últimas 2 horas
kubectl logs -n production <POD_NAME> --since=2h --timestamps

# Logs de pod que reiniciou (container anterior)
kubectl logs -n production <POD_NAME> --previous --timestamps
```

### 3.2 Consultas PromQL — métricas expostas em `/metrics`

Use estas queries no Grafana (datasource Prometheus) para correlacionar com os logs.

```promql
# Taxa de erros HTTP 5xx nos últimos 5 minutos
sum(rate(http_requests_total{app="chronos-api", status=~"5.."}[5m])) by (pod)

# Taxa total de requisições por status
sum(rate(http_requests_total{app="chronos-api"}[5m])) by (status, pod)

# Latência p95 por endpoint
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{app="chronos-api"}[5m])) by (le, handler))

# Uso de CPU por pod
sum(rate(container_cpu_usage_seconds_total{namespace="production", container="chronos-api"}[5m])) by (pod)

# Uso de memória por pod
container_memory_working_set_bytes{namespace="production", container="chronos-api"}

# Pods em CrashLoopBackOff
kube_pod_container_status_waiting_reason{namespace="production", reason="CrashLoopBackOff"} == 1

# Número de reinicializações de containers
kube_pod_container_status_restarts_total{namespace="production", pod=~"chronos-api.*"}

# Disponibilidade do HPA vs réplicas desejadas
kube_horizontalpodautoscaler_status_current_replicas{namespace="production", horizontalpodautoscaler="chronos-api"}
kube_horizontalpodautoscaler_status_desired_replicas{namespace="production", horizontalpodautoscaler="chronos-api"}
```

### 3.3 Logs no Beacon (LogQL / Loki)

Se o Beacon utiliza Loki como backend, use as queries abaixo:

```logql
# Todos os logs de erro do Chronos
{app="chronos-api", namespace="production"} |= "ERROR"

# Filtrar por stack trace de exceção
{app="chronos-api", namespace="production"} |= "Exception" | json

# Logs de erro nos últimos 30 minutos
{app="chronos-api", namespace="production", level="error"} [30m]

# Erros de conexão com dependências (Ledger/Reactor)
{app="chronos-api", namespace="production"} |= "connection refused" or "timeout" or "SQS" or "PostgreSQL"

# Taxa de logs de erro por pod
sum by (pod) (rate({app="chronos-api", namespace="production", level="error"}[5m]))
```

---

## 4. Avaliar a Causa Raiz

### 4.1 Árvore de diagnóstico

Use o fluxo abaixo para identificar a categoria do problema:

```
Alerta disparado
│
├─► Pods em CrashLoopBackOff / OOMKilled?
│       └─► Ver seção 5.1 — Reinicialização / OOM
│
├─► Pods Pending (não sobem)?
│       └─► Verificar recursos do cluster (nodes, taints, limites de namespace)
│
├─► Pods Running mas com alta latência / erros 5xx?
│       ├─► Dependência Ledger (PostgreSQL) indisponível? → Ver seção 5.3
│       ├─► Dependência Reactor (SQS) com falha? → Ver seção 5.4
│       └─► Problema na própria aplicação → Ver seção 5.2
│
└─► HPA no limite máximo (12 réplicas)?
        └─► Investigar gargalo de CPU ou memory leak → Ver seção 5.5
```

### 4.2 Verificar dependências externas

**Ledger — PostgreSQL:**

```bash
# Verificar se o pod do Ledger está saudável
kubectl get pods -n production -l app=ledger

# Testar conectividade a partir de um pod do Chronos
kubectl exec -n production <CHRONOS_POD> -- nc -zv <LEDGER_SERVICE> 5432

# Verificar logs de conexão com banco
kubectl logs -n production <CHRONOS_POD> --timestamps | grep -i "postgres\|ledger\|connection\|pool"
```

```promql
# Latência de queries ao banco (se instrumentado)
histogram_quantile(0.99, rate(db_query_duration_seconds_bucket{app="chronos-api"}[5m]))

# Erros de banco
rate(db_errors_total{app="chronos-api"}[5m])
```

**Reactor — SQS:**

```bash
# Verificar filas SQS via AWS CLI
aws sqs get-queue-attributes \
  --queue-url <QUEUE_URL> \
  --attribute-names All

# Verificar número de mensagens na fila (possível acúmulo)
aws sqs get-queue-attributes \
  --queue-url <QUEUE_URL> \
  --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible

# Logs do Chronos relacionados ao SQS
kubectl logs -n production <CHRONOS_POD> --timestamps | grep -i "sqs\|reactor\|queue\|consumer"
```

### 4.3 Verificar estado do Argo CD

```bash
# Status completo da aplicação
argocd app get chronos-api --output json | jq '.status'

# Listar recursos gerenciados
argocd app resources chronos-api

# Verificar se há diff entre Git e cluster
argocd app diff chronos-api
```

---

### 4.1 Avaliar Necessidade de Escalação

| Condição | Ação |
|---|---|
| Falha em **Ledger (PostgreSQL)** | Escalar para o time do Ledger via `#oncall-ledger` |
| Falha em **Reactor (SQS)** ou problema AWS | Escalar para o time da plataforma / AWS support |
| Bug de aplicação confirmado nos logs | Escalar para **@chronos-core** (SLA: 15 min horário comercial / 30 min fora) |
| Problema de infra EKS (nodes, networking) | Escalar para time de plataforma/infraestrutura |
| Incidente com impacto em usuários em produção | Abrir bridge de incidente + notificar gestão |

**Template de escalação para o Slack:**

```
@chronos-core 🚨 Escalação Chronos API — <RESUMO DO PROBLEMA>

• Alerta: <NOME DO ALERTA>
• Início: <TIMESTAMP>
• Impacto: <DESCRIÇÃO DO IMPACTO>
• Diagnóstico inicial: <O QUE FOI VERIFICADO>
• Logs relevantes: <LINK BEACON OU TRECHO>
• Métricas: <LINK GRAFANA>
• Ações já tomadas: <LISTA>
```

---

## 5. Aplicar Correções

### 5.1 Pods em CrashLoopBackOff

```bash
# 1. Obter logs do container que crashou
kubectl logs -n production <POD_NAME> --previous --timestamps

# 2. Descrever o pod para ver eventos e exit codes
kubectl describe pod -n production <POD_NAME>

# 3. Se for problema de configuração (env, secrets, configmap)
kubectl get configmap -n production chronos-api-config -o yaml
kubectl get secret -n production chronos-api-secret -o yaml | base64 -d  # com cautela

# 4. Forçar rollout (recriar pods com a mesma versão)
kubectl rollout restart deployment/chronos-api -n production

# 5. Acompanhar o rollout
kubectl rollout status deployment/chronos-api -n production
```

### 5.2 Rollback via Argo CD (deploy problemático)

```bash
# 1. Listar histórico de deploys
argocd app history chronos-api

# 2. Reverter para revisão anterior (substituir <ID> pelo número desejado)
argocd app rollback chronos-api <REVISION_ID>

# 3. Confirmar que o rollback foi aplicado
argocd app get chronos-api
kubectl rollout status deployment/chronos-api -n production
```

### 5.3 Falha de conexão com Ledger (PostgreSQL)

```bash
# Verificar se o Service do Ledger está resolvendo
kubectl exec -n production <CHRONOS_POD> -- nslookup ledger-service

# Verificar endpoints do service
kubectl get endpoints -n production ledger-service

# Se o Ledger estiver com pods com problema
kubectl get pods -n production -l app=ledger
kubectl describe pod -n production <LEDGER_POD>

# Opção temporária: reiniciar pods do Chronos para limpar pool de conexões
kubectl rollout restart deployment/chronos-api -n production
```

### 5.4 Falha no Reactor (SQS)

```bash
# Verificar permissões IAM do Service Account do Chronos
kubectl get serviceaccount -n production chronos-api -o yaml

# Verificar se a IAM Role associada tem permissões na fila
aws iam get-role-policy --role-name <ROLE_NAME> --policy-name <POLICY_NAME>

# Verificar DLQ (Dead Letter Queue) — mensagens com falha
aws sqs get-queue-attributes \
  --queue-url <DLQ_URL> \
  --attribute-names ApproximateNumberOfMessages

# Reprocessar mensagens da DLQ (se necessário e seguro)
aws sqs start-message-move-task \
  --source-arn <DLQ_ARN> \
  --destination-arn <MAIN_QUEUE_ARN>
```

### 5.5 Alta utilização de CPU / HPA no limite

```bash
# Verificar uso atual de CPU/memória por pod
kubectl top pods -n production -l app=chronos-api

# Verificar nodes do cluster
kubectl top nodes

# Aumentar temporariamente o limite máximo do HPA (se necessário)
kubectl patch hpa chronos-api -n production \
  --type merge \
  -p '{"spec":{"maxReplicas": 16}}'

# Verificar se há memory leak — monitorar por alguns minutos
watch -n 10 kubectl top pods -n production -l app=chronos-api

# Forçar recriação dos pods para liberar memória (temporário)
kubectl rollout restart deployment/chronos-api -n production
```

### 5.6 Escalonamento manual de réplicas (emergência)

```bash
# Aumentar réplicas manualmente (bypassa o HPA temporariamente)
kubectl scale deployment/chronos-api -n production --replicas=10

# IMPORTANTE: Restaurar o controle ao HPA após estabilização
# O HPA voltará a gerenciar as réplicas automaticamente
# Para forçar reset:
kubectl patch hpa chronos-api -n production \
  --type merge \
  -p '{"spec":{"minReplicas": 4, "maxReplicas": 12}}'
```

---

### 5.1 Avaliar Encerramento do Caso

Antes de encerrar o caso, confirme **todos** os itens abaixo:

#### Checklist de encerramento

- [ ] **Aplicação estável:** Pods em `Running` sem reinicializações recentes
  ```bash
  kubectl get pods -n production -l app=chronos-api
  ```

- [ ] **HPA normalizado:** Réplicas voltando ao range operacional (4–12)
  ```bash
  kubectl get hpa -n production chronos-api
  ```

- [ ] **Métricas saudáveis:** Error rate < 1%, latência dentro do SLO, CPU < 70%
  ```promql
  sum(rate(http_requests_total{app="chronos-api", status=~"5.."}[5m])) /
  sum(rate(http_requests_total{app="chronos-api"}[5m]))
  ```

- [ ] **Logs limpos:** Sem novos erros críticos no Beacon nos últimos 15 minutos

- [ ] **Dependências OK:** Ledger e Reactor respondendo normalmente

- [ ] **Rollout completo:** Se houve reinício ou rollback, confirmar com:
  ```bash
  kubectl rollout status deployment/chronos-api -n production
  ```

- [ ] **Alterações manuais revertidas:** HPA, replicas e quaisquer patches temporários devem estar nos valores originais

#### Post-mortem e registro

Após encerrar o caso:

1. **Registrar no canal** `#oncall-chronos`:
   ```
   ✅ Caso encerrado — Chronos API
   • Duração: <INICIO> → <FIM>
   • Causa raiz: <DESCRIÇÃO>
   • Correção aplicada: <AÇÃO>
   • Próximos passos: <MELHORIAS / TICKETS>
   ```

2. **Criar ticket de follow-up** para:
   - Ajuste de alertas se houve falso positivo
   - Melhoria de resiliência (retry, circuit breaker, timeout)
   - Revisão de limites de recursos (requests/limits dos pods)
   - Documentação de nova causa raiz identificada

3. **Atualizar este runbook** se um novo cenário foi identificado.

---

## Referência Rápida — Comandos Essenciais

```bash
# Saúde geral
kubectl get pods -n production -l app=chronos-api
kubectl get hpa -n production chronos-api
kubectl top pods -n production -l app=chronos-api

# Logs rápidos
kubectl logs -n production -l app=chronos-api --all-containers --prefix -f --since=30m

# Eventos
kubectl get events -n production --sort-by='.lastTimestamp' | grep chronos | tail -20

# Rollout restart
kubectl rollout restart deployment/chronos-api -n production
kubectl rollout status deployment/chronos-api -n production

# Argo CD
argocd app get chronos-api
argocd app rollback chronos-api <REVISION_ID>
```

---

*Última atualização: 2026-06 | Time: @chronos-core | Canal: #oncall-chronos*