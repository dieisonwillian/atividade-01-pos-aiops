#!/bin/bash

################################################################################
# Script de Setup - Configuração do Backup Automatizado
# Descrição: Configura o ambiente e cron job para backup automático
# Uso: sudo ./setup-ledger-backup.sh
################################################################################

set -euo pipefail

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configurações
BACKUP_SCRIPT="/opt/ledger-backup/ledger-backup.sh"
BACKUP_DIR="/var/backups/ledger"
LOG_DIR="/var/log"
LOG_FILE="${LOG_DIR}/ledger-backup.log"
BACKUP_USER="backup_user"
CRON_SCHEDULE="0 2 * * *"  # 2 AM diariamente

# ============================================================================
# FUNÇÕES
# ============================================================================

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo_error "Este script deve ser executado como root (use: sudo)"
        exit 1
    fi
}

create_directories() {
    echo_info "Criando estrutura de diretórios..."
    
    mkdir -p "${BACKUP_DIR}"
    mkdir -p "/opt/ledger-backup"
    
    echo_info "Diretórios criados com sucesso"
}

create_log_file() {
    echo_info "Configurando arquivo de log..."
    
    touch "${LOG_FILE}"
    chmod 666 "${LOG_FILE}"
    
    echo_info "Log file configurado: ${LOG_FILE}"
}

create_backup_user() {
    echo_info "Verificando usuário de backup..."
    
    if id "${BACKUP_USER}" &>/dev/null; then
        echo_warn "Usuário ${BACKUP_USER} já existe"
    else
        useradd -r -s /bin/bash -d "${BACKUP_DIR}" -m "${BACKUP_USER}"
        echo_info "Usuário ${BACKUP_USER} criado com sucesso"
    fi
}

setup_permissions() {
    echo_info "Configurando permissões de arquivo..."
    
    chown "${BACKUP_USER}:${BACKUP_USER}" "${BACKUP_DIR}"
    chmod 750 "${BACKUP_DIR}"
    
    chown "root:${BACKUP_USER}" "${LOG_FILE}"
    chmod 664 "${LOG_FILE}"
    
    chown "root:root" "${BACKUP_SCRIPT}"
    chmod 750 "${BACKUP_SCRIPT}"
    
    echo_info "Permissões configuradas com sucesso"
}

setup_aws_credentials() {
    echo_info "Configurando credenciais AWS..."
    
    # Criar diretório .aws para o usuário de backup
    mkdir -p "/var/backups/ledger/.aws"
    chown "${BACKUP_USER}:${BACKUP_USER}" "/var/backups/ledger/.aws"
    chmod 700 "/var/backups/ledger/.aws"
    
    echo_warn "Para usar AWS Secrets Manager:"
    echo_warn "1. Certifique-se de que a instância possui IAM role com permissões:"
    echo_warn "   - secretsmanager:GetSecretValue"
    echo_warn "   - s3:PutObject"
    echo_warn "   - s3:GetObject"
    echo_warn "   - s3:ListBucket"
    echo_warn ""
    echo_warn "2. Configure o arquivo de credenciais:"
    echo_warn "   /home/backup/.aws/credentials"
}

setup_sudoers() {
    echo_info "Configurando sudoers para execução sem senha..."
    
    cat > "/etc/sudoers.d/ledger-backup" << 'EOF'
# Permitir execução do backup sem senha
backup ALL=(ALL) NOPASSWD: /opt/ledger-backup/ledger-backup.sh
EOF
    
    chmod 440 "/etc/sudoers.d/ledger-backup"
    
    echo_info "Sudoers configurado com sucesso"
}

setup_cron_job() {
    echo_info "Configurando cron job para backup automático..."
    
    # Remover cron anterior se existir
    (crontab -u "${BACKUP_USER}" -l 2>/dev/null | grep -v "ledger-backup.sh" || true) | crontab -u "${BACKUP_USER}" -
    
    # Adicionar novo cron job
    (crontab -u "${BACKUP_USER}" -l 2>/dev/null || true; \
     echo "${CRON_SCHEDULE} ${BACKUP_SCRIPT} >> ${LOG_FILE} 2>&1") | crontab -u "${BACKUP_USER}" -
    
    echo_info "Cron job configurado: ${CRON_SCHEDULE}"
    echo_info "Comando: ${BACKUP_SCRIPT}"
    
    # Verificar cron job
    echo_info "Verificando cron job..."
    crontab -u "${BACKUP_USER}" -l | grep ledger-backup
}

