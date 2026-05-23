
Questão 08 - Postmortem técnico de incidente em produção
Um incidente está em andamento durante pico de tráfego. Doc Brown entrou na call e precisa de um postmortem técnico em 20 minutos para decidir entre rollback do deploy v2.48.0 (que subiu ontem) e scaling emergencial (aumento de limits do RDS e do pool de conexões). Os artefatos disponíveis para análise são os seguintes.

Evento do deploy anterior (ontem, 18:42 UTC):

Deploy chronos-api: v2.47.0 -> v2.48.0
Argo CD sync: 2026-04-23 18:42:11 UTC
Changelog:
- Adicionado endpoint POST /v2/transactions/batch
- Refatorado cliente do Ledger (pool de conexoes movido para nova biblioteca interna)
- Bump de psycopg 3.1.18 -> 3.2.0
- Reduzido timeout do Ledger de 5s para 2s
Métricas do Beacon nos últimos 30 minutos:

timestamp                p99_latency_ms   req_rate_s   err_rate_pct
2026-04-24 13:30 UTC     420              1200         0.2
2026-04-24 13:45 UTC     510              1450         0.3
2026-04-24 14:00 UTC     780              1780         0.8
2026-04-24 14:10 UTC     2400             2100         4.5
2026-04-24 14:15 UTC     5200             2400         8.2
2026-04-24 14:20 UTC     8100             2650         11.7
Trecho do log do pod chronos-api-79c4d8b9-xk2jp:

2026-04-24 14:19:48 [ERROR] [ledger-client] connection pool exhausted (max=20, active=20, waiting=147)
2026-04-24 14:19:49 [WARN]  [ledger-client] query timeout after 2000ms: SELECT ... FROM transactions WHERE ...
2026-04-24 14:19:49 [ERROR] [handler] POST /v2/transactions/batch failed: context deadline exceeded
2026-04-24 14:19:50 [ERROR] [ledger-client] connection reset by peer
2026-04-24 14:19:51 [WARN]  [circuit-breaker] ledger-client OPEN (threshold 50%, current 87%)
2026-04-24 14:19:52 [ERROR] [reactor] failed to publish message: chronos-api upstream error
Estado do Reactor (fila chronos-transactions):

50.127 mensagens acumuladas, crescendo a ~800/min.
Consumer lag atual: 18 minutos e aumentando.
Estado do cluster:

Chronos: 12/12 pods running (HPA no máximo).
CPU médio dos pods: 62%.
Memória média dos pods: 71%.
Conexões ativas ao Ledger: 240/250 (limite do RDS).
Tarefa. Escolher entre os cinco frameworks do capítulo (R-T-F, T-A-G, B-A-B, C-A-R-E ou R-I-S-E) aquele que se aplica melhor a esse cenário e escrever o prompt de IA que produza o postmortem técnico que o Doc pediu.

Nesta questão a justificativa é o coração da entrega. Além de explicar o framework escolhido e como seus componentes aparecem no prompt, comparar explicitamente com pelo menos 2 outros frameworks candidatos, apontando o que se ganharia e o que se perderia em cada um.

Entregue. Prompt, modelo, output e justificativa estendida com comparação entre frameworks.


## Justificativa
Usei o modelo Gemini 3.1 pro para avaliar o resultado gerado por ele, quando ao escolha do modelo TAG, avaliando todas esse me fez mais sentido pois tenho uma tarefa que é gerar o relatório, uma ação de analise dos logs e um objetivo que é descidir se faz rollback do sistema ou não.

Avalei RTF inicialmente mas acabei mudando pois o quem e o formato são menos importante que a ação e o objetivo
Também pensei em usar o BAB pois eu teria o estado anterios e posterior da atualização, porém precisaria separar os dados e no final acaba que era uma tomada de descição e não a solução do problema.

## Modelo
Gemini 3.1 Pro
## Prompt

Gerar um arquivo de postmortem

Avalie os indicadores abaixo para montar arquivo:

Evento do deploy anterior (ontem, 18:42 UTC):

