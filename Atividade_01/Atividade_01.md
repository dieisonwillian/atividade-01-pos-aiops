
# Atividade 01

Foi defindo diretamente no prompt as informações importante como estrutura e os dados do requiements pois foi usado no Chat do Claude, quando usando o ClaudeCode seria referenciados o arquivos diretamente no diretório, abaixo as estruturas usadas para ter o resultado e a saida do console, na mesma pasta o arquivo DockerFile e o Manifesto kubernetes gerados pelo Sonnet 4.6.


## Prompt:
```
Role:
SER Senior, Python/Flask, kubernetes, 

Task:
Imput de sistema em Python/flask para Kubernetes, necessário váriaveis DATABASE_URL e API_KEY no runtime.
Estrutura:
lift/
├── app.py
├── requirements.txt
├── lib/
│   ├── auth.py
│   └── storage.py
└── tests/
    └── test_app.py
Dependecias:
Flask==3.0.0
gunicorn==21.2.0
requests==2.31.0
python-dotenv==1.0.0
psycopg2-binary==2.9.9

Format:
Dockerfile
```

## Modelo: Sonnet 4.6

## OutPut:

### Saida do console do chat


Vou criar um Dockerfile production-ready para sua aplicação Flask/Kubernetes com as melhores práticas de segurança e otimização.---

## Decisões de arquitetura

### Dockerfile — Multi-stage build

**Stage `builder`** instala todas as dependências com `pip install --prefix=/install`, isolando os artefatos de build. O `psycopg2-binary` exige compilação, então manter isso separado evita que ferramentas de build entrem na imagem final.

**Stage `runtime`** copia apenas `/install` do builder, resultando em imagem ~60% menor. Inclui só `libpq5` (runtime do PostgreSQL) e `curl` (para o healthcheck).

### Segurança

| Prática | Implementação |
|---|---|
| Usuário não-root | `useradd --uid 1001` + `USER appuser` |
| `securityContext` no pod | `runAsNonRoot: true` no Deployment |
| Segredos fora da imagem | `secretKeyRef` no manifest K8s |
| Superfície mínima | `python:3.12-slim`, sem bash, git, etc. |

### `DATABASE_URL` e `API_KEY` no runtime

As variáveis **não existem no Dockerfile** — isso seria um erro de segurança (ficam gravadas nas layers). O fluxo correto é:

```bash
# 1. Criar o Secret no cluster
kubectl apply -f k8s-manifests.yaml

# 2. Verificar injeção dentro do pod
kubectl exec -it <pod-name> -- env | grep -E "DATABASE_URL|API_KEY"
```

O Kubernetes injeta os valores como variáveis de ambiente em runtime, sem expô-los em `docker inspect`, logs de build ou registros de imagem.

### Gunicorn — configuração para K8s

- `--forwarded-allow-ips='*'` — necessário quando há ingress/proxy na frente
- `--access-logfile -` e `--error-logfile -` — stdout/stderr capturados pelo kubelet (`kubectl logs`)
- `WORKERS` e `THREADS` como env vars — ajustáveis por `ConfigMap` sem rebuild
