## Questão 05 - Modernizar deployment legado
Numa revisão de produção, Doc Brown puxou o manifest do Chronos e caiu neste deployment que o George escreveu três anos atrás. Desde então ninguém mexeu nele, e muita coisa que hoje é obrigatória no padrão da empresa ainda não está presente. Modernizar caiu na sua mesa.

apiVersion: apps/v1
kind: Deployment
metadata:
  name: chronos-api
  namespace: production
spec:
  replicas: 1
  selector:
    matchLabels:
      app: chronos-api
  template:
    metadata:
      labels:
        app: chronos-api
    spec:
      containers:
      - name: api
        image: chronos-api:latest
        ports:
        - containerPort: 8080
        env:
        - name: DB_PASSWORD
          value: "P@ssw0rd2023!"
        - name: JWT_SECRET
          value: "hvt-jwt-prod-secret"
A versão moderna precisa ter alta disponibilidade, imagem versionada (nada de latest), secrets fora do manifest, resource requests e limits, liveness e readiness probes, securityContext não-root e as demais práticas de produção que hoje são padrão na empresa.

Tarefa. Aplicando o framework B-A-B, escrever o prompt de IA que, recebendo esse manifest, produza a versão modernizada.

Entregue. Prompt, modelo, output e justificativa mostrando como Before, After e Bridge aparecem no prompt.

## Justificativa

Iniciei com o Before passando o  manifesto antigo, como não tenho um modelo atual, descrevi o que queria como o novo no After e no Bridge passei o que queria executar em etapas.

## Modelo

Haiku 4.5

## Prompt

Manifesto kubernetes da aplicação Chornos
apiVersion: apps/v1
kind: Deployment
metadata:
  name: chronos-api
  namespace: production
spec:
  replicas: 1
  selector:
    matchLabels:
      app: chronos-api
  template:
    metadata:
      labels:
        app: chronos-api
    spec:
      containers:
      - name: api
        image: chronos-api:latest
        ports:
        - containerPort: 8080
        env:
        - name: DB_PASSWORD
          value: "P@ssw0rd2023!"
        - name: JWT_SECRET
          value: "hvt-jwt-prod-secret"


Monte um manifesto novo com base em todas as boas práticas de infraestrutura e segurança

Avalie os pontos de criticos, busque na sua base as boas práticas e me gere um novo arquivo validados e comentado.



## Saida do Prompt (Chat)

Vou analisar o manifesto atual, identificar os pontos críticos de segurança e infraestrutura, e gerar uma versão melhorada com boas práticas.Perfeito! Vou criar um manifesto Kubernetes melhorado com todas as boas práticas de segurança e infraestrutura. Deixa eu documentar os **pontos críticos encontrados** e depois gero o arquivo corrigido:

## 🔴 Problemas Críticos Identificados:

1. **Credenciais em Plaintext** - Senha e JWT secret expostos no manifesto
2. **Imagem com tag `latest`** - Sem versionamento específico
3. **Sem limites de recursos** - CPU/Memory unbounded
4. **Health checks ausentes** - Sem liveness/readiness probes
5. **Sem estratégia de update** - Deployment pode ficar indisponível
6. **Sem security context** - Container rodando como root
7. **Sem network policies** - Acesso irrestrito
8. **Sem RBAC** - Service account não configurado
9. **Sem requests/limits** - Risco de resource starvation
10. **Sem configuração de logs** - Sem observabilidade

Agora vou criar o manifesto completo e validado:Agora vou criar um documento complementar com a análise detalhada e guia de implementação:Agora vou criar um arquivo adicional com exemplos práticos de ferramentas de segurança complementares:Perfeito! Agora vou apresentar os arquivos criados:---

## 📊 RESUMO DOS ARQUIVOS CRIADOS

