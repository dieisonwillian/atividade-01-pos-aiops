# Runbook — Chronos API
**Namespace:** `production` | **Cluster:** EKS | **Canal de plantão:** `#oncall-chronos`

---

## Pré-requisitos

| Ferramenta | Versão mínima | Finalidade |
|---|---|---|
| `kubectl` | 1.28+ | Gerenciamento do cluster |
| `aws cli` | 2.x | Acesso a recursos AWS (SQS, CloudWatch) |
| `argocd cli` | 2.x | Verificação de estado do deploy |

Confirme acesso antes de iniciar qualquer intervenção:

```bash
kubectl auth can-i get pods -n production
argocd app list
aws sts get-caller-identity
```

---

## 1. Verificar o Alerta

### 1.1 Identificar a origem

Verifique o alerta no Grafana ou no canal `#oncall-chronos`:

- **Grafana:** Dashboard `Chronos API` → painel `Error Rate / Latency / Pod Health`
- **Beacon (logs centralizados):** filtre por `service=chronos-api` e `level=error`

### 1.2 Categorias de alerta mais comuns

| Alerta | Possível causa | Prioridade |
|---|---|---|
| `HighErrorRate5xx` | Falha na aplicação / dependência | P1 |
| `PodCrashLooping` | OOM, misconfiguration, startup probe | P1 |
| `HPAMaxReplicasReached` | Pico de carga / memory leak | P2 |
| `SQSConsumerLag` | Reactor indisponível ou lento | P2 |
| `PostgresConnectionError` | Ledger inacessível ou pool esgotado | P1 |
| `DeploymentProgressing` | Rollout travado no Argo CD | P2 |

### 1.3 Coletar metadados do alerta

Anote antes de prosseguir:

```
- Nome do alerta:
- Horário de início:
- Labels (pod, node, region):
- Threshold disparado:
```

---

## 2. Acessar o Ambiente Kubernetes

### 2.1 Configurar contexto do cluster EKS

```bash
# Atualizar kubeconfig para o cluster correto
aws eks update-kubeconfig --name <CLUSTER_NAME> --region <AWS_REGION>

# Confirmar contexto ativo
kubectl config current-context
```

### 2.2 Verificar saúde geral do namespace

```bash
# Visão geral dos recursos em production
kubectl get all -n production

# Status dos pods do Chronos
kubectl get pods -n production -l app=chronos-api -o wide

# Estado do Deployment e HPA
kubectl get deployment chronos-api -n production
kubectl get hpa chronos-api -n production
```

### 2.3 Inspecionar eventos recentes

```bash
# Eventos do namespace (últimas ocorrências primeiro)
kubectl get events -n production --sort-by='.lastTimestamp' | grep -i chronos

# Detalhes de um pod específico (substitua <POD_NAME>)
kubectl describe pod <POD_NAME> -n production
```

---

## 3. Listar os Logs do Chronos API

### 3.1 Logs via kubectl (tempo real)

```bash
# Todos os pods do Chronos (label selector)
kubectl logs -n production -l app=chronos-api --tail=200 --prefix

# Pod específico com follow
kubectl logs -n production <POD_NAME> --tail=500 -f

# Pod em CrashLoop — logs do container anterior
kubectl logs -n production <POD_NAME> --previous --tail=300

# Filtrar apenas erros no terminal
kubectl logs -n production -l app=chronos-api --tail=500 | grep -iE "error|exception|fatal|panic"
```

### 3.2 Logs via PromQL / Loki no Grafana

> Use o datasource **Loki** no Grafana ou a CLI do Beacon para as queries abaixo.

**Erros críticos nos últimos 15 minutos:**

```logql
{namespace="production", app="chronos-api"} |= "error" | json | level="error"
```

**Rastrear um trace_id específico:**

```logql
{namespace="production", app="chronos-api"} | json | trace_id="<TRACE_ID>"
```

**Volume de erros por pod (agregado):**

```logql
sum by (pod) (
  count_over_time(
    {namespace="production", app="chronos-api"} |= "error" [5m]
  )
)
```

**Erros de conexão com Ledger (PostgreSQL):**

```logql
{namespace="production", app="chronos-api"} |= "postgres" |~ "connection|timeout|refused"
```

**Erros de conexão com Reactor (SQS):**

