#!/bin/bash
# infra/setup_gcp.sh
# Provisionamento completo do ambiente GCP para o challenge
# Uso: ./infra/setup_gcp.sh

set -euo pipefail

# ─── Configurações ───────────────────────────────────────────────────────────
PROJECT_ID="${GCP_PROJECT_ID:-paybridge-data-challenge}"
REGION="${GCP_REGION:-us-central1}"
SA_NAME="dbt-sa"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
KEY_PATH="./infra/keys/dbt-sa-key.json"
BUCKET_NAME="${PROJECT_ID}-raw-zone"

# ─── Cores para output ───────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }

# ─── 1. Autenticação e seleção do projeto ────────────────────────────────────
log_info "Configurando projeto GCP: ${PROJECT_ID}"
gcloud config set project "${PROJECT_ID}"

# ─── 2. Habilitar APIs necessárias ───────────────────────────────────────────
log_info "Habilitando APIs..."
gcloud services enable \
  bigquery.googleapis.com \
  storage.googleapis.com \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  --quiet
log_ok "APIs habilitadas"

# ─── 3. Criar Service Account para dbt ───────────────────────────────────────
log_info "Criando Service Account: ${SA_NAME}"
gcloud iam service-accounts create "${SA_NAME}" \
  --display-name="dbt Service Account" \
  --description="Usado pelo dbt para acessar BigQuery" \
  --quiet 2>/dev/null || log_warn "Service Account já existe, pulando criação"

# ─── 4. Atribuir permissões mínimas ──────────────────────────────────────────
log_info "Atribuindo permissões IAM..."

ROLES=(
  "roles/bigquery.dataEditor"
  "roles/bigquery.jobUser"
  "roles/bigquery.metadataViewer"
  "roles/storage.objectViewer"
)

for ROLE in "${ROLES[@]}"; do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="${ROLE}" \
    --quiet
  log_ok "Permissão concedida: ${ROLE}"
done

# ─── 5. Gerar chave JSON ──────────────────────────────────────────────────────
mkdir -p ./infra/keys
log_info "Gerando chave JSON..."
gcloud iam service-accounts keys create "${KEY_PATH}" \
  --iam-account="${SA_EMAIL}" \
  --quiet
log_ok "Chave salva em ${KEY_PATH}"
log_warn "NUNCA faça commit desta chave no Git! Está no .gitignore."

# ─── 6. Criar datasets no BigQuery ───────────────────────────────────────────
log_info "Criando datasets no BigQuery..."

DATASETS=("raw" "staging" "analytics" "audit")

for DS in "${DATASETS[@]}"; do
  bq mk \
    --dataset \
    --location="${REGION}" \
    --description="PayBridge: camada ${DS}" \
    "${PROJECT_ID}:${DS}" 2>/dev/null || log_warn "Dataset ${DS} já existe"
  log_ok "Dataset criado: ${DS}"
done

# ─── 7. Criar bucket no Cloud Storage ────────────────────────────────────────
log_info "Criando bucket: gs://${BUCKET_NAME}"
gsutil mb \
  -p "${PROJECT_ID}" \
  -c STANDARD \
  -l "${REGION}" \
  "gs://${BUCKET_NAME}" 2>/dev/null || log_warn "Bucket já existe"

# Criar estrutura de pastas no bucket
gsutil -m cp /dev/null "gs://${BUCKET_NAME}/raw/transactions/.keep"
gsutil -m cp /dev/null "gs://${BUCKET_NAME}/raw/customers/.keep"
gsutil -m cp /dev/null "gs://${BUCKET_NAME}/raw/credit_contracts/.keep"
gsutil -m cp /dev/null "gs://${BUCKET_NAME}/raw/merchants/.keep"
gsutil -m cp /dev/null "gs://${BUCKET_NAME}/raw/daily_rates/.keep"
gsutil -m cp /dev/null "gs://${BUCKET_NAME}/raw/chargebacks/.keep"
log_ok "Estrutura do bucket criada"

# ─── 8. Criar tabela de auditoria ────────────────────────────────────────────
log_info "Criando tabela de auditoria..."
bq mk \
  --table \
  --time_partitioning_field=started_at \
  --time_partitioning_type=DAY \
  "${PROJECT_ID}:audit.pipeline_runs" \
  "run_id:STRING,pipeline_name:STRING,step:STRING,status:STRING,rows_processed:INTEGER,rows_failed:INTEGER,started_at:TIMESTAMP,finished_at:TIMESTAMP,error_message:STRING,triggered_by:STRING,git_commit_sha:STRING" \
  2>/dev/null || log_warn "Tabela pipeline_runs já existe"
log_ok "Tabela de auditoria criada"

# ─── 9. Gerar profiles.yml para dbt ──────────────────────────────────────────
cat > ./dbt_project/profiles.yml << EOF
paybridge:
  target: dev
  outputs:
    dev:
      type: bigquery
      method: service-account
      project: ${PROJECT_ID}
      dataset: staging
      keyfile: ../infra/keys/dbt-sa-key.json
      threads: 4
      location: ${REGION}
      timeout_seconds: 300
      priority: interactive
    prod:
      type: bigquery
      method: service-account
      project: ${PROJECT_ID}
      dataset: analytics
      keyfile: ../infra/keys/dbt-sa-key.json
      threads: 8
      location: ${REGION}
      timeout_seconds: 600
      priority: batch
EOF
log_ok "profiles.yml gerado em dbt_project/"

# ─── Resumo ───────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════"
echo "  Setup concluído com sucesso!"
echo "════════════════════════════════════════════"
echo "  Projeto GCP:  ${PROJECT_ID}"
echo "  Service Acct: ${SA_EMAIL}"
echo "  Bucket:       gs://${BUCKET_NAME}"
echo "  Datasets:     raw, staging, analytics, audit"
echo "  Chave JSON:   ${KEY_PATH}"
echo ""
echo "  Próximo passo:"
echo "  cd ingestion && python extract_postgres.py"
echo "════════════════════════════════════════════"