verify_requirements() {
    echo_info "Verificando requisitos..."
    
    local missing=0
    
    # Verificar pg_dump
    if ! command -v pg_dump &> /dev/null; then
        echo_error "postgresql-client não encontrado"
        missing=$((missing + 1))
    else
        echo_info "✓ pg_dump encontrado"
    fi
    
    # Verificar aws cli
    if ! command -v aws &> /dev/null; then
        echo_error "AWS CLI não encontrado"
        missing=$((missing + 1))
    else
        echo_info "✓ AWS CLI encontrado"
    fi
    
    # Verificar gzip
    if ! command -v gzip &> /dev/null; then
        echo_error "gzip não encontrado"
        missing=$((missing + 1))
    else
        echo_info "✓ gzip encontrado"
    fi
    
    # Verificar psql
    if ! command -v psql &> /dev/null; then
        echo_error "psql não encontrado"
        missing=$((missing + 1))
    else
        echo_info "✓ psql encontrado"
    fi
    
    if [[ $missing -gt 0 ]]; then
        echo_error "Existem ${missing} requisito(s) faltando"
        echo_info "Para instalar no Ubuntu/Debian:"
        echo "  sudo apt-get update"
        echo "  sudo apt-get install -y postgresql-client awscli"
        return 1
    fi
    
    echo_info "Todos os requisitos atendidos"
    return 0
}

install_backup_script() {
    echo_info "Instalando script de backup..."
    
    # Verificar se script já existe no repositório local
    if [[ ! -f "./ledger-backup.sh" ]]; then
        echo_error "ledger-backup.sh não encontrado no diretório atual"
        echo_info "Certifique-se de executar este script no mesmo diretório que ledger-backup.sh"
        return 1
    fi
    
    cp "./ledger-backup.sh" "${BACKUP_SCRIPT}"
    chmod 755 "${BACKUP_SCRIPT}"
    
    echo_info "Script instalado em: ${BACKUP_SCRIPT}"
}

generate_config_template() {
    echo_info "Gerando template de configuração..."
    
    cat > "/opt/ledger-backup/.env.example" << 'EOF'
# Configurações de Backup PostgreSQL

# PostgreSQL
DB_HOST=ledger-db.internal.hvt.io
DB_PORT=5432
DB_NAME=ledger_prod
DB_USER=backup_user
# PGPASSWORD é carregada do AWS Secrets Manager via IAM role

# AWS
BUCKET_NAME=hvt-ledger-backups
AWS_REGION=us-east-1

# Retenção
RETENTION_DAYS=30

# Diretórios
BACKUP_DIR=/var/backups/ledger
LOG_FILE=/var/log/ledger-backup.log
EOF
    
    chmod 644 "/opt/ledger-backup/.env.example"
    echo_info "Template de configuração criado"
}

test_backup() {
    echo_info "Teste: Executando backup manualmente (pode levar alguns minutos)..."
    echo_warn "Pressione Ctrl+C para cancelar"
    sleep 3
    
    if sudo -u "${BACKUP_USER}" "${BACKUP_SCRIPT}"; then
        echo_info "✓ Teste de backup realizado com sucesso"
        return 0
    else
        echo_error "✗ Teste de backup falhou"
        return 1
    fi
}

# ============================================================================
# EXECUTAR SETUP
# ============================================================================

main() {
    echo ""
    echo "================================"
    echo "Setup - Ledger Backup"
    echo "================================"
    echo ""
    
    check_root
    verify_requirements || exit 1
    create_directories
    create_log_file
    create_backup_user
    install_backup_script
    setup_permissions
    setup_aws_credentials
    generate_config_template
    setup_cron_job
    
    echo ""
    echo "================================"
    echo -e "${GREEN}Setup concluído com sucesso!${NC}"
    echo "================================"
    echo ""
    
    echo "Próximos passos:"
    echo "1. Verificar configurações de IAM role na instância EC2"
    echo "2. Executar teste de backup (opcional):"
    echo "   sudo -u ${BACKUP_USER} ${BACKUP_SCRIPT}"
    echo ""
    echo "3. Acompanhar os logs:"
    echo "   tail -f ${LOG_FILE}"
    echo ""
    echo "Cron job configurado para executar diariamente às 2 AM"
    echo ""
}

main

exit 0
