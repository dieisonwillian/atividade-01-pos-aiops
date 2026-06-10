#!/bin/bash

################################################################################
# Script de Backup - PostgreSQL Ledger Production
# Descrição: Realiza backup do banco de dados PostgreSQL, compacta, faz upload
#            para S3 e aplica rotina de expurgo de arquivos com mais de 30 dias
# Autor: TI Especializado
# Data: $(date '+%Y-%m-%d')
################################################################################

set -euo pipefail

# ============================================================================
# CONFIGURAÇÕES
# ============================================================================

# Diretórios e caminhos
BACKUP_DIR="/var/backups/ledger"
LOG_FILE="/var/log/ledger-backup.log"
TEMP_DIR="${BACKUP_DIR}/temp"

# Configurações do PostgreSQL
DB_HOST="ledger-db.internal.hvt.io"
DB_PORT="5432"
DB_NAME="ledger_prod"
DB_USER="backup_user"

# Configurações AWS
BUCKET_NAME="hvt-ledger-backups"
AWS_REGION="us-east-1"  # Ajuste conforme sua região

# Variáveis de retenção
RETENTION_DAYS=30

# Data e hora para nomeação dos arquivos
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BACKUP_FILENAME="ledger_prod_${TIMESTAMP}.sql"
BACKUP_COMPRESSED="${BACKUP_FILENAME}.gz"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_COMPRESSED}"

# ============================================================================
# FUNÇÕES
# ============================================================================

# Função de logging
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Função de erro com cleanup
error_exit() {
    log "ERROR" "$1"
    cleanup_temp
    exit 1
}

# Função para validar pré-requisitos
validate_prerequisites() {
    log "INFO" "Validando pré-requisitos..."
    
    # Verificar comando pg_dump
    if ! command -v pg_dump &> /dev/null; then
        error_exit "pg_dump não encontrado. Instale postgresql-client"
    fi
    
    # Verificar comando aws
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI não encontrado. Instale aws-cli"
    fi
    
    # Verificar gzip
    if ! command -v gzip &> /dev/null; then
        error_exit "gzip não encontrado"
    fi
    
    # Verificar diretório de backup
    if [[ ! -d "${BACKUP_DIR}" ]]; then
        log "INFO" "Criando diretório de backup: ${BACKUP_DIR}"
        mkdir -p "${BACKUP_DIR}" || error_exit "Falha ao criar ${BACKUP_DIR}"
    fi
    
    # Verificar permissão de escrita
    if [[ ! -w "${BACKUP_DIR}" ]]; then
        error_exit "Sem permissão de escrita em ${BACKUP_DIR}"
    fi
    
    # Verificar log file
    if [[ ! -f "${LOG_FILE}" ]]; then
        touch "${LOG_FILE}" || error_exit "Falha ao criar ${LOG_FILE}"
    fi
    
    log "INFO" "Pré-requisitos validados com sucesso"
}

# Função para carregar credenciais do AWS Secrets Manager
load_credentials() {
    log "INFO" "Carregando credenciais do AWS Secrets Manager..."
    
    # Verificar se a variável PGPASSWORD já está definida
    if [[ -z "${PGPASSWORD:-}" ]]; then
        # Tentar recuperar via AWS Secrets Manager (assume IAM role configurada)
        if command -v aws &> /dev/null; then
            PGPASSWORD=$(aws secretsmanager get-secret-value \
                --secret-id ledger-db-backup-password \
                --region "${AWS_REGION}" \
                --query 'SecretString' \
                --output text 2>/dev/null || echo "") || true
            
            if [[ -z "${PGPASSWORD}" ]]; then
                log "WARN" "Senha não encontrada no Secrets Manager"
                log "WARN" "Tentando usar PGPASSWORD do ambiente..."
                if [[ -z "${PGPASSWORD:-}" ]]; then
                    error_exit "PGPASSWORD não configurada"
                fi
            fi
        fi
    fi
    
    export PGPASSWORD
    log "INFO" "Credenciais carregadas com sucesso"
}

