#!/bin/bash

################################################################################
# Script de Validação - Teste de Funcionalidade do Backup
# Descrição: Executa série de testes para validar o sistema de backup
# Uso: ./validate-backup.sh
################################################################################

set -euo pipefail

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Contadores
PASSED=0
FAILED=0
WARNED=0

# ============================================================================
# FUNÇÕES DE OUTPUT
# ============================================================================

print_header() {
    echo ""
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================================${NC}"
}

print_test() {
    echo -n -e "${BLUE}[TEST]${NC} $1 ... "
}

print_pass() {
    echo -e "${GREEN}✓ PASS${NC}"
    ((PASSED++))
}

print_fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ((FAILED++))
}

print_warn() {
    echo -e "${YELLOW}⚠ WARN${NC}: $1"
    ((WARNED++))
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_summary() {
    echo ""
    echo -e "${BLUE}================================================================${NC}"
    echo -e "Resultado: ${GREEN}${PASSED} Passou${NC} | ${RED}${FAILED} Falhou${NC} | ${YELLOW}${WARNED} Avisos${NC}"
    echo -e "${BLUE}================================================================${NC}"
    echo ""
    
    if [[ $FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ Validação concluída com sucesso!${NC}"
        return 0
    else
        echo -e "${RED}✗ Validação encontrou problemas${NC}"
        return 1
    fi
}

# ============================================================================
# TESTES DE SISTEMA
# ============================================================================

test_system_requirements() {
    print_header "Teste 1: Requisitos do Sistema"
    
    # SO
    print_test "Verificar SO Linux"
    if [[ $(uname -s) == "Linux" ]]; then
        print_pass
    else
        print_fail "SO não é Linux"
    fi
    
    # Usuário root
    print_test "Executando como root/sudo"
    if [[ $EUID -eq 0 ]]; then
        print_pass
    else
        print_warn "Não é root (alguns testes podem falhar)"
    fi
    
    # Espaço em disco
    print_test "Verificar espaço em disco (/ com mínimo 5GB)"
    DISK_AVAILABLE=$(df / | awk 'NR==2 {print $4}')
    if [[ $DISK_AVAILABLE -gt 5242880 ]]; then  # 5GB em KB
        print_pass
        print_info "Espaço disponível: $(numfmt --to=iec $((DISK_AVAILABLE*1024)) 2>/dev/null || echo $DISK_AVAILABLE KB)"
    else
        print_warn "Espaço em disco limitado: $(numfmt --to=iec $((DISK_AVAILABLE*1024)) 2>/dev/null || echo $DISK_AVAILABLE KB)"
    fi
}

# ============================================================================
# TESTES DE BINÁRIOS
# ============================================================================

test_required_binaries() {
    print_header "Teste 2: Binários Necessários"
    
    local binaries=("pg_dump" "psql" "aws" "gzip" "tar" "grep" "sed" "awk")
    
    for binary in "${binaries[@]}"; do
        print_test "Binário: $binary"
        if command -v $binary &> /dev/null; then
            local version=$($binary --version 2>&1 | head -1 || echo "disponível")
            print_pass
            print_info "  └─ $version"
        else
            print_fail "$binary não encontrado"
        fi
    done
}

# ============================================================================
# TESTES DE DIRETÓRIOS E PERMISSÕES
# ============================================================================

test_directories_and_permissions() {
    print_header "Teste 3: Diretórios e Permissões"
    
    # Backup dir
    print_test "Diretório de backup (/var/backups/ledger)"
    if [[ -d /var/backups/ledger ]]; then
        print_pass
        if [[ -w /var/backups/ledger ]]; then
            print_info "  └─ Permissão de escrita: OK"
        else
            print_warn "  └─ Sem permissão de escrita"
        fi
    else
        print_fail "Diretório não existe"
    fi
    
    # Log file
    print_test "Arquivo de log (/var/log/ledger-backup.log)"
    if [[ -f /var/log/ledger-backup.log ]]; then
        print_pass
        local log_size=$(stat -c%s /var/log/ledger-backup.log 2>/dev/null || stat -f%z /var/log/ledger-backup.log)
        print_info "  └─ Tamanho: $(numfmt --to=iec $log_size 2>/dev/null || echo $log_size bytes)"
    else
        print_warn "Arquivo de log ainda não foi criado"
    fi
    
    # Script directory
    print_test "Diretório de scripts (/opt/ledger-backup)"
    if [[ -d /opt/ledger-backup ]]; then
        print_pass
    else
        print_warn "Diretório não existe (pode ser instalado após setup)"
    fi
}

# ============================================================================
# TESTES DE USUÁRIO
# ============================================================================

test_user_configuration() {
    print_header "Teste 4: Configuração do Usuário"
    
    # Verificar usuário backup
    print_test "Usuário 'backup' existe"
    if id backup &>/dev/null; then
        print_pass
        local home_dir=$(eval echo ~backup)
        print_info "  └─ Home directory: $home_dir"
    else
        print_warn "Usuário 'backup' não existe"
    fi
    
    # Verificar cron
    print_test "Cron job configurado para usuário 'backup'"
    if crontab -u backup -l 2>/dev/null | grep -q "ledger-backup"; then
        print_pass
        print_info "  └─ Cron job encontrado:"
        crontab -u backup -l 2>/dev/null | grep "ledger-backup" | sed 's/^/     /'
    else
        print_warn "Cron job não encontrado"
    fi
}

# ============================================================================
# TESTES DE CONECTIVIDADE
# ============================================================================

test_postgresql_connection() {
    print_header "Teste 5: Conectividade PostgreSQL"
    
    local db_host="ledger-db.internal.hvt.io"
    local db_port="5432"
    local db_name="ledger_prod"
    local db_user="backup_user"
    
    # Teste de ping/conectividade
    print_test "Conectividade ao host PostgreSQL ($db_host)"
    if timeout 5 bash -c "echo > /dev/tcp/$db_host/$db_port" 2>/dev/null; then
        print_pass
    else
        print_fail "Host não acessível ($db_host:$db_port)"
    fi
    
    # Teste de conexão psql
    print_test "Conexão ao banco de dados com psql"
    if PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "$db_host" \
        -p "$db_port" \
        -U "$db_user" \
        -d "$db_name" \
        -c "SELECT version();" &>/dev/null; then
        print_pass
    else
        print_fail "Não foi possível conectar (verifique PGPASSWORD)"
    fi
    
    # Tamanho do banco
    print_test "Obter tamanho do banco de dados"
    if command -v psql &> /dev/null && [[ ! -z "${PGPASSWORD:-}" ]]; then
        local db_size=$(PGPASSWORD="${PGPASSWORD:-}" psql \
            -h "$db_host" \
            -p "$db_port" \
            -U "$db_user" \
            -d "$db_name" \
            -t \
            -c "SELECT pg_size_pretty(pg_database_size(current_database()));" 2>/dev/null || echo "N/A")
        print_pass
        print_info "  └─ Tamanho do banco: $db_size"
    else
        print_warn "Não foi possível obter tamanho do banco"
    fi
}

# ============================================================================
# TESTES AWS
# ============================================================================

test_aws_configuration() {
    print_header "Teste 6: Configuração AWS"
    
    # AWS CLI disponível
    print_test "AWS CLI instalado"
    if command -v aws &> /dev/null; then
        print_pass
    else
        print_fail "AWS CLI não encontrado"
        return
    fi
    
    # Identidade AWS
    print_test "Credenciais AWS configuradas"
    if aws sts get-caller-identity &>/dev/null; then
        print_pass
        local account=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
        print_info "  └─ Conta AWS: $account"
    else
        print_fail "Credenciais AWS não configuradas"
        return
    fi
    
    # Bucket S3
    print_test "Acesso ao bucket S3 (hvt-ledger-backups)"
    if aws s3 ls s3://hvt-ledger-backups/ &>/dev/null; then
        print_pass
    else
        print_fail "Sem acesso ao bucket S3"
        return
    fi
    
    # Listar backups
    print_test "Listar arquivos de backup no S3"
    local backup_count=$(aws s3 ls s3://hvt-ledger-backups/ | grep -c "\.sql\.gz" || echo "0")
    print_pass
    print_info "  └─ Total de backups: $backup_count"
    
    # AWS Secrets Manager
    print_test "Acesso ao AWS Secrets Manager"
    if aws secretsmanager get-secret-value \
        --secret-id ledger-db-backup-password \
        --query 'Name' \
        --output text &>/dev/null; then
        print_pass
    else
        print_warn "Não foi possível acessar secret no Secrets Manager"
    fi
}

# ============================================================================
# TESTES DE SCRIPT
# ============================================================================

test_backup_script() {
    print_header "Teste 7: Script de Backup"
    
    local script="/opt/ledger-backup/ledger-backup.sh"
    
    # Arquivo existe
    print_test "Script de backup existe"
    if [[ -f "$script" ]]; then
        print_pass
    else
        print_fail "Script não encontrado em $script"
        return
    fi
    
    # Permissões
    print_test "Script tem permissão de execução"
    if [[ -x "$script" ]]; then
        print_pass
    else
        print_fail "Script não tem permissão de execução"
    fi
    
    # Sintaxe
    print_test "Verificar sintaxe bash do script"
    if bash -n "$script" 2>/dev/null; then
        print_pass
    else
        print_fail "Erro de sintaxe no script"
    fi
}

# ============================================================================
# TESTES DE ARMAZENAMENTO
# ============================================================================

test_storage() {
    print_header "Teste 8: Espaço de Armazenamento"
    
    local backup_dir="/var/backups/ledger"
    
    # Espaço total
    print_test "Espaço total em ${backup_dir}"
    if [[ -d "$backup_dir" ]]; then
        local total_size=$(du -sh "$backup_dir" | awk '{print $1}')
        print_pass
        print_info "  └─ Tamanho total: $total_size"
    else
        print_warn "Diretório não existe"
        return
    fi
    
    # Arquivos de backup
    print_test "Contar arquivos de backup locais"
    local backup_count=$(find "$backup_dir" -maxdepth 1 -name "*.sql.gz" -type f 2>/dev/null | wc -l)
    print_pass
    print_info "  └─ Total de backups locais: $backup_count"
    
    # Arquivo mais recente
    print_test "Verificar arquivo de backup mais recente"
    local newest=$(find "$backup_dir" -maxdepth 1 -name "*.sql.gz" -type f -printf '%T@ %p\n' 2>/dev/null | \
                   sort -rn | head -1 | cut -d' ' -f2- || echo "Nenhum")
    if [[ "$newest" != "Nenhum" ]]; then
        print_pass
        local mtime=$(stat -c%y "$newest" 2>/dev/null | cut -d. -f1 || stat -f "%Sm" "$newest" 2>/dev/null | cut -d' ' -f1-4)
        print_info "  └─ Arquivo: $(basename $newest)"
        print_info "  └─ Data: $mtime"
    else
        print_warn "Nenhum arquivo de backup encontrado"
    fi
}

# ============================================================================
# TESTES DE LOGS
# ============================================================================

test_logs() {
    print_header "Teste 9: Logs de Backup"
    
    local log_file="/var/log/ledger-backup.log"
    
    # Arquivo existe
    print_test "Arquivo de log existe"
    if [[ -f "$log_file" ]]; then
        print_pass
    else
        print_warn "Arquivo de log não encontrado"
        return
    fi
    
    # Contar linhas
    print_test "Verificar entradas de log"
    local line_count=$(wc -l < "$log_file")
    print_pass
    print_info "  └─ Total de linhas: $line_count"
    
    # Últimas execuções bem-sucedidas
    print_test "Encontrar últimas execuções bem-sucedidas"
    local success_count=$(grep -c "SUCESSO" "$log_file" 2>/dev/null || echo "0")
    if [[ $success_count -gt 0 ]]; then
        print_pass
        print_info "  └─ Execuções bem-sucedidas: $success_count"
        echo "  └─ Últimas 3 execuções:"
        grep "SUCESSO" "$log_file" | tail -3 | sed 's/^/        /'
    else
        print_warn "Nenhuma execução bem-sucedida encontrada"
    fi
    
    # Erros nos logs
    print_test "Verificar erros nos logs"
    local error_count=$(grep -c "ERROR" "$log_file" 2>/dev/null || echo "0")
    if [[ $error_count -eq 0 ]]; then
        print_pass
        print_info "  └─ Nenhum erro encontrado"
    else
        print_warn "$error_count erros encontrados"
        echo "  └─ Últimos 3 erros:"
        grep "ERROR" "$log_file" | tail -3 | sed 's/^/        /'
    fi
}

# ============================================================================
# TESTES DE FUNCIONALIDADE
# ============================================================================

test_functional() {
    print_header "Teste 10: Testes Funcionais (Opcional)"
    
    echo -e "${YELLOW}Deseja executar teste funcional completo?${NC}"
    echo "Este teste executará um backup completo (pode levar minutos)"
    read -p "Digite 'sim' para continuar: " -r response
    
    if [[ "$response" != "sim" ]]; then
        print_info "Teste funcional pulado"
        return
    fi
    
    local script="/opt/ledger-backup/ledger-backup.sh"
    
    if [[ -x "$script" ]]; then
        print_test "Executar backup completo"
        if sudo -u backup "$script" >> /tmp/backup-test.log 2>&1; then
            print_pass
            print_info "Logs do teste salvos em: /tmp/backup-test.log"
        else
            print_fail "Teste funcional falhou"
            print_info "Verifique /tmp/backup-test.log para detalhes"
        fi
    else
        print_fail "Script não acessível"
    fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    print_header "VALIDAÇÃO DO SISTEMA DE BACKUP - POSTGRESQL LEDGER"
    
    print_info "Data/Hora: $(date '+%Y-%m-%d %H:%M:%S')"
    print_info "Host: $(hostname)"
    print_info "Kernel: $(uname -r)"
    
    # Executar testes
    test_system_requirements
    test_required_binaries
    test_directories_and_permissions
    test_user_configuration
    test_postgresql_connection
    test_aws_configuration
    test_backup_script
    test_storage
    test_logs
    test_functional
    
    # Resumo
    print_summary
}

# Executar
main

exit $FAILED