Deploy chronos-api: v2.47.0 -> v2.48.0
Argo CD sync: 2026-04-23 18:42:11 UTC
Changelog:
- Adicionado endpoint POST /v2/transactions/batch
- Refatorado cliente do Ledger (pool de conexoes movido para nova biblioteca interna)
- Bump de psycopg 3.1.18 -> 3.2.0
- Reduzido timeout do Ledger de 5s para 2s
Métricas do Beacon nos últimos 30 minutos:

timestamp                p99_latency_ms   req_rate_s   err_rate_pct
2026-04-24 13:30 UTC     420              1200         0.2
2026-04-24 13:45 UTC     510              1450         0.3
2026-04-24 14:00 UTC     780              1780         0.8
2026-04-24 14:10 UTC     2400             2100         4.5
2026-04-24 14:15 UTC     5200             2400         8.2
2026-04-24 14:20 UTC     8100             2650         11.7
Trecho do log do pod chronos-api-79c4d8b9-xk2jp:

2026-04-24 14:19:48 [ERROR] [ledger-client] connection pool exhausted (max=20, active=20, waiting=147)
2026-04-24 14:19:49 [WARN]  [ledger-client] query timeout after 2000ms: SELECT ... FROM transactions WHERE ...
2026-04-24 14:19:49 [ERROR] [handler] POST /v2/transactions/batch failed: context deadline exceeded
2026-04-24 14:19:50 [ERROR] [ledger-client] connection reset by peer
2026-04-24 14:19:51 [WARN]  [circuit-breaker] ledger-client OPEN (threshold 50%, current 87%)
2026-04-24 14:19:52 [ERROR] [reactor] failed to publish message: chronos-api upstream error
Estado do Reactor (fila chronos-transactions):

50.127 mensagens acumuladas, crescendo a ~800/min.
Consumer lag atual: 18 minutos e aumentando.
Estado do cluster:

Chronos: 12/12 pods running (HPA no máximo).
CPU médio dos pods: 62%.
Memória média dos pods: 71%.
Conexões ativas ao Ledger: 240/250 (limite do RDS).

Entrege indicadores que tragam a capacidade de gerar a decisão sobre rollback das versão no deply .2.48.0 ou um scaling emergencial da aplicação.


## Saida do Prompt (Chat)

Aqui está o draft do documento de Postmortem, estruturado para fornecer visibilidade clara sobre o incidente e, principalmente, focar nos indicadores que guiam a decisão técnica imediata entre Rollback e Scaling Emergencial.

---

# 📄 Documento de Postmortem: Incidente Chronos-API

## 1. Resumo Executivo

**Status Atual:** Ativo / Crítico (Nível 1)
**Data/Hora do Incidente:** 24 de Abril de 2026, a partir das 14:00 UTC
**Impacto:** Degradação severa na API `chronos-api` (p99 latency de 8.1s, taxa de erro de 11.7%). Acúmulo crítico na fila `chronos-transactions` (50k+ mensagens, lag de 18 min).
**Causa Inicial Suspeita:** Gargalo de I/O com o banco de dados (Ledger) originado por alterações no pool de conexões e redução do timeout introduzidos no deploy da versão `v2.48.0` (ontem, 18:42 UTC).

## 2. Timeline do Incidente (24/04/2026)

* **13:30 UTC:** Tráfego e latência normais (420ms, 1200 req/s).
* **14:00 UTC:** Aumento natural de tráfego detectado (1780 req/s). Latência dobra (780ms).
* **14:10 UTC:** Início da degradação sistêmica. Latência atinge 2.4s e erros disparam para 4.5%.
* **14:15 UTC:** Gargalo severo. Latência em 5.2s.
* **14:19 UTC:** Logs indicam exaustão do pool de conexões do Ledger (`max=20`, `waiting=147`) e interrupção por timeout de 2s, levando à abertura do Circuit Breaker.
* **14:20 UTC:** Erros atingem 11.7%. Fila do Reactor acumula 50k+ mensagens.

---

## 3. Matriz de Decisão Operacional: Rollback vs. Scaling Emergencial

