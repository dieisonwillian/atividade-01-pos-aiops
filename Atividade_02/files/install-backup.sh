#!/bin/bash

################################################################################
# Script de Instalação: PostgreSQL Backup to AWS S3
# Descrição: Instala e configura o sistema de backup automatizado
################################################################################

set -euo pipefail

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# FUNÇÕES UTILITÁRIAS
# ============================================================================

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Verificar se é root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Este script deve ser executado como root"
        echo "Tente: sudo $0"
        exit 1
    fi
    print_success "Verificação de root passou"
}

# Detectar sistema operacional
detect_os() {
    if [[ -f /etc/debian_version ]]; then
        OS="debian"
        print_success "Sistema operacional: Debian/Ubuntu detectado"
    elif [[ -f /etc/redhat-release ]]; then
        OS="redhat"
        print_success "Sistema operacional: RedHat/CentOS detectado"
    else
        print_error "Sistema operacional não suportado"
        exit 1
    fi
}

# ============================================================================
# INSTALAÇÃO DE DEPENDÊNCIAS
# ============================================================================

install_dependencies() {
    print_header "Instalando Dependências"
    
    if [[ "$OS" == "debian" ]]; then
        print_info "Atualizando repositórios..."
        apt-get update -qq
        
        print_info "Instalando pacotes..."
        apt-get install -y postgresql-client aws-cli gzip curl
        
    elif [[ "$OS" == "redhat" ]]; then
        print_info "Instalando pacotes..."
        yum install -y postgresql aws-cli gzip curl
    fi
    
    print_success "Dependências instaladas"
}

# Verificar dependências
verify_dependencies() {
    print_header "Verificando Dependências"
    
    local deps=("pg_dump" "aws" "gzip")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if command -v "$dep" &> /dev/null; then
            print_success "$dep instalado"
        else
            print_error "$dep não encontrado"
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Dependências faltando: ${missing[*]}"
        return 1
    fi
    
    return 0
}

# ============================================================================
# CONFIGURAÇÃO DE DIRETÓRIOS
# ============================================================================

setup_directories() {
    print_header "Configurando Diretórios"
    
    # Diretório de backup
    print_info "Criando diretório de backup..."
    mkdir -p /var/backups/ledger
    chmod 700 /var/backups/ledger
    print_success "Diretório /var/backups/ledger criado"
    
    # Diretório de logs
    print_info "Configurando diretório de logs..."
    mkdir -p /var/log
    touch /var/log/ledger-backup.log
    chmod 644 /var/log/ledger-backup.log
    print_success "Log file /var/log/ledger-backup.log criado"
}

# ============================================================================
# INSTALAÇÃO DO SCRIPT
# ============================================================================

install_script() {
    print_header "Instalando Script"
    
    if [[ ! -f "./postgres-backup-s3.sh" ]]; then
        print_error "postgres-backup-s3.sh não encontrado no diretório atual"
        return 1
    fi
    
    print_info "Copiando script para /usr/local/bin..."
    cp ./postgres-backup-s3.sh /usr/local/bin/postgres-backup-s3.sh
    chmod 755 /usr/local/bin/postgres-backup-s3.sh
    print_success "Script instalado em /usr/local/bin/postgres-backup-s3.sh"
}

# ============================================================================
# CONFIGURAÇÃO AWS
# ============================================================================

configure_aws() {
    print_header "Configuração AWS"
    
    print_info "Testando credenciais AWS existentes..."
    
    if aws sts get-caller-identity &> /dev/null; then
        print_success "Credenciais AWS já configuradas"
        
        # Verificar bucket
        read -p "Deseja verificar o bucket hvt-ledger-backups? (s/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Ss]$ ]]; then
            if aws s3 ls s3://hvt-ledger-backups/ --region us-east-1 &> /dev/null; then
                print_success "Bucket hvt-ledger-backups acessível"
            else
                print_warning "Bucket hvt-ledger-backups não acessível"
                print_info "Criando bucket..."
                aws s3api create-bucket \
                    --bucket hvt-ledger-backups \
                    --region us-east-1 \
                    --create-bucket-configuration LocationConstraint=us-east-1 || true
            fi
        fi
    else
        print_warning "Credenciais AWS não configuradas"
        read -p "Deseja configurar agora? (s/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Ss]$ ]]; then
            print_info "Execute: aws configure"
            print_info "Você pode pular esse passo pressionando Enter se usar variáveis de ambiente"
            return 0
        fi
    fi
}

# ============================================================================
# CONFIGURAÇÃO POSTGRESQL
# ============================================================================

