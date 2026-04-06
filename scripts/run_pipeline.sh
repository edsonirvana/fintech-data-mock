#!/bin/bash
# scripts/run_pipeline.sh
# Executa o pipeline completo da PayBridge
# Uso: ./scripts/run_pipeline.sh [--step ingestion|dbt|all]

set -euo pipefail

STEP="${1:-all}"
LOG_DIR="./logs"
RUN_ID=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/pipeline_${RUN_ID}.log"

mkdir -p "${LOG_DIR}"

log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "${LOG_FILE}"; }
log_section() {
  echo "" | tee -a "${LOG_FILE}"
  echo "════════════════════════════════════════" | tee -a "${LOG_FILE}"
  echo "  $1" | tee -a "${LOG_FILE}"
  echo "════════════════════════════════════════" | tee -a "${LOG_FILE}"
}

export GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "no-git")
export TRIGGERED_BY="${TRIGGERED_BY:-manual}"

log_section "PayBridge Data Pipeline — Run ${RUN_ID}"
log "Git SHA: ${GIT_SHA}"
log "Disparado por: ${TRIGGERED_BY}"

if [[ "${STEP}" == "ingestion" || "${STEP}" == "all" ]]; then
  log_section "ETAPA 1: Extração e Ingestão"

  log "Gerando/extraindo dados..."
  cd ingestion
  python extract_postgres.py 2>&1 | tee -a "../${LOG_FILE}"

  log "Carregando para BigQuery..."
  python load_to_bigquery.py 2>&1 | tee -a "../${LOG_FILE}"
  cd ..

  log "✓ Ingestão concluída"
fi

if [[ "${STEP}" == "dbt" || "${STEP}" == "all" ]]; then
  log_section "ETAPA 2: Transformações dbt"

  cd dbt_project

  log "Validando conexão..."
  dbt debug 2>&1 | tee -a "../${LOG_FILE}"

  log "Instalando pacotes dbt..."
  dbt deps 2>&1 | tee -a "../${LOG_FILE}"

  log "Executando modelos..."
  dbt run --target prod 2>&1 | tee -a "../${LOG_FILE}"

  log "Executando testes de qualidade..."
  dbt test 2>&1 | tee -a "../${LOG_FILE}"

  log "Gerando documentação..."
  dbt docs generate 2>&1 | tee -a "../${LOG_FILE}"

  cd ..
  log "✓ Transformações dbt concluídas"
fi

log_section "Pipeline Concluído"
log "Run ID: ${RUN_ID}"
log "Log salvo em: ${LOG_FILE}"
log ""
log "Próximo passo: acesse o Looker e atualize os dashboards"