Abaixo estão os indicadores isolados da infraestrutura e aplicação para fundamentar a ação imediata.

### 🔴 Indicadores Críticos (Por que NÃO realizar Scaling Emergencial)

1. **Limite de Conexões do RDS (O Blocker):** * **Estado:** 240/250 conexões ativas.
* **Matemática:** O HPA atual está no máximo (12 pods). Segundo os logs, cada pod possui um pool de 20 conexões (`max=20`). Portanto, 12 pods × 20 conexões = **240 conexões exatas**.
* **Risco de Escalonamento:** Se fizermos um scaling emergencial para 13 ou mais pods, tentaremos abrir mais de 260 conexões. O limite físico do RDS (250) será estourado, causando `Connection Refused` imediatos, podendo derrubar o banco de dados por completo e gerar uma interrupção total (outage).


2. **Uso de Recursos Computacionais:** * **Estado:** CPU a 62% e Memória a 71%.
* **Análise:** A aplicação não está sofrendo de CPU throttling ou OOM (Out Of Memory). O gargalo é exclusivamente de concorrência e dependência externa (I/O). Escalar horizontalmente não resolve problemas de I/O em um banco que já está no limite.



### 🟢 Indicadores de Causa-Raiz (Por que realizar ROLLBACK)

1. **Mudança de Timeout:** O log acusa `query timeout after 2000ms`. O changelog do deploy confirma a alteração de *5s para 2s*. Sob carga (2650 req/s), o banco de dados naturalmente eleva o tempo de resposta; o novo limite de 2s está muito agressivo e matando as requisições antes que o banco consiga processá-las.
2. **Nova Biblioteca de Pool:** A refatoração do cliente do Ledger causou engarrafamento de threads (`active=20, waiting=147`). O pool antigo (v2.47.0) geria melhor o enfileiramento sem gerar `context deadline exceeded`.
3. **Novas Features em Estresse:** O novo endpoint (`POST /v2/transactions/batch`), dependendo de como foi desenhado com o bump do `psycopg`, pode estar retendo conexões por muito tempo, agravando a falta de conexões para outras operações.

---

## 4. Veredito e Plano de Ação Imediata

**Decisão:** **ROLLBACK IMEDIATO** da versão `v2.48.0` para a `v2.47.0`.

**Justificativa Técnica:** O scaling emergencial dos Pods agravará o incidente, causando a queda imediata do banco de dados (estouro do limite de conexões do RDS). O HPA já cumpriu seu papel e escalou até o máximo possível dentro das limitações atuais da infraestrutura. A degradação ocorre por má configuração do client do banco (timeouts muito curtos) e má gestão de concorrência na versão introduzida ontem.

**Passos para Execução:**

1. Via Argo CD (ou pipeline CI/CD), iniciar o Rollback da tag `v2.48.0` para `v2.47.0`.
2. Monitorar o restart das réplicas, assegurando que o limite de conexões do RDS dissipe para o padrão de tráfego anterior.
3. Observar a fila do Reactor (`chronos-transactions`). O lag de 18 min deve começar a reduzir automaticamente assim que a API `v2.47.0` normalizar o throughput de gravação.

## 5. Action Items (Para Pós-Incidente)

* [ ] **Dev/SRE:** Investigar a nova biblioteca de pool de conexões (por que 147 conexões em waiting geram contexto excedido ao invés de throughput escalonado).
* [ ] **DBA/SRE:** Rever o limite de 250 conexões no RDS. Se a expectativa de tráfego normal é bater 2600+ req/s, o limite de 250 do banco ou a modelagem do pool (20 por pod) precisam ser redimensionados (uso de PgBouncer, se aplicável).
* [ ] **Dev:** Reverter o timeout de 2s para 5s (ou um valor intermediário como 3.5s) e analisar o tempo real das queries de lote (batch).
* [ ] **Ops:** Ajustar o HPA para que o `maxReplicas` * `maxPoolSize` nunca seja superior ao limite máximo permitido pelo RDS para evitar incidentes futuros.

## Resultados
