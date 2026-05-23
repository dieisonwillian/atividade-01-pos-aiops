# FERRAMENTAS COMPLEMENTARES DE SEGURANÇA PARA KUBERNETES
## Implementação de Defense in Depth

---

## 1. SEALED SECRETS - Gerenciamento Seguro de Credenciais

### Problema: Secrets em plaintext no Git
```yaml
# ❌ INSEGURO - Nunca faça isso!
apiVersion: v1
kind: Secret
metadata:
  name: chronos-api-secrets
type: Opaque
data:
  db-password: UGFzc3cwcmQyMDIzIQ==  # Base64 é encoding, NÃO criptografia!
```

### Solução: Sealed Secrets
```bash
# 1. Instalar Sealed Secrets
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

# 2. Criar um secret normal
kubectl create secret generic chronos-api-secrets \
  --from-literal=db-password='P@ssw0rd2023!' \
  --from-literal=jwt-secret='hvt-jwt-prod-secret' \
  -n chronos-production \
  --dry-run=client -o yaml > secret.yaml

# 3. Selar o secret
kubeseal -f secret.yaml -w sealed-secret.yaml

# 4. Aplicar o secret selado (seguro no Git!)
kubectl apply -f sealed-secret.yaml

# 5. Verificar
kubectl get sealedsecrets -n chronos-production
kubectl get secrets -n chronos-production
```

### Sealed Secret no Manifesto
```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: chronos-api-secrets
  namespace: chronos-production
spec:
  encryptedData:
    db-password: AgCvK3x8F...  # Criptografado pelo Sealed Secrets
    jwt-secret: AgBk2M9wP...
  template:
    metadata:
      name: chronos-api-secrets
      namespace: chronos-production
    type: Opaque
```

### Rotinas Operacionais
```bash
# Rotar chaves quando mudam
kubectl create secret generic chronos-api-secrets \
  --from-literal=db-password='nova-senha' \
  -n chronos-production \
  --dry-run=client -o yaml | kubeseal -f - | kubectl apply -f -

# Backup da chave mestre (⚠️ CRÍTICO)
kubectl get secret \
  -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  -o yaml > sealed-secrets-backup.yaml

# Restaurar em novo cluster
kubectl apply -f sealed-secrets-backup.yaml
```

---

## 2. FALCO - Monitoramento de Segurança em Runtime

### Instalação
```bash
# Adicionar repositório Helm
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update

# Instalar Falco
helm install falco falcosecurity/falco \
  --namespace falco --create-namespace \
  -f falco-values.yaml
```

### Configuração: falco-values.yaml
```yaml
# Valores personalizados para Falco
falco:
  # Habilitar módulo do kernel (mais performático)
  ebpf:
    enabled: true
  
  # Regras customizadas
  rules:
    - /etc/falco/rules.d/

  # Alerts para atividades suspeitas
  alerts:
    - log
    - stdout

  # Configuração de logging
  json_output: true
  log_level: info

# Output para SIEM/ELK
falcoctl:
  artifact:
    install:
      enabled: true
      rulesdir: /etc/falco/rules.d/
    follow:
      enabled: true
```

### Regras Customizadas: chronos-rules.yaml
```yaml
- rule: Unauthorized Process Execution
  desc: Detectar execução de processos não autorizados
  condition: >
    spawned_process and container
    and container.name = "api"
    and process.name not in (node, npm)
  output: >
    Unauthorized process execution detected
    (user=%user.name command=%proc.cmdline container=%container.name)
  priority: WARNING

- rule: Suspicious Network Connection
  desc: Detectar conexões de rede suspeitas
  condition: >
    outbound and container
    and container.name = "api"
    and not fd.sip in (mongodb_servers)
    and not fd.sport = 443
  output: >
    Suspicious network connection
    (src=%fd.sip dst=%fd.dip port=%fd.dport container=%container.name)
  priority: WARNING

- rule: File System Modification Attempted
  desc: Detectar modificação do filesystem
  condition: >
    write and container
    and container.name = "api"
    and fd.name glob /etc/*
  output: >
    File system modification attempt
    (file=%fd.name user=%user.name container=%container.name)
  priority: CRITICAL

- rule: Privilege Escalation Attempt
  desc: Detectar tentativa de escalação de privilégio
  condition: >
    syscall in (setuid, setgid, setreuid, setregid)
    and container
  output: >
    Privilege escalation attempt detected
    (syscall=%syscall.name user=%user.name container=%container.name)
  priority: CRITICAL
```

