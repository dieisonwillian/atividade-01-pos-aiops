#!/bin/bash

################################################################################
# Script de Teste: PostgreSQL Backup Validation
# Descrição: Testa todos os componentes do sistema de backup
################################################################################

set -euo pipefail

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# FUNÇÕES DE OUTPUT
# ============================================================================

print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

print_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

print_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# ============================================================================
# TESTES
# ============================================================================

test_dependencies() {
    print_header "Testando Dependências"
    
    local deps=("pg_dump:postgresql-client" "aws:awscli" "gzip:gzip" "psql:postgresql-client")
    local failed=0
    
    for dep in "${deps[@]}"; do
        IFS=':' read -r cmd pkg <<< "$dep"
        
        if command -v "$cmd" &> /dev/null; then
            version=$($cmd --version 2>/dev/null || $cmd -v 2>/dev/null | head -1)
            print_pass "$cmd (versão: $version)"
        else
            print_fail "$cmd não encontrado (instalar: $pkg)"
            ((failed++))
        fi
    done
    
    return $failed
}

test_directories() {
    print_header "Testando Diretórios"
    
    local failed=0
    
    # Testar diretório de backup
    if [[ -d "/var/backups/ledger" ]]; then
        if [[ -w "/var/backups/ledger" ]]; then
            print_pass "Diretório /var/backups/ledger existe e é escrevível"
        else
            print_fail "/var/backups/ledger não é escrevível"
            ((failed++))
        fi
    else
        print_warn "Diretório /var/backups/ledger não existe (será criado)"
    fi
    
    # Testar diretório de log
    if [[ -d "/var/log" ]]; then
        print_pass "Diretório /var/log existe"
        
        if [[ -w "/var/log" ]]; then
            print_pass "/var/log é escrevível"
        else
            print_warn "/var/log pode não ser escrevível para usuário atual"
        fi
    else
        print_fail "Diretório /var/log não existe"
        ((failed++))
    fi
    
    return $failed
}

test_postgres_connection() {
    print_header "Testando Conexão PostgreSQL"
    
    local failed=0
    local db_host="${DB_HOST:-localhost}"
    local db_port="${DB_PORT:-5432}"
    local db_user="${DB_USER:-postgres}"
    local db_name="${DB_NAME:-postgres}"
    
    print_info "Parâmetros:"
    print_info "  Host: $db_host"
    print_info "  Port: $db_port"
    print_info "  User: $db_user"
    print_info "  Database: $db_name"
    echo ""
    
    if PGPASSWORD="${DB_PASSWORD:-}" psql \
        -h "$db_host" \
        -p "$db_port" \
        -U "$db_user" \
        -d "$db_name" \
        -c "SELECT version();" &> /tmp/pg_test.log; then
        
        version=$(PGPASSWORD="${DB_PASSWORD:-}" psql \
            -h "$db_host" \
            -p "$db_port" \
            -U "$db_user" \
            -d "$db_name" \
            -t -c "SELECT version();" 2>/dev/null | head -1)
        
        print_pass "Conectado ao PostgreSQL"
        print_info "Versão: $version"
    else
        print_fail "Falha ao conectar ao PostgreSQL"
        print_info "Erro: $(cat /tmp/pg_test.log | head -5)"
        ((failed++))
    fi
    
    # Listar bancos de dados
    print_info "Bancos de dados disponíveis:"
    if PGPASSWORD="${DB_PASSWORD:-}" psql \
        -h "$db_host" \
        -p "$db_port" \
        -U "$db_user" \
        -d "$db_name" \
        -l 2>/dev/null | grep -E '^\s' | head -5; then
        true
    fi
    
    return $failed
}

test_aws_credentials() {
    print_header "Testando Credenciais AWS"
    
    local failed=0
    
    if aws sts get-caller-identity &> /tmp/aws_test.log; then
        account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
        user_arn=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null)
        
        print_pass "Credenciais AWS válidas"
        print_info "Account: $account_id"
        print_info "ARN: $user_arn"
    else
        print_fail "Credenciais AWS inválidas"
        print_info "Configure com: aws configure"
        ((failed++))
    fi
    
    return $failed
}

