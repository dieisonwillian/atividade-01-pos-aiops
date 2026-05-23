#!/bin/bash

################################################################################
# Script: PostgreSQL Backup to AWS S3
# Descrição: Realiza backup do PostgreSQL, compacta, faz upload para S3 e
#            limpa arquivos com mais de 30 dias
# Data: $(date '+%Y-%m-%d')
################################################################################

set -euo pipefail

# ============================================================================
# CONFIGURAÇÕES
# ============================================================================

# Diretórios
BACKUP_DIR="/var/backups/ledger"
LOG_FILE="/var/log/ledger-backup.log"
LOG_DIR="$(dirname "$LOG_FILE")"

# Banco de dados
DB_NAME="${DB_NAME:-ledger}"           # Nome do banco (ajustar conforme necessário)
DB_USER="${DB_USER:-postgres}"         # Usuário PostgreSQL
DB_HOST="${DB_HOST:-localhost}"        # Host do PostgreSQL
DB_PORT="${DB_PORT:-5432}"             # Porta do PostgreSQL

# AWS
S3_BUCKET="hvt-ledger-backups"
S3_REGION="${AWS_REGION:-us-east-1}"   # Ajustar conforme sua região

# Retenção
RETENTION_DAYS=30

# Timestamp
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BACKUP_FILENAME="ledger_backup_${TIMESTAMP}.sql.gz"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_FILENAME}"

# ============================================================================
# FUNÇÕES UTILITÁRIAS
# ============================================================================

# Inicializar logs
init_logging() {
    # Criar diretório de log se não existir
    if [[ ! -d "$LOG_DIR" ]]; then
        mkdir -p "$LOG_DIR"
        chmod 755 "$LOG_DIR"
    fi
    
    # Criar arquivo de log se não existir
    if [[ ! -f "$LOG_FILE" ]]; then
        touch "$LOG_FILE"
        chmod 644 "$LOG_FILE"
    fi
}

# Função de logging
log() {
    local level="$1"
    shift
    local message="$*"
    local log_timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${log_timestamp}] [${level}] ${message}" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "$@"
}

log_error() {
    log "ERROR" "$@"
}

log_warn() {
    log "WARN" "$@"
}

log_success() {
    log "SUCCESS" "$@"
}

# Validar diretório de backup
validate_backup_dir() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_info "Criando diretório de backup: $BACKUP_DIR"
        mkdir -p "$BACKUP_DIR"
        chmod 700 "$BACKUP_DIR"
    fi
    
    if [[ ! -w "$BACKUP_DIR" ]]; then
        log_error "Diretório $BACKUP_DIR não tem permissão de escrita"
        exit 1
    fi
}

# Validar prerequisites
validate_prerequisites() {
    log_info "Validando prerequisites..."
    
    # Verificar pg_dump
    if ! command -v pg_dump &> /dev/null; then
        log_error "pg_dump não encontrado. Instale postgresql-client"
        exit 1
    fi
    
    # Verificar gzip
    if ! command -v gzip &> /dev/null; then
        log_error "gzip não encontrado"
        exit 1
    fi
    
    # Verificar AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI não encontrado. Instale awscli"
        exit 1
    fi
    
    log_success "Todos os prerequisites validados"
}

# Validar conexão com PostgreSQL
validate_postgres_connection() {
    log_info "Validando conexão com PostgreSQL..."
    
    if ! PGPASSWORD="${DB_PASSWORD:-}" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "postgres" -c "SELECT version();" &> /dev/null; then
        log_error "Falha ao conectar ao PostgreSQL em $DB_HOST:$DB_PORT"
        return 1
    fi
    
    log_success "Conexão com PostgreSQL validada"
    return 0
}

# Validar credenciais AWS
validate_aws_credentials() {
    log_info "Validando credenciais AWS..."
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "Credenciais AWS inválidas ou não configuradas"
        return 1
    fi
    
    log_success "Credenciais AWS validadas"
    return 0
}