configure_postgres() {
    print_header "Configuração PostgreSQL"
    
    print_info "Testando conexão PostgreSQL..."
    
    DB_HOST="${DB_HOST:-localhost}"
    DB_PORT="${DB_PORT:-5432}"
    DB_USER="${DB_USER:-postgres}"
    
    if PGPASSWORD="${DB_PASSWORD:-}" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "SELECT version();" &> /dev/null; then
        print_success "Conexão PostgreSQL validada"
    else
        print_warning "Não foi possível conectar ao PostgreSQL"
        print_info "Verifique as configurações:"
        echo "  Host: $DB_HOST"
        echo "  Port: $DB_PORT"
        echo "  User: $DB_USER"
    fi
    
    # Sugerir .pgpass
    print_info "Recomendação: Usar .pgpass para autenticação segura"
    if [[ ! -f ~/.pgpass ]]; then
        read -p "Deseja criar um arquivo .pgpass? (s/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Ss]$ ]]; then
            read -p "Host PostgreSQL [localhost]: " pg_host
            pg_host=${pg_host:-localhost}
            read -p "Porta PostgreSQL [5432]: " pg_port
            pg_port=${pg_port:-5432}
            read -p "Banco de dados [ledger]: " pg_db
            pg_db=${pg_db:-ledger}
            read -p "Usuário PostgreSQL [postgres]: " pg_user
            pg_user=${pg_user:-postgres}
            read -sp "Senha PostgreSQL: " pg_pass
            echo
            
            echo "${pg_host}:${pg_port}:${pg_db}:${pg_user}:${pg_pass}" > ~/.pgpass
            chmod 600 ~/.pgpass
            print_success ".pgpass criado com sucesso"
        fi
    else
        print_success ".pgpass já existe"
    fi
}

# ============================================================================
# TESTE DE EXECUÇÃO
# ============================================================================

test_script() {
    print_header "Testando Script"
    
    read -p "Deseja executar um teste do script? (s/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        print_info "Executando: /usr/local/bin/postgres-backup-s3.sh"
        echo ""
        
        if /usr/local/bin/postgres-backup-s3.sh; then
            print_success "Teste concluído com sucesso"
            echo ""
            print_info "Verificar logs em: /var/log/ledger-backup.log"
            tail -20 /var/log/ledger-backup.log
        else
            print_error "Teste falhou. Verifique os logs:"
            tail -20 /var/log/ledger-backup.log
        fi
    fi
}

# ============================================================================
# CONFIGURAÇÃO CRON
# ============================================================================

setup_cron() {
    print_header "Configuração Cron"
    
    read -p "Deseja agendar o backup com cron? (s/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        print_info "Opções de agendamento:"
        echo "1) Diariamente às 2 AM"
        echo "2) A cada 6 horas"
        echo "3) Toda segunda-feira às 3 AM"
        echo "4) Customizado"
        echo "5) Pular"
        
        read -p "Escolha uma opção [1-5]: " cron_option
        
        case $cron_option in
            1)
                CRON_SCHEDULE="0 2 * * *"
                CRON_DESC="Diariamente às 2 AM"
                ;;
            2)
                CRON_SCHEDULE="0 */6 * * *"
                CRON_DESC="A cada 6 horas"
                ;;
            3)
                CRON_SCHEDULE="0 3 * * 1"
                CRON_DESC="Toda segunda-feira às 3 AM"
                ;;
            4)
                read -p "Entre com o agendamento cron (ex: 0 2 * * *): " CRON_SCHEDULE
                CRON_DESC="Customizado: $CRON_SCHEDULE"
                ;;
            5)
                print_warning "Cron não foi configurado"
                return 0
                ;;
            *)
                print_error "Opção inválida"
                return 1
                ;;
        esac
        
        # Instalar cron job
        CRON_CMD="/usr/local/bin/postgres-backup-s3.sh"
        (crontab -l 2>/dev/null | grep -v "$CRON_CMD"; echo "$CRON_SCHEDULE $CRON_CMD") | crontab -
        
        print_success "Cron job instalado: $CRON_DESC"
        print_info "Para editar o cron novamente: crontab -e"
    fi
}

# ============================================================================
# RESUMO E FINALIZAÇÃO
# ============================================================================

print_summary() {
    print_header "Resumo da Instalação"
    
    echo "✓ Script instalado em:        /usr/local/bin/postgres-backup-s3.sh"
    echo "✓ Diretório de backup:        /var/backups/ledger"
    echo "✓ Arquivo de log:             /var/log/ledger-backup.log"
    echo "✓ Documentação:               ./DOCUMENTACAO.md"
    echo ""
    
    print_info "Próximos passos:"
    echo "1. Verificar logs: tail -f /var/log/ledger-backup.log"
    echo "2. Listar backups S3: aws s3 ls s3://hvt-ledger-backups/"
    echo "3. Testar cron: crontab -l"
    echo ""
    
    print_info "Comandos úteis:"
    echo "  Executar manualmente:  /usr/local/bin/postgres-backup-s3.sh"
    echo "  Ver logs em tempo real: tail -f /var/log/ledger-backup.log"
    echo "  Listar backups:         aws s3 ls s3://hvt-ledger-backups/"
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    clear
    print_header "Instalação: PostgreSQL Backup to AWS S3"
    
    echo "Este script irá:"
    echo "✓ Instalar dependências (postgresql-client, aws-cli, gzip)"
    echo "✓ Criar diretórios necessários"
    echo "✓ Instalar o script de backup"
    echo "✓ Configurar AWS e PostgreSQL"
    echo "✓ Agendar com cron (opcional)"
    echo ""
    
    read -p "Deseja continuar? (s/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        print_warning "Instalação cancelada"
        exit 0
    fi
    
    # Executar etapas
    check_root
    detect_os
    install_dependencies
    verify_dependencies || exit 1
    setup_directories
    install_script
    configure_aws
    configure_postgres
    setup_cron
    
    # Teste (opcional)
    test_script
    
    # Resumo
    print_summary
    
    print_header "Instalação Completa!"
    print_success "O sistema está pronto para realizar backups"
}

# Executar main
main "$@"