test_s3_bucket() {
    print_header "Testando Bucket S3"
    
    local bucket="hvt-ledger-backups"
    local region="${AWS_REGION:-us-east-1}"
    local failed=0
    
    print_info "Bucket: $bucket"
    print_info "Região: $region"
    echo ""
    
    # Verificar existência do bucket
    if aws s3 ls "s3://${bucket}" --region "$region" &> /tmp/s3_test.log; then
        print_pass "Bucket $bucket é acessível"
        
        # Contar arquivos
        file_count=$(aws s3 ls "s3://${bucket}/" --region "$region" --recursive | wc -l)
        print_info "Total de arquivos: $file_count"
        
        # Tamanho total
        if command -v bc &> /dev/null; then
            total_size=$(aws s3 ls "s3://${bucket}/" --region "$region" --recursive --human-readable --summarize | grep "Total Size" | awk '{print $NF}')
            print_info "Tamanho total: $total_size"
        fi
        
        # Listar últimos 5 backups
        print_info "Últimos 5 arquivos:"
        aws s3 ls "s3://${bucket}/" --region "$region" --recursive --human-readable | tail -5 | sed 's/^/  /'
    else
        print_warn "Bucket $bucket não encontrado"
        print_info "Verificar permissões IAM"
        ((failed++))
    fi
    
    # Testar permissão de escrita
    local test_file="test_write_$(date +%s).txt"
    print_info "Testando permissão de escrita..."
    
    if echo "test" | aws s3 cp - "s3://${bucket}/${test_file}" --region "$region" &> /dev/null; then
        print_pass "Permissão de escrita validada"
        
        # Deletar arquivo de teste
        aws s3 rm "s3://${bucket}/${test_file}" --region "$region" &> /dev/null
    else
        print_fail "Sem permissão de escrita no bucket"
        ((failed++))
    fi
    
    return $failed
}

test_pg_dump() {
    print_header "Testando pg_dump"
    
    local db_host="${DB_HOST:-localhost}"
    local db_port="${DB_PORT:-5432}"
    local db_user="${DB_USER:-postgres}"
    local db_name="${DB_NAME:-ledger}"
    local failed=0
    
    print_info "Testando capacidade de backup do banco: $db_name"
    
    # Tentar fazer um backup pequeno
    if PGPASSWORD="${DB_PASSWORD:-}" pg_dump \
        -h "$db_host" \
        -p "$db_port" \
        -U "$db_user" \
        -d "$db_name" \
        --no-password \
        2> /tmp/pgdump_test.log | head -100 > /dev/null; then
        
        print_pass "pg_dump pode fazer backup do banco"
    else
        print_fail "pg_dump falhou ao fazer backup"
        print_info "Erro: $(head -5 /tmp/pgdump_test.log)"
        ((failed++))
    fi
    
    return $failed
}

test_gzip() {
    print_header "Testando Compressão Gzip"
    
    local test_file="/tmp/test_${RANDOM}.sql"
    local failed=0
    
    # Criar arquivo de teste
    echo "SELECT 1;" > "$test_file"
    
    if gzip -9 "$test_file" 2> /dev/null; then
        local compressed_file="${test_file}.gz"
        size_original=$(stat -f%z "$test_file" 2>/dev/null || stat -c%s "$test_file" 2>/dev/null || echo "N/A")
        size_compressed=$(stat -f%z "$compressed_file" 2>/dev/null || stat -c%s "$compressed_file" 2>/dev/null || echo "N/A")
        
        print_pass "Compressão gzip funcional"
        
        # Teste de descompressão
        if gunzip -t "$compressed_file" 2> /dev/null; then
            print_pass "Arquivo gzip é válido"
        else
            print_fail "Arquivo gzip é inválido"
            ((failed++))
        fi
        
        rm -f "$compressed_file"
    else
        print_fail "Erro ao comprimir arquivo"
        ((failed++))
    fi
    
    return $failed
}