```logql
{namespace="production", app="chronos-api"} |= "sqs" |~ "error|timeout|throttl"
```

### 3.3 Métricas via PromQL no Grafana

**Taxa de erros HTTP 5xx:**

```promql
sum(rate(http_requests_total{namespace="production", app="chronos-api", status=~"5.."}[5m]))
/
sum(rate(http_requests_total{namespace="production", app="chronos-api"}[5m]))
```

**Latência p99 por endpoint:**

```promql
histogram_quantile(0.99,
  sum by (le, handler) (
    rate(http_request_duration_seconds_bucket{namespace="production", app="chronos-api"}[5m])
  )
)
```

**Pods em estado não-Ready:**

```promql
kube_pod_status_ready{namespace="production", pod=~"chronos-api.*", condition="true"} == 0
```

**Uso de CPU vs target do HPA:**

```promql
rate(container_cpu_usage_seconds_total{namespace="production", container="chronos-api"}[2m])
```

**Réplicas ativas vs desejadas:**

```promql
kube_deployment_status_replicas_available{namespace="production", deployment="chronos-api"}
```

---

## 4. Avaliar a Causa Raiz

Siga a árvore de decisão abaixo para identificar a categoria do problema:

```
Alerta disparado
│
├── Pods em CrashLoop / Not Ready?
│   ├── SIM → ver seção 4.1 (falha no pod)
│   └── NÃO ↓
│
├── Alta taxa de erro 5xx?
│   ├── SIM → ver seção 4.2 (erro de aplicação)
│   └── NÃO ↓
│
├── Latência elevada?
│   ├── SIM → ver seção 4.3 (degradação de dependência)
│   └── NÃO ↓
│
└── HPA no máximo / deploy travado?
    └── SIM → ver seção 4.4 (capacidade / rollout)
```

### 4.1 Falha no Pod (CrashLoop / OOMKilled)

```bash
# Verificar motivo do restart
kubectl describe pod <POD_NAME> -n production | grep -A 10 "Last State"

# Verificar se é OOMKilled
kubectl get pod <POD_NAME> -n production -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}'

# Verificar resource limits configurados
kubectl get pod <POD_NAME> -n production -o jsonpath='{.spec.containers[0].resources}'
```

**Sinais:**
- `OOMKilled` → memory limit muito baixo ou vazamento de memória
- `Error` / `CreateContainerError` → erro de configuração (secret, configmap, imagem)
- `ImagePullBackOff` → tag de imagem inválida ou credencial ECR expirada

### 4.2 Erro de Aplicação (5xx)

```bash
# Verificar endpoints disponíveis
kubectl get endpoints chronos-api -n production

# Acessar o /metrics diretamente para snapshot
kubectl exec -n production <POD_NAME> -- curl -s http://localhost:<PORT>/metrics | grep http_requests
```

**Sinais nos logs:**
- Stack traces recorrentes em Java/Go/Node → bug na aplicação
- `connection refused` para Ledger → PostgreSQL indisponível
- `timeout` para Reactor → SQS com consumo lento ou throttling

### 4.3 Degradação de Dependência

```bash
# Verificar conectividade com o Ledger (PostgreSQL)
kubectl exec -n production <POD_NAME> -- nc -zv <LEDGER_SERVICE> 5432

# Verificar fila SQS pelo AWS CLI
aws sqs get-queue-attributes \
  --queue-url <QUEUE_URL> \
  --attribute-names ApproximateNumberOfMessages,ApproximateNumberOfMessagesNotVisible

# Verificar se o serviço do Ledger está respondendo no cluster
kubectl get svc -n production | grep ledger
kubectl get endpoints -n production | grep ledger
```

### 4.4 Capacidade / Rollout Travado

```bash
# Status detalhado do HPA
kubectl describe hpa chronos-api -n production

# Estado do rollout no Argo CD
argocd app get chronos-api
argocd app history chronos-api

# Verificar se há rollout travado
kubectl rollout status deployment/chronos-api -n production
```

---

## 5. Aplicar Correções

> ⚠️ **Antes de qualquer ação destrutiva:** registre no canal `#oncall-chronos` o que será feito e por quê.

---

### 5.1 Reiniciar Pods com CrashLoop