# Validar acesso ao bucket S3
validate_s3_bucket() {
    log_info "Validando acesso ao bucket S3: $S3_BUCKET"
    
    if ! aws s3 ls "s3://${S3_BUCKET}" --region "$S3_REGION" &> /dev/null; then
        log_error "Bucket $S3_BUCKET não acessível ou não existe"
        return 1
    fi
    
    log_success "Bucket S3 acessível"
    return 0
}

# ============================================================================
# FUNÇÕES PRINCIPAIS
# ============================================================================

# Realizar backup
perform_backup() {
    log_info "Iniciando backup do banco: $DB_NAME"
    
    local backup_tmp="${BACKUP_PATH}.tmp"
    
    if PGPASSWORD="${DB_PASSWORD:-}" pg_dump \
        -h "$DB_HOST" \
        -p "$DB_PORT" \
        -U "$DB_USER" \
        -d "$DB_NAME" \
        -F p \
        --verbose \
        --no-password \
        2>> "$LOG_FILE" | gzip > "$backup_tmp"; then
        
        mv "$backup_tmp" "$BACKUP_PATH"
        local file_size=$(du -h "$BACKUP_PATH" | cut -f1)
        log_success "Backup criado com sucesso: $BACKUP_FILENAME (Tamanho: $file_size)"
        return 0
    else
        log_error "Falha ao criar backup do banco de dados"
        rm -f "$backup_tmp"
        return 1
    fi
}

# Upload para S3
upload_to_s3() {
    log_info "Iniciando upload para S3: s3://$S3_BUCKET/$BACKUP_FILENAME"
    
    if aws s3 cp "$BACKUP_PATH" "s3://${S3_BUCKET}/${BACKUP_FILENAME}" \
        --region "$S3_REGION" \
        --metadata "backup-date=$(date -u +%Y-%m-%dT%H:%M:%SZ),database=$DB_NAME" \
        2>> "$LOG_FILE"; then
        
        log_success "Upload concluído com sucesso para S3"
        return 0
    else
        log_error "Falha no upload para S3"
        return 1
    fi
}

# Listar arquivos no bucket com mais de 30 dias
list_old_backups() {
    log_info "Listando backups com mais de $RETENTION_DAYS dias..."
    
    local cutoff_date=$(date -d "${RETENTION_DAYS} days ago" +%Y-%m-%d 2>/dev/null || date -v-${RETENTION_DAYS}d +%Y-%m-%d)
    
    log_info "Data de corte: $cutoff_date (arquivos anteriores a esta data serão listados)"
    
    # Listar todos os arquivos
    log_info "=== Todos os backups no bucket ==="
    aws s3 ls "s3://${S3_BUCKET}/" --region "$S3_REGION" --recursive --human-readable >> "$LOG_FILE" 2>&1
    
    # Listar apenas os antigos
    log_info "=== Backups antigos (mais de $RETENTION_DAYS dias) ==="
    aws s3api list-objects-v2 \
        --bucket "$S3_BUCKET" \
        --region "$S3_REGION" \
        --query "Contents[?LastModified<='${cutoff_date}'].[Key, Size, LastModified]" \
        --output table 2>> "$LOG_FILE" | tee -a "$LOG_FILE"
    
    return 0
}