### Monitorar Alertas
```bash
# Ver logs do Falco
kubectl logs -f -n falco -l app=falco

# Filtrar por severidade crítica
kubectl logs -f -n falco -l app=falco | grep CRITICAL

# Dashboard Grafana
# Configurar datasource Prometheus + alertas Falco
```

---

## 3. KUBE-BENCH - Validação de CIS Kubernetes Benchmarks

### Executar Validação
```bash
# Instalar via Helm
helm repo add aquasecurity https://aquasecurity.github.io/helm-charts/
helm install kube-bench aquasecurity/kube-bench \
  --namespace kube-bench --create-namespace

# Ou rodar direto
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job-gke.yaml

# Ver resultados
kubectl logs -f -l app=kube-bench
```

### Interpretar Resultados
```
[PASS]   1.1.1 Ensure API server anonymous-auth is disabled
[FAIL]   1.2.1 Ensure that insecure-bind-address is not set
[WARN]   1.2.5 Ensure that the kubelet kubeconfig is set up correctly
```

### Remediar Falhas
```bash
# Para cada FAIL, atualizar kubeadm config
sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml

# Adicionar flags de segurança:
- --anonymous-auth=false
- --insecure-bind-address=
- --insecure-port=0
- --basic-auth-file=
```

---

## 4. KUBE-HUNTER - Teste de Penetração Kubernetes

### Executar Teste
```bash
# Job de scanning
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: kube-hunter
  namespace: default
spec:
  template:
    spec:
      containers:
      - name: kube-hunter
        image: aquasec/kube-hunter:latest
        args:
          - --pod
          - --report=json
        securityContext:
          privileged: true
      restartPolicy: Never
  backoffLimit: 0
EOF

# Ver resultados
kubectl logs -f job/kube-hunter
```

### Vulnerabilidades Comuns Detectadas
- Kubelet não autenticado
- Informações de credenciais em logs
- ServiceAccount tokens acessíveis
- Container escape possível
- Privileged containers

---

## 5. POLARIS - Validação de Segurança de Pods

### Instalar
```bash
# Helm chart
helm repo add fairwinds-stable https://charts.fairwinds.com/stable
helm install polaris fairwinds-stable/polaris \
  --namespace polaris --create-namespace

# Acessar dashboard
kubectl port-forward -n polaris svc/polaris-dashboard 8080:80
# Abrir: http://localhost:8080
```

### Checklist de Validação
```yaml
# Polaris verifica:
- ✅ Security Context (runAsNonRoot, readOnlyFS)
- ✅ Resource Requests/Limits
- ✅ Health Checks (liveness, readiness)
- ✅ Image vulnerabilities
- ✅ Network Policies
- ✅ RBAC configuration
- ✅ Pod Disruption Budgets
- ✅ Image pull policy
```

### Gerar Relatório
```bash
# CLI scanning
polaris audit --namespace chronos-production --format json > polaris-report.json

# Score esperado em produção: >80%
```

---

## 6. TRIVY - Scanning de Vulnerabilidades em Imagens

### Scan Local
```bash
# Instalar Trivy
brew install aquasecurity/trivy/trivy  # macOS
apt-get install trivy                   # Linux

# Scanear imagem
trivy image chronos-api:v1.2.3

# Gerar relatório HTML
trivy image chronos-api:v1.2.3 \
  --format template \
  --template '@contrib/html.tpl' \
  -o trivy-report.html
```

### Integração no CI/CD
```yaml
# GitHub Actions
- name: Run Trivy vulnerability scanner
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: ${{ env.REGISTRY }}/chronos-api:${{ github.sha }}
    format: 'sarif'
    output: 'trivy-results.sarif'
    severity: 'CRITICAL,HIGH'
    exit-code: '1'

- name: Upload Trivy results to GitHub Security
  uses: github/codeql-action/upload-sarif@v2
  if: always()
  with:
    sarif_file: 'trivy-results.sarif'
```

### Políticas de Scan
```bash
# Bloquear deploy se vulnerabilidades críticas encontradas
trivy image --severity CRITICAL \
  --exit-code 1 \
  chronos-api:v1.2.3
```

---