### 🎯 **1. chronos-deployment-best-practices.yaml**
Manifesto Kubernetes **production-ready** com:
- ✅ **Namespace** isolado para produção
- ✅ **Secrets** via Kubernetes (pronto para Sealed Secrets)
- ✅ **ConfigMap** para configurações não-sensíveis
- ✅ **RBAC** (ServiceAccount, Role, RoleBinding)
- ✅ **Network Policies** (isolamento de rede)
- ✅ **Deployment** com segurança completa
- ✅ **3+ replicas** para HA
- ✅ **Rolling Update** com zero downtime
- ✅ **Health Checks** (liveness, readiness, startup)
- ✅ **Resource Requests/Limits**
- ✅ **Security Context** (non-root, read-only FS)
- ✅ **Service** ClusterIP
- ✅ **HorizontalPodAutoscaler** (escala 3-10 pods)
- ✅ **PodDisruptionBudget** (disponibilidade durante manutenção)
- ✅ **Ingress** com TLS e rate limiting
- ✅ **ResourceQuota** para controle de recursos

---

### 📖 **2. ANALISE-E-GUIA-IMPLEMENTACAO.md**
Análise detalhada com:
- 🔴 **10 Problemas Críticos** identificados no manifesto original
- 📋 **Explicação** de cada risco
- ✅ **Solução** implementada para cada problema
- 🚀 **Guia passo-a-passo** para implementação
- 🔧 **Troubleshooting** para problemas comuns
- 📊 **Comparativa** Antes x Depois
- ✅ **Checklist** pré-produção
- 📚 **Leitura recomendada**

---

### 🛡️ **3. FERRAMENTAS-COMPLEMENTARES-SEGURANCA.md**
Ferramentas avançadas incluindo:
- 🔐 **Sealed Secrets** - gerenciamento seguro de credenciais
- 🔍 **Falco** - monitoramento de segurança em runtime
- ✅ **Kube-Bench** - validação de CIS Benchmarks
- 🎯 **Kube-Hunter** - teste de penetração
- 📊 **Polaris** - validação de segurança de pods
- 🐳 **Trivy** - scanning de vulnerabilidades
- ✍️ **Cosign** - assinatura de imagens
- 🚨 **Kyverno** - políticas de admissão dinâmicas
- 📈 **Prometheus + Alertmanager** - monitoramento e alertas
- 🏗️ **Terraform/Helm** - Infrastructure as Code

---

## 🎯 PRÓXIMOS PASSOS RECOMENDADOS

1. **Imediato** (Hoje):
   - ✅ Revisar o manifesto com seu time
   - ✅ Criar secrets com valores reais
   - ✅ Implementar Sealed Secrets

2. **Curto Prazo** (Esta semana):
   - ✅ Aplicar manifesto em staging
   - ✅ Executar testes de carga
   - ✅ Validar health checks
   - ✅ Implementar Falco

3. **Médio Prazo** (Este mês):
   - ✅ Implementar monitoring (Prometheus)
   - ✅ Configurar alertas
   - ✅ Testes de failover
   - ✅ Kyverno policies

4. **Longo Prazo** (Este trimestre):
   - ✅ Implementar GitOps (ArgoCD)
   - ✅ Service Mesh (Istio)
   - ✅ Disaster Recovery plan
   - ✅ Automação completa de CI/CD

---

## 🔒 SEGURANÇA: DESTAQUES PRINCIPAIS

| Camada | Implementação | Benefício |
|--------|---------------|-----------|
| **Rede** | Network Policies | Isolamento de tráfego |
| **Pod** | Security Context | Sem privilégios desnecessários |
| **Identidade** | RBAC + ServiceAccount | Least privilege |
| **Secrets** | Kubernetes Secrets | Credenciais fora do manifesto |
| **Imagem** | Versioning específico | Rastreabilidade |
| **Runtime** | Health checks + Auto-restart | Resiliência |
| **Recursos** | Requests/Limits | Prevenção de starvation |
| **Escalabilidade** | HPA | Disponibilidade sob carga |

---

Todos os arquivos estão prontos em `/mnt/user-data/outputs/` para download! 🚀

## Resultados

Três aquivos, um novo deployment, arquivo de implementação e um arquivo adicionar de segurança