# Limpar backups antigos
cleanup_old_backups() {
    log_info "Iniciando limpeza de backups com mais de $RETENTION_DAYS dias..."
    
    local cutoff_date=$(date -d "${RETENTION_DAYS} days ago" +%Y-%m-%d 2>/dev/null || date -v-${RETENTION_DAYS}d +%Y-%m-%d)
    local deleted_count=0
    local deleted_size=0
    
    # Obter lista de arquivos antigos
    local old_files=$(aws s3api list-objects-v2 \
        --bucket "$S3_BUCKET" \
        --region "$S3_REGION" \
        --query "Contents[?LastModified<='${cutoff_date}'].Key" \
        --output text 2>> "$LOG_FILE")
    
    if [[ -z "$old_files" ]]; then
        log_info "Nenhum backup antigo encontrado para limpeza"
        return 0
    fi
    
    # Deletar arquivos antigos
    for file in $old_files; do
        if aws s3 rm "s3://${S3_BUCKET}/${file}" --region "$S3_REGION" 2>> "$LOG_FILE"; then
            log_info "Deletado: s3://$S3_BUCKET/$file"
            ((deleted_count++))
        else
            log_warn "Falha ao deletar: s3://$S3_BUCKET/$file"
        fi
    done
    
    if [[ $deleted_count -gt 0 ]]; then
        log_success "Limpeza concluída: $deleted_count arquivo(s) removido(s)"
    else
        log_info "Nenhum arquivo foi removido"
    fi
    
    return 0
}

# Limpar backups locais antigos
cleanup_local_backups() {
    log_info "Limpando backups locais com mais de $RETENTION_DAYS dias em $BACKUP_DIR"
    
    local deleted_count=0
    
    # Encontrar e deletar arquivos antigos
    while IFS= read -r file; do
        log_info "Removendo arquivo local: $file"
        rm -f "$file"
        ((deleted_count++))
    done < <(find "$BACKUP_DIR" -maxdepth 1 -name "ledger_backup_*.sql.gz" -mtime +$((RETENTION_DAYS-1)) 2>/dev/null)
    
    if [[ $deleted_count -gt 0 ]]; then
        log_success "Limpeza local concluída: $deleted_count arquivo(s) removido(s)"
    else
        log_info "Nenhum arquivo local foi removido"
    fi
    
    return 0
}

# Gerar relatório
generate_report() {
    log_info "=== RELATÓRIO FINAL ==="
    log_info "Banco de dados: $DB_NAME"
    log_info "Arquivo de backup: $BACKUP_FILENAME"
    log_info "Caminho local: $BACKUP_PATH"
    log_info "Bucket S3: s3://$S3_BUCKET"
    log_info "Data/Hora: $(date '+%Y-%m-%d %H:%M:%S')"
    
    if [[ -f "$BACKUP_PATH" ]]; then
        local file_size=$(du -h "$BACKUP_PATH" | cut -f1)
        log_info "Tamanho do arquivo: $file_size"
    fi
}

# Função de erro (cleanup)
error_cleanup() {
    log_error "Erro detectado no script"
    
    # Limpar arquivo temporário se existir
    if [[ -f "${BACKUP_PATH}.tmp" ]]; then
        log_warn "Removendo arquivo temporário..."
        rm -f "${BACKUP_PATH}.tmp"
    fi
}

# ============================================================================
# EXECUÇÃO PRINCIPAL
# ============================================================================

main() {
    log_info "========== INICIANDO BACKUP DO POSTGRESQL =========="
    
    # Trap para erros
    trap error_cleanup ERR
    
    # Validações iniciais
    init_logging
    validate_backup_dir
    validate_prerequisites
    
    # Validações de conexão
    if ! validate_postgres_connection; then
        log_error "Não foi possível conectar ao PostgreSQL. Abortando."
        exit 1
    fi
    
    if ! validate_aws_credentials; then
        log_error "Credenciais AWS inválidas. Abortando."
        exit 1
    fi
    
    if ! validate_s3_bucket; then
        log_error "Bucket S3 não acessível. Abortando."
        exit 1
    fi
    
    # Executar backup
    if ! perform_backup; then
        log_error "Falha ao realizar backup. Abortando."
        exit 1
    fi
    
    # Upload para S3
    if ! upload_to_s3; then
        log_error "Falha no upload para S3. Abortando."
        exit 1
    fi
    
    # Listar backups antigos
    list_old_backups
    
    # Limpeza
    cleanup_old_backups
    cleanup_local_backups
    
    # Relatório
    generate_report
    
    log_info "========== BACKUP CONCLUÍDO COM SUCESSO =========="
    exit 0
}

# Executar main
main "$@"