## 7. CONTAINER IMAGE SIGNING - Assinatura de Imagens

### Setup com Notary/Cosign
```bash
# Instalar Cosign
wget https://github.com/sigstore/cosign/releases/download/v2.0.0/cosign-linux-amd64
chmod +x cosign-linux-amd64

# Gerar chave de assinatura
./cosign-linux-amd64 generate-key-pair

# Assinar imagem
./cosign-linux-amd64 sign \
  --key cosign.key \
  registry.example.com/chronos-api:v1.2.3

# Verificar assinatura
./cosign-linux-amd64 verify \
  --key cosign.pub \
  registry.example.com/chronos-api:v1.2.3
```

### Enforce Signed Images
```yaml
# ClusterImagePolicy (K8s 1.26+)
apiVersion: images.kyverno.io/v1alpha1
kind: ClusterImagePolicy
metadata:
  name: chronos-signed-images
spec:
  images:
    - glob: "registry.example.com/chronos-api:*"
  attestations:
    - name: check-signature
      attestations:
        - predicateType: cosign.sigstore.dev/attestation/v1
```

---

## 8. KYVERNO - Políticas de Admissão Dinâmicas

### Instalação
```bash
# Helm
helm repo add kyverno https://kyverno.github.io/kyverno/
helm install kyverno kyverno/kyverno \
  --namespace kyverno --create-namespace
```

### Políticas de Segurança
```yaml
# 1. Forçar Security Context
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-security-context
spec:
  validationFailureAction: enforce
  rules:
    - name: validate-security-context
      match:
        resources:
          kinds:
            - Pod
      validate:
        message: "Security context must be defined"
        pattern:
          spec:
            securityContext:
              runAsNonRoot: true
            containers:
              - name: ?*
                securityContext:
                  allowPrivilegeEscalation: false

# 2. Bloquear imagens non-signed
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-signed-images
spec:
  validationFailureAction: enforce
  rules:
    - name: verify-image-signature
      match:
        resources:
          kinds:
            - Pod
      verifyImages:
        - imageReferences:
            - "registry.example.com/*"
          attestations:
            - name: check-signature
              predicateType: cosign.sigstore.dev/attestation/v1

# 3. Forçar Resource Limits
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-resource-limits
spec:
  validationFailureAction: enforce
  rules:
    - name: validate-resources
      match:
        resources:
          kinds:
            - Pod
      validate:
        message: "CPU and memory limits are required"
        pattern:
          spec:
            containers:
              - name: ?*
                resources:
                  limits:
                    memory: "?*"
                    cpu: "?*"
                  requests:
                    memory: "?*"
                    cpu: "?*"

# 4. Forçar Network Policies
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-network-policy
spec:
  validationFailureAction: audit
  rules:
    - name: require-netpol-label
      match:
        resources:
          kinds:
            - Pod
          selector:
            matchLabels:
              require-network-policy: "true"
      validate:
        message: "Network policy must be configured"
        pattern:
          metadata:
            labels:
              network-policy: "?*"
```

---

## 9. PROMETHEUS + ALERTMANAGER - Monitoramento e Alertas

### Instalar Stack
```bash
# Helm Kube-Prometheus-Stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f prometheus-values.yaml
```

### Alertas de Segurança
```yaml
# prometheus-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: kubernetes-security-alerts
  namespace: monitoring
spec:
  groups:
    - name: kubernetes.security
      interval: 30s
      rules:
        # Alert 1: Pod com privilégios executando
        - alert: PrivilegedPodDetected
          expr: |
            kube_pod_security_context_privileged{container="api"} == 1
          for: 5m
          labels:
            severity: CRITICAL
          annotations:
            summary: "Privileged pod detected: {{ $labels.pod }}"
            description: "Pod {{ $labels.pod }} is running in privileged mode"

        # Alert 2: Security Context não configurado
        - alert: NoSecurityContextConfigured
          expr: |
            kube_pod_security_context_run_as_non_root{container="api"} == 0
          for: 5m
          labels:
            severity: HIGH
          annotations:
            summary: "Pod running as root: {{ $labels.pod }}"

        # Alert 3: Network Policy ausente
        - alert: NoNetworkPolicyFound
          expr: |
            count(kube_networkpolicy{namespace="chronos-production"}) == 0
          for: 5m
          labels:
            severity: HIGH
          annotations:
            summary: "No network policies found in chronos-production"

        # Alert 4: Health check falhando
        - alert: PodHealthCheckFailing
          expr: |
            up{job="chronos-api", namespace="chronos-production"} == 0
          for: 2m
          labels:
            severity: CRITICAL
          annotations:
            summary: "Pod health check failing: {{ $labels.pod }}"

        # Alert 5: Alto uso de memória
        - alert: HighMemoryUsage
          expr: |
            (container_memory_usage_bytes{pod="chronos-api"} / 
            container_spec_memory_limit_bytes{pod="chronos-api"}) > 0.9
          for: 5m
          labels:
            severity: WARNING
          annotations:
            summary: "High memory usage: {{ $labels.pod }}"
            value: "{{ $value | humanizePercentage }}"
```

