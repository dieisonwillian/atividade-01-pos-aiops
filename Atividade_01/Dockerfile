# =============================================================================
# Stage 1 — Builder
# Instala dependências em ambiente isolado para manter a imagem final enxuta
# =============================================================================
FROM python:3.12-slim AS builder

# Evita arquivos .pyc e habilita logs não-bufferizados (essencial em containers)
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /build

# Copia apenas o manifesto de dependências primeiro (cache eficiente de layers)
COPY requirements.txt .

# Instala dependências no diretório /install para copiar depois
RUN pip install --upgrade pip \
 && pip install --prefix=/install -r requirements.txt


# =============================================================================
# Stage 2 — Runtime
# Imagem final mínima: sem ferramentas de build, menor superfície de ataque
# =============================================================================
FROM python:3.12-slim AS runtime

# Variáveis de ambiente seguras para produção
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH="/app" \
    # DATABASE_URL e API_KEY NÃO são definidas aqui.
    # Devem ser injetadas pelo Kubernetes via:
    #   - secretKeyRef  (recomendado para credenciais)
    #   - configMapKeyRef (para configs não-sensíveis)
    # Exemplo de Secret manifest no README abaixo.
    PORT=8000 \
    WORKERS=2 \
    THREADS=4 \
    TIMEOUT=120

# Instala apenas libs de sistema necessárias para psycopg2-binary em runtime
# (libpq é necessária para conexão com PostgreSQL)
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libpq5 \
      curl \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Cria usuário não-root dedicado (princípio do menor privilégio)
RUN groupadd --gid 1001 appgroup \
 && useradd --uid 1001 --gid appgroup --shell /bin/bash --create-home appuser

WORKDIR /app

# Copia dependências instaladas no stage builder
COPY --from=builder /install /usr/local

# Copia código da aplicação
COPY --chown=appuser:appgroup app.py       ./app.py
COPY --chown=appuser:appgroup requirements.txt ./requirements.txt
COPY --chown=appuser:appgroup lib/         ./lib/

# Troca para usuário sem privilégios antes de qualquer execução
USER appuser

# Healthcheck: Kubernetes também usa liveness/readiness probes,
# mas este garante comportamento correto em docker run / docker-compose
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD curl -f http://localhost:${PORT}/health || exit 1

# Expõe a porta de aplicação (documentação — não publica automaticamente)
EXPOSE ${PORT}

# =============================================================================
# Entrypoint — Gunicorn em modo produção
#
# Flags relevantes:
#   --bind            : escuta em todas as interfaces na porta configurada
#   --workers         : processos paralelos (recomendado: 2*CPU+1)
#   --threads         : threads por worker (útil para I/O-bound)
#   --timeout         : mata workers travados após N segundos
#   --access-logfile  : loga no stdout para captura pelo kubelet
#   --error-logfile   : idem para stderr
#   --log-level       : ajuste para 'debug' em desenvolvimento
# =============================================================================
CMD ["sh", "-c", \
     "gunicorn app:app \
        --bind 0.0.0.0:${PORT} \
        --workers ${WORKERS} \
        --threads ${THREADS} \
        --timeout ${TIMEOUT} \
        --access-logfile - \
        --error-logfile - \
        --log-level info \
        --forwarded-allow-ips='*'"]
