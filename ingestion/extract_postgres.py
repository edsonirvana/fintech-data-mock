"""
ingestion/extract_postgres.py
Extrai tabelas do PostgreSQL legado e salva como CSV particionado por data.

Simula a extração de dados operacionais da PayBridge Financeira.
Para o challenge, gera dados sintéticos realistas se PostgreSQL não estiver disponível.
"""

import os
import csv
import random
import logging
import argparse
from datetime import date, timedelta, datetime
from decimal import Decimal
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s"
)
logger = logging.getLogger("extract_postgres")

OUTPUT_DIR = Path("./data/raw")
START_DATE = date(2022, 1, 1)
END_DATE = date.today()

MERCHANT_SEGMENTS = ["food_delivery", "retail", "saas", "healthcare", "education", "logistics"]
PAYMENT_METHODS = ["credit_card", "debit_card", "pix", "boleto", "ted"]
TRANSACTION_STATUSES = ["approved", "approved", "approved", "denied", "cancelled", "chargeback", "pending"]
CUSTOMER_SEGMENTS = ["startup", "sme", "enterprise", "micro"]
CREDIT_RATINGS = ["AAA", "AA", "A", "BBB", "BB", "B", "CCC"]

FERIADOS_BRASIL = {
    date(2024, 1, 1), date(2024, 2, 12), date(2024, 2, 13),
    date(2024, 4, 19), date(2024, 4, 21), date(2024, 5, 1),
    date(2024, 6, 20), date(2024, 9, 7), date(2024, 10, 12),
    date(2024, 11, 2), date(2024, 11, 15), date(2024, 12, 25),
}


def is_business_day(d: date) -> bool:
    return d.weekday() < 5 and d not in FERIADOS_BRASIL


def generate_customers(n: int = 500) -> list[dict]:
    logger.info(f"Gerando {n} clientes...")
    customers = []
    for i in range(1, n + 1):
        segment = random.choice(CUSTOMER_SEGMENTS)
        rating = random.choice(CREDIT_RATINGS)
        reg_date = START_DATE + timedelta(days=random.randint(0, 365))
        customers.append({
            "customer_id": f"CUS{i:06d}",
            "company_name": f"Empresa {i} Ltda",
            "cnpj": f"{random.randint(10,99)}.{random.randint(100,999)}.{random.randint(100,999)}/0001-{random.randint(10,99)}",
            "customer_segment": segment,
            "credit_rating": rating,
            "monthly_revenue_brl": round(random.uniform(50_000, 5_000_000), 2),
            "registration_date": reg_date.isoformat(),
            "city": random.choice(["São Paulo", "Rio de Janeiro", "Belo Horizonte", "Curitiba", "Porto Alegre"]),
            "state": random.choice(["SP", "RJ", "MG", "PR", "RS"]),
            "is_active": random.random() > 0.05,
            "account_manager_id": f"AM{random.randint(1,20):03d}",
        })
    return customers


def generate_merchants(n: int = 200) -> list[dict]:
    logger.info(f"Gerando {n} estabelecimentos...")
    merchants = []
    for i in range(1, n + 1):
        segment = random.choice(MERCHANT_SEGMENTS)
        mdr_base = {"food_delivery": 2.5, "retail": 1.8, "saas": 3.2,
                    "healthcare": 1.5, "education": 2.0, "logistics": 1.9}
        merchants.append({
            "merchant_id": f"MER{i:05d}",
            "merchant_name": f"Loja {segment.title()} {i}",
            "merchant_segment": segment,
            "mdr_credit": round(mdr_base[segment] + random.uniform(-0.3, 0.5), 3),
            "mdr_debit": round(mdr_base[segment] * 0.6 + random.uniform(-0.1, 0.2), 3),
            "mdr_pix": round(0.4 + random.uniform(0, 0.2), 3),
            "activated_at": (START_DATE + timedelta(days=random.randint(0, 180))).isoformat(),
            "is_active": random.random() > 0.08,
            "customer_id": f"CUS{random.randint(1,500):06d}",
        })
    return merchants