# Função para testar conexão com o banco
test_database_connection() {
    log "INFO" "Testando conexão com banco de dados..."
    
    if ! psql \
        -h "${DB_HOST}" \
        -p "${DB_PORT}" \
        -U "${DB_USER}" \
        -d "${DB_NAME}" \
        -c "SELECT version();" &>/dev/null; then
        error_exit "Falha ao conectar no banco de dados"
    fi
    
    log "INFO" "Conexão com banco de dados estabelecida com sucesso"
}

# Função para criar diretório temporário
create_temp_dir() {
    TEMP_DIR="${BACKUP_DIR}/temp_${TIMESTAMP}"
    mkdir -p "${TEMP_DIR}" || error_exit "Falha ao criar diretório temporário"
    log "INFO" "Diretório temporário criado: ${TEMP_DIR}"
}

# Função para limpeza de diretório temporário
cleanup_temp() {
    if [[ -d "${TEMP_DIR}" ]]; then
        rm -rf "${TEMP_DIR}"
        log "INFO" "Diretório temporário removido"
    fi
}

# Função para executar backup
perform_backup() {
    log "INFO" "Iniciando backup do banco de dados: ${DB_NAME}"
    
    local backup_temp_path="${TEMP_DIR}/${BACKUP_FILENAME}"
    
    # Executar pg_dump
    if pg_dump \
        -h "${DB_HOST}" \
        -p "${DB_PORT}" \
        -U "${DB_USER}" \
        -d "${DB_NAME}" \
        --verbose \
        --format=plain \
        --compress=0 \
        --on-conflict-do-nothing \
        > "${backup_temp_path}" 2>> "${LOG_FILE}"; then
        log "INFO" "Backup SQL realizado com sucesso"
    else
        error_exit "Falha ao executar pg_dump"
    fi
    
    # Validar tamanho do arquivo
    local file_size=$(stat -f%z "${backup_temp_path}" 2>/dev/null || stat -c%s "${backup_temp_path}" 2>/dev/null)
    if [[ ${file_size} -lt 1024 ]]; then
        error_exit "Arquivo de backup muito pequeno (${file_size} bytes) - possível erro"
    fi
    
    log "INFO" "Tamanho do backup: $(numfmt --to=iec ${file_size} 2>/dev/null || echo ${file_size} 'bytes')"
    
    # Comprimir arquivo
    log "INFO" "Compactando arquivo de backup com gzip..."
    if gzip -9 "${backup_temp_path}"; then
        log "INFO" "Arquivo compactado com sucesso"
    else
        error_exit "Falha ao comprimir arquivo"
    fi
    
    # Mover para diretório final
    mv "${backup_temp_path}.gz" "${BACKUP_PATH}"
    log "INFO" "Arquivo de backup: ${BACKUP_PATH}"
}

# Função para upload para S3
upload_to_s3() {
    log "INFO" "Iniciando upload para bucket S3: ${BUCKET_NAME}"
    
    if aws s3 cp \
        "${BACKUP_PATH}" \
        "s3://${BUCKET_NAME}/" \
        --region "${AWS_REGION}" \
        --metadata "backup-date=$(date '+%Y-%m-%d'),database=${DB_NAME}" \
        --sse AES256 \
        --storage-class STANDARD_IA; then
        log "INFO" "Upload para S3 realizado com sucesso"
        log "INFO" "Arquivo: s3://${BUCKET_NAME}/${BACKUP_COMPRESSED}"
    else
        error_exit "Falha ao fazer upload para S3"
    fi
}

# Função para listar arquivos antigos
list_old_backups() {
    log "INFO" "Listando arquivos com mais de ${RETENTION_DAYS} dias no bucket..."
    
    local cutoff_date=$(date -d "${RETENTION_DAYS} days ago" '+%Y-%m-%d' 2>/dev/null || \
                        date -v-${RETENTION_DAYS}d '+%Y-%m-%d')
    
    log "INFO" "Data de corte: ${cutoff_date}"
    
    aws s3api list-objects-v2 \
        --bucket "${BUCKET_NAME}" \
        --region "${AWS_REGION}" \
        --output table | tee -a "${LOG_FILE}"
}

