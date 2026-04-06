# Decisões de Arquitetura — PayBridge Financeira

## Contexto

Este documento registra as principais decisões técnicas tomadas no projeto, incluindo raciocínio e trade-offs. Segue o padrão ADR (Architecture Decision Record).

---

## ADR-001: Medalion Architecture no BigQuery

**Status:** Aceito  
**Contexto:** Precisamos de uma arquitetura que separe claramente responsabilidades entre ingestão, transformação e consumo analítico.

**Decisão:** Implementar a Medalion Architecture com 4 camadas no BigQuery:

| Dataset | Propósito | Materialização |
|---|---|---|
| `raw` | Dados brutos sem transformação, imutáveis | External Tables / Native Tables |
| `staging` | Limpeza, cast de tipos, filtros nulos | dbt views |
| `intermediate` | Joins, regras de negócio, deduplicação | dbt tables |
| `analytics` (marts) | KPIs, métricas finais, consumo por Looker | dbt tables com particionamento |
| `audit` | Logs de execução, lineage, alertas de qualidade | Native tables |

**Consequências:** Custo maior de armazenamento, mas queries de produção sempre acessam marts otimizados. Staging como views elimina duplicação de dados intermediários.

---

## ADR-002: Particionamento e Clustering no BigQuery

**Status:** Aceito  
**Contexto:** Tabelas de transações e contratos de crédito têm potencial para crescer para bilhões de linhas.

**Decisão:**
- Todas as tabelas mart são **particionadas por data** (`transaction_date`, `contract_date`)
- Clustering por `merchant_id` em tabelas financeiras e por `customer_segment` em tabelas de risco
- Retenção de partições configurada para 365 dias nos marts e 90 dias no staging

**Rationale:** Em fintech, a maioria das queries de risco e financeiro filtra por período. Particionamento por data reduz custo de scan em até 95% para consultas mensais.

```sql
-- Exemplo de configuração no dbt
{{ config(
    materialized='table',
    partition_by={
      "field": "transaction_date",
      "data_type": "date",
      "granularity": "day"
    },
    cluster_by=["merchant_id", "payment_method"],
    partition_expiration_days=365
) }}
```

---

## ADR-003: Estratégia de Macros dbt para Fintech

**Status:** Aceito  
**Contexto:** Cálculos de MDR, NPL e exposição de crédito seguem fórmulas regulatórias específicas que precisam ser consistentes em todos os modelos.

**Decisão:** Criar macros Jinja centralizadas para:

1. `calculate_mdr(gross_amount, net_amount)` — cálculo padronizado de MDR
2. `classify_overdue(days_past_due)` — classificação de inadimplência (Resolução CMN 2682)
3. `mask_pii(column_name, mask_type)` — mascaramento de CPF, CNPJ e dados bancários
4. `assert_financial_reconciliation(debit_col, credit_col, tolerance)` — teste de consistência contábil
5. `get_business_days(start_date, end_date)` — dias úteis brasileiros (considera feriados)

**Consequências:** Mudanças na fórmula de MDR precisam ser feitas em um único lugar. Auditoria mais simples.

---

## ADR-004: Governança com Row-Level Security

**Status:** Aceito  
**Contexto:** Dados de risco de crédito não podem ser acessados pela área comercial. CPF e dados bancários são PII.

**Decisão:** Implementar RLS em três camadas:

1. **BigQuery IAM:** Service accounts separadas por área (risco, financeiro, comercial, exec)
2. **BigQuery Row Access Policies:** Filtros por `business_unit` nas tabelas sensíveis
3. **Looker User Attributes:** `user_attribute: business_unit` aplicado em todos os Explores sensíveis

```sql
-- Row Access Policy no BigQuery
CREATE ROW ACCESS POLICY risk_team_only
  ON analytics.marts_risk_credit_portfolio
  GRANT TO ("group:risk-team@paybridge.com.br")
  FILTER USING (business_unit = 'risk');
```

---

## ADR-005: Estratégia LookML — Camada Semântica

**Status:** Aceito  
**Contexto:** Diferentes áreas usam os mesmos dados com definições distintas de "receita" e "cliente ativo".

**Decisão:** Construir a camada semântica no Looker com:

1. **Views:** uma por mart/entidade, com dimensões e medidas claramente nomeadas
2. **Explores:** agrupados por domínio (financeiro, risco, operacional)
3. **Derived Tables:** para métricas complexas que não cabem em SQL simples
4. **Refinements:** para reutilização de views entre explores sem duplicação
5. **Access Grants:** para controlar quais campos cada grupo pode ver

**Princípio DRY aplicado:**
```lookml
# Medida definida UMA VEZ na view
measure: net_revenue {
  type: sum
  sql: ${TABLE}.net_revenue_brl ;;
  value_format_name: brazilian_real
  description: "Receita líquida após MDR e custos operacionais"
}
# Todos os dashboards referenciam esta medida — nunca redefinem
```

---

## ADR-006: Qualidade de Dados — Framework de Testes

**Status:** Aceito  
**Contexto:** Dados financeiros têm requisitos regulatórios. Erros em cálculos de risco podem ter consequências legais.

**Decisão:** Três camadas de testes:

| Camada | Ferramenta | Exemplos |
|---|---|---|
| Schema | dbt nativo | `not_null`, `unique`, `accepted_values` |
| Negócio | dbt_expectations | `expect_column_sum_to_be_between`, ranges de MDR |
| Reconciliação | Macros customizadas | Débito = crédito, TPV bate com operadora |

**Alertas:** Falhas em testes de reconciliação financeira bloqueiam o pipeline e geram alerta via webhook.

---

## ADR-007: Estratégia de Migração — Zero Downtime

**Status:** Aceito  
**Contexto:** O PostgreSQL legado não pode ser desligado durante a migração. Dados históricos de 5 anos precisam ser preservados.

**Decisão:** Migração em 4 fases:

1. **Shadow mode (semana 1–2):** Pipeline GCP em paralelo, comparação de contagens
2. **Validação (semana 3):** Reconciliação financeira entre PostgreSQL e BigQuery
3. **Cutover gradual (semana 4):** Área por área, começando pela menor (operacional)
4. **Descomissionamento (mês 2):** PostgreSQL mantido como backup por 30 dias

**Evidências de reconciliação:** Scripts em `scripts/reconcile_migration.py` geram relatório de divergências por tabela e período.