### Alertmanager Config
```yaml
# alertmanager-config.yaml
global:
  resolve_timeout: 5m

route:
  receiver: 'chronos-devops'
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  routes:
    # Security alerts - notificar imediatamente
    - match:
        severity: CRITICAL
      receiver: 'chronos-security-team'
      group_wait: 1s
      repeat_interval: 1h

    # High priority alerts
    - match:
        severity: HIGH
      receiver: 'chronos-devops'
      repeat_interval: 4h

receivers:
  - name: 'chronos-devops'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'
        channel: '#devops-alerts'
        title: 'Chronos Alert'
        text: '{{ range .Alerts }}{{ .Annotations.summary }}\n{{ end }}'

  - name: 'chronos-security-team'
    pagerduty_configs:
      - service_key: 'YOUR-PAGERDUTY-KEY'
        description: '{{ .GroupLabels.alertname }}'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'
        channel: '#security-team'
        title: '🚨 SECURITY ALERT'
        text: '{{ range .Alerts }}CRITICAL: {{ .Annotations.summary }}\n{{ end }}'
    email_configs:
      - to: 'security@example.com'
        smarthost: 'smtp.example.com:587'
        from: 'alerts@example.com'
```

---

## 10. TERRAFORM/HELM - Infrastructure as Code

### Estrutura de Projeto
```
chronos-k8s-infrastructure/
├── terraform/
│   ├── main.tf              # EKS cluster
│   ├── security.tf          # RBAC, network policies
│   ├── monitoring.tf        # Prometheus, Falco
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars
├── helm/
│   ├── chronos-api/
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   ├── templates/
│   │   │   ├── deployment.yaml
│   │   │   ├── service.yaml
│   │   │   └── ingress.yaml
│   │   └── values-prod.yaml
│   └── kyverno/
│       └── values.yaml
└── scripts/
    ├── deploy.sh
    ├── validate.sh
    └── test.sh
```

### Helm Chart: values-prod.yaml
```yaml
# Valores específicos para produção
replicaCount: 3

image:
  repository: registry.example.com/chronos-api
  tag: v1.2.3
  pullPolicy: IfNotPresent

resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 2000m
    memory: 2Gi

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80

securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 2000

podSecurityPolicy:
  enabled: true

networkPolicy:
  enabled: true
  
monitoring:
  enabled: true
  prometheus:
    enabled: true
```

---

## 📋 CHECKLIST DE IMPLEMENTAÇÃO

- [ ] Sealed Secrets instalado e configurado
- [ ] Falco rodando em todos os nodes
- [ ] Kube-bench passou em >90% dos testes
- [ ] Kube-hunter não encontrou vulnerabilidades críticas
- [ ] Polaris score >80%
- [ ] Trivy scan passando (sem CVEs críticas)
- [ ] Imagens assinadas com Cosign
- [ ] Kyverno policies aplicadas
- [ ] Prometheus + Alertmanager rodando
- [ ] Alertas configurados e testados
- [ ] Terraform/Helm em Git (sem secrets!)
- [ ] CI/CD pipeline com security gates

---

## 📚 RECURSOS ADICIONAIS

- [CNCF Cloud Native Security Whitepaper](https://www.cncf.io/blog/2021/12/01/container-security-at-cncf/)
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/)
- [CIS Kubernetes Benchmarks](https://www.cisecurity.org/benchmark/kubernetes)
- [OWASP Top 10 Cloud Native](https://owasp.org/www-project-top-10-cloud-native/)

---

**Versão:** 1.0.0  
**Data:** 2024-05-21
