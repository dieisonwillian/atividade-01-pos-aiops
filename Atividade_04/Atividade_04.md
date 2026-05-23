## Questão 04 - Relatório mensal de transações do Ledger
Jennifer está fechando a apresentação que vai levar pra Goldie na semana que vem, sobre crescimento de transações nos últimos 6 meses por categoria. Ela precisa dos números consolidados mas não escreve SQL, então mandou a demanda pra sua fila. O Ledger (PostgreSQL) tem o histórico completo, e as duas tabelas relevantes estão abaixo.

CREATE TABLE transactions (
  id              BIGSERIAL PRIMARY KEY,
  customer_id     BIGINT NOT NULL REFERENCES customers(id),
  category        VARCHAR(32) NOT NULL,
  amount_cents    BIGINT NOT NULL,
  status          VARCHAR(16) NOT NULL,
  payment_method  VARCHAR(16),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at    TIMESTAMPTZ
);

CREATE INDEX idx_transactions_created_at ON transactions(created_at);
CREATE INDEX idx_transactions_status ON transactions(status);
CREATE INDEX idx_transactions_category ON transactions(category);
CREATE TABLE customers (
  id          BIGSERIAL PRIMARY KEY,
  segment     VARCHAR(16) NOT NULL,
  country     CHAR(2) NOT NULL,
  signup_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
Categorias em produção hoje: subscription, one_time, refund e credit_adjustment. Só entra no relatório quem tem status = 'completed'. O campo amount_cents está em centavos de real e precisa aparecer na saída em reais com 2 casas decimais. O recorte é dos últimos 6 meses corridos a partir de hoje (2026-04-24), agrupado por mês (no formato YYYY-MM) e por categoria, trazendo duas métricas por linha: quantidade de transações e volume total em reais. Ordenação final: mês crescente, depois categoria crescente.

Tarefa. Aplicando o framework T-A-G, escrever o prompt de IA que produza essa query SQL.

Entregue. Prompt, modelo, output e justificativa mostrando como Task, Action e Goal aparecem no prompt.

## Justificativa

Tentei entender a logica mas acredito que até o momento esta foi a mais complexa de se entender, tentei criar um prompt que tenha todos os requisitos e feito da forma que cumpra com os requisitos do TAG.

## Modelo

Sonnet 4.6

## Prompt

Tarefa
Gerar indicador para complementar a apresentação.

Ação
Avaliar a estrutura destas duas tabelas para que consiga buscar os dados necessários:
CREATE TABLE transactions (
  id              BIGSERIAL PRIMARY KEY,
  customer_id     BIGINT NOT NULL REFERENCES customers(id),
  category        VARCHAR(32) NOT NULL,
  amount_cents    BIGINT NOT NULL,
  status          VARCHAR(16) NOT NULL,
  payment_method  VARCHAR(16),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at    TIMESTAMPTZ
);

CREATE INDEX idx_transactions_created_at ON transactions(created_at);
CREATE INDEX idx_transactions_status ON transactions(status);
CREATE INDEX idx_transactions_category ON transactions(category);
CREATE TABLE customers (
  id          BIGSERIAL PRIMARY KEY,
  segment     VARCHAR(16) NOT NULL,
  country     CHAR(2) NOT NULL,
  signup_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


Objetivo
Crie um Query SQL para consolidar as transações e o valor movimentado no últimos 6 meses a partir de (2026-04-24), deve ser considerador apenas registros com o campo status = 'completed", campo amount_cents deve ser convertido de centantávos para reais com 2 casas decimais, a saída é um relatório com dias metricas por linha, quantidade de transações e volume total em reais, ele deve ser agrupado por mês YYYY-MM e por categoria, ordenação mês cresente, depois categoria crescente.


## Saida do Prompt (Chat)

```sql
SELECT
    TO_CHAR(DATE_TRUNC('month', created_at), 'YYYY-MM')  AS mes,
    category                                              AS categoria,
    COUNT(*)                                              AS quantidade_transacoes,
    ROUND(SUM(amount_cents) / 100.0, 2)                  AS volume_total_reais
FROM transactions
WHERE
    status     = 'completed'
    AND created_at >= '2025-10-24 00:00:00+00'   -- 6 meses antes de 2026-04-24
    AND created_at <  '2026-04-25 00:00:00+00'   -- inclusive até o dia 2026-04-24
GROUP BY
    DATE_TRUNC('month', created_at),
    category
ORDER BY
    DATE_TRUNC('month', created_at) ASC,
    category                        ASC;
```

**Pontos relevantes da query:**

- **Filtro de período** — usa `created_at` com um intervalo fechado (`>=` / `<`) em vez de funções sobre a coluna, o que aproveita o índice `idx_transactions_created_at` sem precisar de full scan.
- **Filtro de status** — `status = 'completed'` bate direto no índice `idx_transactions_status`.
- **Conversão de centavos** — `SUM(amount_cents) / 100.0` mantém precisão numérica antes do `ROUND(..., 2)`, evitando truncamento por divisão inteira.
- **Agrupamento** — `DATE_TRUNC('month', created_at)` é usado tanto no `GROUP BY` quanto no `ORDER BY` para garantir ordenação cronológica real; o `TO_CHAR` fica só no `SELECT` para formatação visual.
- **Saída esperada:**

| mes | categoria | quantidade_transacoes | volume_total_reais |
|---|---|---|---|
| 2025-10 | food | 312 | 48.750,90 |
| 2025-10 | travel | 87 | 212.340,00 |
| … | … | … | … |


## Resultados