```bash
# Reiniciar um pod específico
kubectl delete pod <POD_NAME> -n production

# Rollout restart em todos os pods (rolling, sem downtime)
kubectl rollout restart deployment/chronos-api -n production

# Acompanhar o rollout
kubectl rollout status deployment/chronos-api -n production
```

---

### 5.2 Corrigir OOMKilled — Ajustar Memory Limit

```bash
# Verificar configuração atual de resources
kubectl get deployment chronos-api -n production -o yaml | grep -A 10 resources

# Editar inline (use com cuidado em produção)
kubectl set resources deployment chronos-api \
  -n production \
  --limits=memory=1Gi \
  --requests=memory=512Mi
```

> **Preferível:** atualizar o `values.yaml` no repositório `hvt/chronos-api` e deixar o Argo CD reconciliar.

---

### 5.3 Forçar Rollback via Argo CD

```bash
# Verificar histórico de revisões
argocd app history chronos-api

# Rollback para revisão anterior (ex: ID 42)
argocd app rollback chronos-api 42

# Acompanhar sincronização
argocd app wait chronos-api --health
```

---

### 5.4 Escalar Manualmente as Réplicas (Sobrecarga Temporária)

```bash
# Escalar para além do mínimo do HPA temporariamente
kubectl scale deployment chronos-api -n production --replicas=10

# Verificar distribuição dos pods nos nodes
kubectl get pods -n production -l app=chronos-api -o wide
```

> **Lembre-se:** o HPA vai sobrescrever essa escala manual assim que o ciclo de reconciliação ocorrer. Para escala persistente, ajuste `minReplicas` no manifesto.

---

### 5.5 Corrigir Problema com Dependências (Ledger / Reactor)

**Se o Ledger (PostgreSQL) estiver inacessível:**

```bash
# Verificar se o serviço existe e tem endpoints
kubectl get svc,endpoints -n production | grep ledger

# Verificar secrets de conexão
kubectl get secret -n production | grep ledger
kubectl describe secret <LEDGER_SECRET> -n production
```

**Se o Reactor (SQS) estiver com fila acumulada:**

```bash
# Purge da DLQ (somente se autorizado pelo owner)
aws sqs purge-queue --queue-url <DLQ_URL>

# Verificar consumers ativos
aws sqs get-queue-attributes \
  --queue-url <QUEUE_URL> \
  --attribute-names All
```

---

### 5.6 Forçar Sincronização no Argo CD

Útil quando o deploy está em `OutOfSync` ou `Degraded`:

```bash
# Sincronizar sem prune (mais seguro)
argocd app sync chronos-api

# Sincronizar com prune (remove recursos órfãos)
argocd app sync chronos-api --prune

# Hard refresh (ignora cache do Git)
argocd app sync chronos-api --force
```

---

### 5.7 Corrigir ImagePullBackOff (Credenciais ECR)

```bash
# Verificar erro de pull
kubectl describe pod <POD_NAME> -n production | grep -A 5 "Failed"

# Renovar token ECR manualmente
aws ecr get-login-password --region <AWS_REGION> | \
  kubectl create secret docker-registry ecr-creds \
    --docker-server=<ACCOUNT_ID>.dkr.ecr.<AWS_REGION>.amazonaws.com \
    --docker-username=AWS \
    --docker-password=$(aws ecr get-login-password --region <AWS_REGION>) \
    -n production --dry-run=client -o yaml | kubectl apply -f -
```

---

## Pós-Incidente

Após a estabilização, execute obrigatoriamente:

```bash
# Confirmar que todos os pods estão Running e Ready
kubectl get pods -n production -l app=chronos-api

# Confirmar HPA dentro da faixa esperada
kubectl get hpa chronos-api -n production

# Verificar ausência de novos erros nos logs
kubectl logs -n production -l app=chronos-api --tail=100 | grep -iE "error|exception|fatal"
```

Registre no canal `#oncall-chronos`:

- [ ] Horário de início e fim do incidente
- [ ] Causa raiz identificada
- [ ] Ação aplicada
- [ ] Link para o dashboard Grafana do período
- [ ] Abertura de ticket de follow-up (se necessário)

---

*Runbook mantido pelo time SRE — repositório `hvt/chronos-api` · Última revisão: 2026-05*