test_script_file() {
    print_header "Testando Arquivo do Script"
    
    local failed=0
    local script_paths=(
        "/usr/local/bin/postgres-backup-s3.sh"
        "./postgres-backup-s3.sh"
        "../postgres-backup-s3.sh"
    )
    
    local found=0
    for path in "${script_paths[@]}"; do
        if [[ -f "$path" ]]; then
            if [[ -x "$path" ]]; then
                print_pass "Script encontrado: $path (executável)"
                found=1
                
                # Verificar sintaxe bash
                if bash -n "$path" 2> /dev/null; then
                    print_pass "Sintaxe bash válida"
                else
                    print_fail "Erro de sintaxe bash"
                    ((failed++))
                fi
            else
                print_warn "Script encontrado mas não é executável: $path"
            fi
            break
        fi
    done
    
    if [[ $found -eq 0 ]]; then
        print_fail "Script postgres-backup-s3.sh não encontrado"
        ((failed++))
    fi
    
    return $failed
}

test_permissions() {
    print_header "Testando Permissões de Arquivo"
    
    local failed=0
    
    # Verificar se pode criar arquivos em /var/backups/ledger
    if [[ -d "/var/backups/ledger" ]]; then
        local test_file="/var/backups/ledger/test_$(date +%s).txt"
        
        if touch "$test_file" 2> /dev/null; then
            print_pass "Permissão de escrita em /var/backups/ledger validada"
            rm -f "$test_file"
        else
            print_fail "Sem permissão de escrita em /var/backups/ledger"
            ((failed++))
        fi
    fi
    
    # Verificar se pode escrever em /var/log
    if [[ -w "/var/log" ]] || [[ -w "/var/log/ledger-backup.log" ]]; then
        print_pass "Permissão de escrita em /var/log validada"
    else
        print_warn "Sem permissão de escrita em /var/log (pode precisar sudo)"
    fi
    
    return $failed
}

test_cron() {
    print_header "Testando Configuração Cron"
    
    local failed=0
    
    if crontab -l 2> /dev/null | grep -q "postgres-backup-s3.sh"; then
        print_pass "Cron job encontrado"
        print_info "Cronograma:"
        crontab -l | grep "postgres-backup-s3.sh" | sed 's/^/  /'
    else
        print_warn "Nenhum cron job configurado para postgres-backup-s3.sh"
    fi
    
    return 0
}

test_system_resources() {
    print_header "Testando Recursos do Sistema"
    
    # Espaço em disco
    available_space=$(df /var/backups/ledger 2>/dev/null | tail -1 | awk '{print $4}')
    if [[ -n "$available_space" ]]; then
        if [[ $available_space -gt 1048576 ]]; then
            print_pass "Espaço em disco disponível: $(numfmt --to=iec-i --suffix=B $((available_space * 1024)) 2>/dev/null || echo '$available_space KB')"
        else
            print_warn "Espaço em disco limitado: $(numfmt --to=iec-i --suffix=B $((available_space * 1024)) 2>/dev/null || echo '$available_space KB')"
        fi
    fi
    
    # Memória disponível
    mem_available=$(free -h | grep "Mem:" | awk '{print $7}')
    print_info "Memória disponível: $mem_available"
    
    return 0
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    clear
    echo -e "${BLUE}"
    echo "╔═════════════════════════════════════════════════════════╗"
    echo "║   PostgreSQL Backup to S3 - Validação Completa         ║"
    echo "╚═════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
    
    local total_tests=0
    local passed_tests=0
    
    # Executar testes
    for test_func in test_dependencies test_directories test_postgres_connection \
                     test_aws_credentials test_s3_bucket test_pg_dump test_gzip \
                     test_script_file test_permissions test_cron test_system_resources; do
        
        ((total_tests++))
        
        if $test_func; then
            ((passed_tests++))
        fi
    done
    
    # Resumo
    print_header "Resumo dos Testes"
    
    echo "Testes executados: $total_tests"
    echo "Testes aprovados: $passed_tests"
    echo "Testes falhados: $((total_tests - passed_tests))"
    echo ""
    
    if [[ $passed_tests -eq $total_tests ]]; then
        print_pass "Todos os testes passaram! Sistema pronto."
    elif [[ $passed_tests -gt $((total_tests / 2)) ]]; then
        print_warn "Alguns testes falharam. Verifique os erros acima."
    else
        print_fail "Muitos testes falharam. Verifique a configuração."
    fi
    
    return $((total_tests - passed_tests))
}

# Executar
main "$@"
