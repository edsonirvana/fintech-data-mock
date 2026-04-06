# Dicionário de Dados — PayBridge Financeira

> Documento de referência para todos os campos presentes nas camadas staging, intermediate e marts.

---

## Camada: Staging

### `stg_transactions`

| Campo | Tipo | Descrição | PII |
|---|---|---|---|
| `transaction_id` | STRING | Identificador único da transação | Não |
| `merchant_id` | STRING | Referência ao estabelecimento | Não |
| `customer_id` | STRING | Referência ao cliente | Não |
| `amount_brl` | NUMERIC | Valor bruto da transação em R$ | Não |
| `mdr_rate_pct` | NUMERIC | Taxa MDR aplicada (%) | Não |
| `mdr_amount_brl` | NUMERIC | Valor do MDR em R$ | Não |
| `net_amount_brl` | NUMERIC | Valor líquido recebido pelo lojista | Não |
| `payment_method` | STRING | Método: credit_card, debit_card, pix, boleto, ted | Não |
| `status` | STRING | Status: approved, denied, cancelled, chargeback, pending | Não |
| `transaction_date` | DATE | Data da transação (partição) | Não |
| `transaction_ts` | TIMESTAMP | Timestamp completo | Não |
| `installments` | INT64 | Número de parcelas (1 = à vista) | Não |
| `authorization_code` | STRING | Código de autorização da operadora | Não |
| `acquirer` | STRING | Adquirente: cielo, rede, getnet, stone | Não |
| `is_approved` | BOOL | Flag derivada: transação aprovada | Não |
| `is_chargeback` | BOOL | Flag derivada: transação em chargeback | Não |
| `is_installment` | BOOL | Flag derivada: parcelado (>1 parcela) | Não |
| `is_weekend` | BOOL | Flag derivada: transação em fim de semana | Não |

### `stg_credit_contracts`

| Campo | Tipo | Descrição | Regulatório |
|---|---|---|---|
| `contract_id` | STRING | Identificador único do contrato | — |
| `customer_id` | STRING | Referência ao cliente | — |
| `product_type` | STRING | working_capital, credit_line, equipment_finance, trade_finance | — |
| `principal_brl` | NUMERIC | Valor original do contrato em R$ | — |
| `outstanding_balance_brl` | NUMERIC | Saldo devedor atual em R$ | Sim |
| `monthly_rate_pct` | NUMERIC | Taxa de juros mensal (%) | Sim |
| `days_past_due` | INT64 | Dias em atraso | Sim |
| `risk_classification_bacen` | STRING | Classificação AA a H (Res. CMN 2682) | Sim |
| `is_npl` | BOOL | Flag: Non-Performing Loan (>90 dias) | Sim |
| `is_written_off` | BOOL | Flag: Baixado a prejuízo | Sim |
| `risk_level_num` | INT64 | Nível numérico de risco (0=AA, 8=H) | — |
| `collateral_coverage_ratio` | NUMERIC | Colateral / Saldo devedor | — |

---

## Camada: Marts

### `mart_fin_daily_summary`

**Domínio:** Financeiro | **Partição:** `summary_date` | **Cluster:** `payment_method`

| Campo | Tipo | KPI | Descrição |
|---|---|---|---|
| `summary_date` | DATE | — | Data de referência (partição) |
| `payment_method` | STRING | — | Método de pagamento |
| `total_transactions` | INT64 | — | Total de transações (todos os status) |
| `approved_transactions` | INT64 | — | Transações aprovadas |
| `total_tpv_brl` | NUMERIC | **TPV** | Total Payment Volume (aprovadas) |
| `total_mdr_revenue_brl` | NUMERIC | **Receita MDR** | Receita bruta de MDR |
| `avg_mdr_rate_pct` | NUMERIC | **MDR Médio** | Taxa média ponderada de MDR |
| `approval_rate_pct` | NUMERIC | **Taxa Aprovação** | % de aprovação sobre total |
| `chargeback_rate_pct` | NUMERIC | **Chargeback Rate** | % de chargebacks sobre aprovadas |
| `avg_ticket_brl` | NUMERIC | **Ticket Médio** | Valor médio das transações aprovadas |

### `mart_risk_credit_portfolio`

**Domínio:** Risco | **Acesso:** Restrito (equipe de risco + executivo) | **Base regulatória:** Res. CMN 2682

| Campo | Tipo | KPI | Descrição |
|---|---|---|---|
| `risk_classification_bacen` | STRING | — | Classificação BACEN (AA a H) |
| `dpd_bucket` | STRING | — | Faixa de atraso em dias |
| `total_outstanding_brl` | NUMERIC | **Exposição** | Saldo devedor total da carteira |
| `npl_balance_brl` | NUMERIC | **NPL** | Saldo inadimplente (>90 dias) |
| `npl_rate_pct` | NUMERIC | **Índice NPL** | NPL / Saldo total (%) |
| `total_expected_loss_brl` | NUMERIC | **Perda Esperada** | Provisão mínima BACEN |
| `portfolio_coverage_ratio` | NUMERIC | **Cobertura** | Colateral / Saldo devedor |
| `written_off_balance_brl` | NUMERIC | — | Saldo baixado a prejuízo |
| `snapshot_date` | DATE | — | Data do snapshot |

---

## Macros Disponíveis

| Macro | Propósito | Exemplo de Uso |
|---|---|---|
| `calculate_mdr(gross, net)` | Calcula MDR percentual | `{{ calculate_mdr('amount_brl', 'net_amount_brl') }}` |
| `classify_risk_bacen(dpd)` | Classifica risco por DPD | `{{ classify_risk_bacen('days_past_due') }}` |
| `bacen_provision_rate(class)` | Taxa de provisão BACEN | `{{ bacen_provision_rate('risk_classification_bacen') }}` |
| `mask_pii(col, type)` | Mascaramento LGPD | `{{ mask_pii('cnpj', 'cnpj') }}` |
| `business_days_between(d1, d2)` | Dias úteis (BR) | `{{ business_days_between('contract_date', 'current_date()') }}` |
| `monthly_to_annual_rate(rate)` | Conversão taxa mensal→anual | `{{ monthly_to_annual_rate('monthly_rate_pct') }}` |

---

## Glossário de Termos Financeiros

| Termo | Definição |
|---|---|
| **TPV** | Total Payment Volume — volume total de transações aprovadas em R$ |
| **MDR** | Merchant Discount Rate — taxa cobrada do lojista pela operadora |
| **NPL** | Non-Performing Loan — crédito com mais de 90 dias em atraso |
| **DPD** | Days Past Due — dias em atraso desde o vencimento |
| **Chargeback** | Contestação de transação pelo portador do cartão |
| **Provisão BACEN** | Reserva mínima exigida pela regulação para créditos de risco |
| **CDI** | Certificado de Depósito Interbancário — taxa de referência do mercado financeiro BR |
| **Resolução CMN 2682** | Regulação do Banco Central que define classificação de risco de crédito |
| **RLS** | Row-Level Security — controle de acesso em nível de linha de dado |