def generate_transactions(merchants: list[dict], n_days: int = 730) -> list[dict]:
    logger.info("Gerando transações...")
    transactions = []
    tx_id = 1
    current = START_DATE

    while current <= END_DATE and tx_id <= 100_000:
        volume_factor = 1.5 if not is_business_day(current) else 1.0
        daily_txs = int(random.uniform(50, 300) * volume_factor)

        for _ in range(daily_txs):
            merchant = random.choice(merchants)
            method = random.choice(PAYMENT_METHODS)
            amount = round(random.uniform(10, 50_000), 2)

            mdr_rate = {
                "credit_card": merchant["mdr_credit"],
                "debit_card": merchant["mdr_debit"],
                "pix": merchant["mdr_pix"],
                "boleto": 1.8,
                "ted": 0.5,
            }.get(method, 2.0)

            mdr_amount = round(amount * mdr_rate / 100, 2)
            net_amount = round(amount - mdr_amount, 2)

            transactions.append({
                "transaction_id": f"TXN{tx_id:09d}",
                "merchant_id": merchant["merchant_id"],
                "customer_id": merchant["customer_id"],
                "amount_brl": amount,
                "mdr_rate_pct": mdr_rate,
                "mdr_amount_brl": mdr_amount,
                "net_amount_brl": net_amount,
                "payment_method": method,
                "status": random.choice(TRANSACTION_STATUSES),
                "transaction_date": current.isoformat(),
                "transaction_ts": f"{current.isoformat()}T{random.randint(0,23):02d}:{random.randint(0,59):02d}:{random.randint(0,59):02d}",
                "installments": random.randint(1, 12) if method == "credit_card" else 1,
                "authorization_code": f"AUTH{random.randint(100000,999999)}",
                "acquirer": random.choice(["cielo", "rede", "getnet", "stone"]),
            })
            tx_id += 1

        current += timedelta(days=1)

    logger.info(f"  {len(transactions):,} transações geradas")
    return transactions


def generate_credit_contracts(customers: list[dict]) -> list[dict]:
    logger.info("Gerando contratos de crédito...")
    contracts = []
    contract_id = 1

    for customer in random.sample(customers, k=min(200, len(customers))):
        n_contracts = random.randint(1, 4)
        for _ in range(n_contracts):
            start = START_DATE + timedelta(days=random.randint(0, 400))
            term_months = random.choice([6, 12, 18, 24, 36, 48])
            end = start + timedelta(days=term_months * 30)
            principal = round(random.uniform(10_000, 500_000), 2)
            rate_monthly = round(random.uniform(0.8, 3.5), 4)
            outstanding = round(principal * random.uniform(0.0, 1.0), 2)
            days_past_due = 0 if random.random() > 0.12 else random.randint(1, 180)

            # Classificação BACEN (Resolução CMN 2682)
            if days_past_due == 0:
                risk_class = "AA"
            elif days_past_due <= 14:
                risk_class = "A"
            elif days_past_due <= 30:
                risk_class = "B"
            elif days_past_due <= 60:
                risk_class = "C"
            elif days_past_due <= 90:
                risk_class = "D"
            elif days_past_due <= 120:
                risk_class = "E"
            elif days_past_due <= 150:
                risk_class = "F"
            elif days_past_due <= 180:
                risk_class = "G"
            else:
                risk_class = "H"

            contracts.append({
                "contract_id": f"CTR{contract_id:07d}",
                "customer_id": customer["customer_id"],
                "product_type": random.choice(["working_capital", "credit_line", "equipment_finance", "trade_finance"]),
                "principal_brl": principal,
                "outstanding_balance_brl": outstanding,
                "monthly_rate_pct": rate_monthly,
                "term_months": term_months,
                "contract_date": start.isoformat(),
                "maturity_date": end.isoformat(),
                "days_past_due": days_past_due,
                "risk_classification_bacen": risk_class,
                "is_npl": days_past_due > 90,
                "is_written_off": days_past_due > 180 and random.random() > 0.5,
                "collateral_type": random.choice(["none", "receivables", "real_estate", "equipment"]),
                "collateral_value_brl": round(principal * random.uniform(0, 2.0), 2),
            })
            contract_id += 1

    logger.info(f"  {len(contracts):,} contratos gerados")
    return contracts