# Função para limpeza de backups antigos
cleanup_old_backups() {
    log "INFO" "Iniciando rotina de expurgo de backups com mais de ${RETENTION_DAYS} dias..."
    
    local cutoff_timestamp=$(date -d "${RETENTION_DAYS} days ago" '+%s' 2>/dev/null || \
                             date -v-${RETENTION_DAYS}d '+%s')
    
    local files_deleted=0
    local total_freed=0
    
    # Processar arquivos locais
    log "INFO" "Processando arquivos locais em ${BACKUP_DIR}..."
    while IFS= read -r file; do
        local file_timestamp=$(stat -f%m "${file}" 2>/dev/null || stat -c%Y "${file}")
        
        if [[ ${file_timestamp} -lt ${cutoff_timestamp} ]]; then
            local file_size=$(stat -f%z "${file}" 2>/dev/null || stat -c%s "${file}")
            rm -f "${file}"
            log "INFO" "Arquivo removido: $(basename ${file}) (${file_size} bytes)"
            ((files_deleted++))
            ((total_freed+=file_size))
        fi
    done < <(find "${BACKUP_DIR}" -maxdepth 1 -name "ledger_prod_*.sql.gz" -type f)
    
    # Processar arquivos no S3
    log "INFO" "Processando arquivos no S3 (${BUCKET_NAME})..."
    local s3_files_deleted=0
    
    aws s3api list-objects-v2 \
        --bucket "${BUCKET_NAME}" \
        --region "${AWS_REGION}" \
        --output json | jq -r '.Contents[] | select(.LastModified != null) | 
        if ((now - (.LastModified | fromdateiso8601)) > '${RETENTION_DAYS}'*86400) 
        then .Key else empty end' 2>/dev/null | while read -r key; do
        if [[ ! -z "${key}" ]]; then
            aws s3 rm "s3://${BUCKET_NAME}/${key}" --region "${AWS_REGION}"
            log "INFO" "Arquivo S3 removido: ${key}"
            ((s3_files_deleted++))
        fi
    done || true
    
    log "INFO" "Expurgo concluído: ${files_deleted} arquivos locais removidos, liberando $(numfmt --to=iec ${total_freed} 2>/dev/null || echo ${total_freed} 'bytes')"
    if [[ ${s3_files_deleted:-0} -gt 0 ]]; then
        log "INFO" "Expurgo S3 concluído: ${s3_files_deleted} arquivos removidos"
    fi
}

# Função para gerar relatório
generate_report() {
    log "INFO" "====== RELATÓRIO FINAL DE BACKUP ======"
    log "INFO" "Data/Hora: $(date '+%Y-%m-%d %H:%M:%S')"
    log "INFO" "Banco de dados: ${DB_NAME}"
    log "INFO" "Host: ${DB_HOST}"
    log "INFO" "Arquivo de backup: ${BACKUP_COMPRESSED}"
    
    if [[ -f "${BACKUP_PATH}" ]]; then
        local size=$(stat -f%z "${BACKUP_PATH}" 2>/dev/null || stat -c%s "${BACKUP_PATH}")
        log "INFO" "Tamanho do arquivo: $(numfmt --to=iec ${size} 2>/dev/null || echo ${size} 'bytes')"
    fi
    
    log "INFO" "Bucket S3: ${BUCKET_NAME}"
    log "INFO" "Período de retenção: ${RETENTION_DAYS} dias"
    log "INFO" "Status: SUCESSO"
    log "INFO" "====== FIM DO RELATÓRIO ======"
}

# Função principal
main() {
    log "INFO" "==============================================="
    log "INFO" "Iniciando processo de backup do PostgreSQL"
    log "INFO" "==============================================="
    
    validate_prerequisites
    load_credentials
    test_database_connection
    create_temp_dir
    
    # Executar processo de backup
    perform_backup
    upload_to_s3
    
    # Limpeza de arquivos antigos
    list_old_backups
    cleanup_old_backups
    
    # Gerar relatório
    generate_report
    
    # Cleanup final
    cleanup_temp
    
    log "INFO" "==============================================="
    log "INFO" "Processo de backup concluído com sucesso"
    log "INFO" "==============================================="
}

# ============================================================================
# EXECUÇÃO PRINCIPAL
# ============================================================================

# Tratamento de erros
trap 'error_exit "Script interrompido"' INT TERM

# Executar função principal
main

exit 0