def generate_daily_rates(n_days: int = 730) -> list[dict]:
    logger.info("Gerando taxas diárias (CDI, Selic, câmbio)...")
    rates = []
    cdi = 10.75
    usd_brl = 5.10
    current = START_DATE

    while current <= END_DATE:
        cdi += random.uniform(-0.05, 0.05)
        cdi = max(8.0, min(15.0, cdi))
        usd_brl += random.uniform(-0.08, 0.08)
        usd_brl = max(4.5, min(6.5, usd_brl))

        rates.append({
            "rate_date": current.isoformat(),
            "cdi_annual_pct": round(cdi, 4),
            "selic_annual_pct": round(cdi + 0.1, 4),
            "usd_brl": round(usd_brl, 4),
            "eur_brl": round(usd_brl * 1.09, 4),
            "is_business_day": is_business_day(current),
        })
        current += timedelta(days=1)

    return rates


def save_csv(data: list[dict], filename: str) -> Path:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUTPUT_DIR / filename
    if not data:
        logger.warning(f"Nenhum dado para {filename}")
        return path

    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=data[0].keys())
        writer.writeheader()
        writer.writerows(data)

    logger.info(f"  Salvo: {path} ({len(data):,} linhas)")
    return path


def main():
    parser = argparse.ArgumentParser(description="Extrai/gera dados da PayBridge para o challenge")
    parser.add_argument("--mode", choices=["synthetic", "postgres"], default="synthetic",
                        help="Fonte dos dados: sintético (default) ou PostgreSQL real")
    args = parser.parse_args()

    logger.info("=== PayBridge Data Extraction ===")
    logger.info(f"Modo: {args.mode}")

    if args.mode == "synthetic":
        logger.info("Gerando dados sintéticos realistas...")
        customers = generate_customers(500)
        merchants = generate_merchants(200)
        transactions = generate_transactions(merchants)
        contracts = generate_credit_contracts(customers)
        rates = generate_daily_rates()

        save_csv(customers, "customers.csv")
        save_csv(merchants, "merchants.csv")
        save_csv(transactions, "transactions.csv")
        save_csv(contracts, "credit_contracts.csv")
        save_csv(rates, "daily_rates.csv")

    elif args.mode == "postgres":
        # Extração real — requer variáveis de ambiente:
        # PG_HOST, PG_PORT, PG_DB, PG_USER, PG_PASSWORD
        try:
            import psycopg2
            import psycopg2.extras

            conn_params = {
                "host": os.environ["PG_HOST"],
                "port": os.environ.get("PG_PORT", 5432),
                "dbname": os.environ["PG_DB"],
                "user": os.environ["PG_USER"],
                "password": os.environ["PG_PASSWORD"],
            }

            logger.info(f"Conectando ao PostgreSQL: {conn_params['host']}:{conn_params['port']}")
            conn = psycopg2.connect(**conn_params)

            TABLES = ["transactions", "customers", "merchants", "credit_contracts", "daily_rates", "chargebacks"]
            for table in TABLES:
                with conn.cursor(cursor_factory=psycopg2.extras.DictCursor) as cur:
                    cur.execute(f"SELECT COUNT(*) FROM {table}")
                    count = cur.fetchone()[0]
                    logger.info(f"  {table}: {count:,} linhas")

                    cur.execute(f"SELECT * FROM {table}")
                    rows = [dict(row) for row in cur.fetchall()]
                    save_csv(rows, f"{table}.csv")

            conn.close()

        except ImportError:
            logger.error("psycopg2 não instalado. Execute: pip install psycopg2-binary")
            raise
        except KeyError as e:
            logger.error(f"Variável de ambiente não encontrada: {e}")
            raise

    logger.info("=== Extração concluída ===")
    logger.info(f"Arquivos em: {OUTPUT_DIR.absolute()}")


if __name__ == "__main__":
    main()
