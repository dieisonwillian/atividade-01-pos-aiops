# PostgreSQL Backup to AWS S3 - Suite Completa

Um conjunto de scripts bash para automação completa de backup do PostgreSQL com upload para AWS S3, com suporte a retenção de 30 dias e limpeza automática.

## 📦 O que está incluído

```
├── postgres-backup-s3.sh      # Script principal de backup
├── install-backup.sh          # Instalador automatizado
├── test-backup.sh             # Suite de testes e validação
├── DOCUMENTACAO.md            # Documentação completa
└── README.md                  # Este arquivo
```

---

## 🚀 Quick Start (5 minutos)

### 1. Preparar o Ambiente

```bash
# Clonar/baixar os scripts
cd /caminho/para/scripts

# Dar permissão de execução
chmod +x *.sh
```

### 2. Instalar Automaticamente

```bash
# A instalação é interativa e guiada
sudo ./install-backup.sh
```

**O instalador irá:**
- ✅ Instalar dependências (postgresql-client, awscli, gzip)
- ✅ Criar diretórios necessários
- ✅ Instalar o script principal
- ✅ Configurar AWS e PostgreSQL
- ✅ Agendar com cron (opcional)
- ✅ Executar testes

### 3. Testar a Configuração

```bash
# Validar todos os componentes
./test-backup.sh
```

### 4. Executar Primeiro Backup

```bash
# Execução manual
/usr/local/bin/postgres-backup-s3.sh

# Acompanhar logs em tempo real
tail -f /var/log/ledger-backup.log
```

---

## 📋 Scripts em Detalhes

### `postgres-backup-s3.sh` - Script Principal

**O que faz:**
1. Conecta ao PostgreSQL e faz backup com `pg_dump`
2. Compacta o dump com gzip
3. Faz upload para bucket S3 `hvt-ledger-backups`
4. Lista todos os backups no bucket
5. Identifica arquivos com mais de 30 dias
6. Deleta backups antigos (locais e S3)
7. Registra todas as operações em log

**Uso:**
```bash
# Execução simples (usa configurações padrão)
/usr/local/bin/postgres-backup-s3.sh

# Com variáveis customizadas
DB_NAME=meudb DB_USER=admin /usr/local/bin/postgres-backup-s3.sh

# Com senha (use .pgpass para maior segurança)
export DB_PASSWORD="minha_senha"
/usr/local/bin/postgres-backup-s3.sh
```

**Variáveis de Ambiente:**
```bash
DB_NAME="ledger"              # Nome do banco
DB_USER="postgres"            # Usuário PostgreSQL
DB_HOST="localhost"           # Host PostgreSQL
DB_PORT="5432"                # Porta PostgreSQL
DB_PASSWORD=""                # Senha (opcional)
AWS_REGION="us-east-1"        # Região AWS
RETENTION_DAYS="30"           # Dias de retenção
```

---

### `install-backup.sh` - Instalador Automatizado

**Funcionalidades:**
- Detecção automática de SO (Debian/Ubuntu/CentOS/RedHat)
- Instalação de dependências
- Criação de diretórios com permissões corretas
- Configuração AWS interativa
- Configuração PostgreSQL com .pgpass
- Agendamento cron customizado
- Testes de validação

**Uso:**
```bash
sudo ./install-backup.sh
```

**Fluxo interativo:**
1. Verifica root
2. Detecta SO
3. Instala dependências
4. Configura diretórios
5. Configura AWS
6. Configura PostgreSQL
7. Agenda cron (opcional)
8. Executa testes (opcional)

---

### `test-backup.sh` - Suite de Testes

**Testa:**
- ✓ Dependências instaladas (pg_dump, aws-cli, gzip)
- ✓ Diretórios criados e permissões corretas
- ✓ Conexão com PostgreSQL
- ✓ Credenciais AWS válidas
- ✓ Acesso ao bucket S3
- ✓ Capacidade de compressão gzip
- ✓ Integridade do script bash
- ✓ Configuração cron
- ✓ Recursos do sistema (disco, memória)

**Uso:**
```bash
./test-backup.sh

# Output exemplo:
# [PASS] pg_dump (versão: 14.1)
# [PASS] aws (versão: 2.13.0)
# [PASS] Conectado ao PostgreSQL
# [PASS] Credenciais AWS válidas
# [PASS] Bucket hvt-ledger-backups é acessível
```

---

## 📁 Estrutura de Diretórios e Logs

### Diretórios Criados

```
/var/backups/ledger/          # Backups locais
  └── ledger_backup_*.sql.gz

/var/log/                     # Logs
  └── ledger-backup.log
```

### Formato de Logs

```
[2024-01-19 14:05:30] [INFO] Iniciando backup do PostgreSQL
[2024-01-19 14:05:30] [INFO] Validando prerequisites...
[2024-01-19 14:05:31] [SUCCESS] Todos os prerequisites validados
[2024-01-19 14:05:33] [INFO] Iniciando backup do banco: ledger
[2024-01-19 14:05:45] [SUCCESS] Backup criado: ledger_backup_20240119_140530.sql.gz (245M)
[2024-01-19 14:05:46] [INFO] Iniciando upload para S3
[2024-01-19 14:06:15] [SUCCESS] Upload concluído com sucesso
[2024-01-19 14:06:16] [INFO] Limpeza de backups antigos...
[2024-01-19 14:06:17] [SUCCESS] Limpeza concluída: 2 arquivo(s) removido(s)
[2024-01-19 14:06:17] [SUCCESS] BACKUP CONCLUÍDO COM SUCESSO
```

---

## 🕐 Automação com Cron

### Configurar Manualmente

```bash
# Abrir editor crontab
sudo crontab -e

# Adicionar uma das linhas abaixo:

# Diariamente às 2 AM
0 2 * * * /usr/local/bin/postgres-backup-s3.sh

# A cada 6 horas
0 */6 * * * /usr/local/bin/postgres-backup-s3.sh

# Toda segunda-feira às 3 AM
0 3 * * 1 /usr/local/bin/postgres-backup-s3.sh

# Com redirecionamento de logs
0 2 * * * /usr/local/bin/postgres-backup-s3.sh >> /var/log/ledger-backup.log 2>&1
```

### Verificar Cron

```bash
# Listar cron jobs
crontab -l

# Ver logs de cron (pode variar por SO)
sudo tail -f /var/log/syslog          # Debian/Ubuntu
sudo tail -f /var/log/cron            # CentOS/RedHat
```

---

## 🔐 Autenticação Segura

### Opção 1: Arquivo .pgpass (Recomendado)

```bash
# Criar arquivo
nano ~/.pgpass

# Adicionar linha (formato: host:port:database:user:password)
localhost:5432:ledger:postgres:sua_senha_aqui

# Ajustar permissões (OBRIGATÓRIO)
chmod 600 ~/.pgpass
```

### Opção 2: Variável de Ambiente

```bash
export DB_PASSWORD="sua_senha"
/usr/local/bin/postgres-backup-s3.sh
```

### Opção 3: AWS Credentials

```bash
# Configurar AWS CLI
aws configure

# Ou definir variáveis
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_REGION="us-east-1"
```

---

## 📊 Monitoramento e Manutenção

### Ver Logs em Tempo Real

```bash
tail -f /var/log/ledger-backup.log
```

### Filtrar Logs por Tipo

```bash
# Mostrar apenas sucessos
grep "\[SUCCESS\]" /var/log/ledger-backup.log

# Mostrar apenas erros
grep "\[ERROR\]" /var/log/ledger-backup.log

# Mostrar últimos 50 registros
tail -50 /var/log/ledger-backup.log
```

### Listar Backups no S3

```bash
# Ver todos os backups
aws s3 ls s3://hvt-ledger-backups/ --human-readable --recursive

# Ver com sumário
aws s3 ls s3://hvt-ledger-backups/ --human-readable --recursive --summarize

# Ver tamanho total
aws s3 ls s3://hvt-ledger-backups/ --human-readable --recursive --summarize | grep "Total Size"
```

### Verificar Integridade de Backups

```bash
# Baixar backup
aws s3 cp s3://hvt-ledger-backups/ledger_backup_20240119_140530.sql.gz /tmp/

# Verificar integridade do gzip
gunzip -t /tmp/ledger_backup_20240119_140530.sql.gz

echo "Se não houver erro, o backup está íntegro"
```

---

## 🔄 Restauração

### Restaurar para o Mesmo Banco

```bash
# Baixar backup
aws s3 cp s3://hvt-ledger-backups/ledger_backup_YYYYMMDD_HHMMSS.sql.gz /tmp/

# Descompactar
gunzip /tmp/ledger_backup_YYYYMMDD_HHMMSS.sql.gz

# Restaurar
psql -U postgres -d ledger < /tmp/ledger_backup_YYYYMMDD_HHMMSS.sql
```

### Restaurar para Novo Banco

```bash
# Criar novo banco
createdb novo_ledger

# Restaurar
psql -U postgres -d novo_ledger < /tmp/ledger_backup_YYYYMMDD_HHMMSS.sql
```

### Restaurar Tabela Específica

```bash
# Extrair SQL e filtrar
gunzip -c backup.sql.gz | grep "CREATE TABLE tabela_name" -A 100 | head -200
```

---

## 🐛 Troubleshooting

### Erro: "pg_dump não encontrado"

```bash
# Solução: Instalar postgresql-client
sudo apt-get install postgresql-client

# Ou via instalador
sudo ./install-backup.sh
```

### Erro: "Credenciais AWS inválidas"

```bash
# Verificar credenciais
aws sts get-caller-identity

# Reconfigurar
aws configure
```

### Erro: "Bucket não acessível"

```bash
# Verificar existência
aws s3 ls s3://hvt-ledger-backups/

# Criar se não existir
aws s3api create-bucket --bucket hvt-ledger-backups --region us-east-1
```

### Erro: "Falha ao conectar PostgreSQL"

```bash
# Testar conexão
psql -h localhost -U postgres -d postgres -c "SELECT version();"

# Verificar .pgpass
cat ~/.pgpass
chmod 600 ~/.pgpass

# Verificar credenciais
echo $DB_PASSWORD
```

### Timeout de Conexão

```bash
# Aumentar timeout
export PGCONNECT_TIMEOUT=30

# Ou adicionar ao script
```

### Sem Permissão de Escrita

```bash
# Verificar permissões
ls -la /var/backups/ledger/
ls -la /var/log/

# Ajustar permissões
sudo chmod 700 /var/backups/ledger/
sudo chmod 755 /var/log/
sudo chown postgres:postgres /var/backups/ledger/
```

---

## ✅ Checklist de Validação

Antes de colocar em produção:

- [ ] Todos os testes do `test-backup.sh` passam
- [ ] Primeiro backup manual executado com sucesso
- [ ] Arquivo de backup criado em `/var/backups/ledger/`
- [ ] Arquivo de backup enviado ao S3 (`hvt-ledger-backups`)
- [ ] Logs registrados em `/var/log/ledger-backup.log`
- [ ] Cron job configurado e testado
- [ ] Restauração de backup testada
- [ ] Monitoria/alertas configurados
- [ ] Documentação revisada
- [ ] Backup fora de horas de pico agendado

---

## 📖 Documentação Adicional

Para informações mais detalhadas, consulte:
- `DOCUMENTACAO.md` - Guia completo com exemplos avançados
- Logs do sistema - `/var/log/ledger-backup.log`
- AWS S3 docs - https://docs.aws.amazon.com/s3/
- PostgreSQL docs - https://www.postgresql.org/docs/

---

## 🤝 Suporte e Contribuições

### Relatar Problemas

1. Verifique `/var/log/ledger-backup.log`
2. Execute `./test-backup.sh` para diagnósticos
3. Verifique a documentação
4. Consulte a seção de Troubleshooting

### Logs Detalhados

```bash
# Copiar logs para análise
cp /var/log/ledger-backup.log ~/ledger-backup-$(date +%Y%m%d).log

# Arquivo de teste
./test-backup.sh > ~/test-results-$(date +%Y%m%d).txt 2>&1
```

---

## 📝 Licença e Autor

Scripts fornecidos como está, para uso em produção de backup PostgreSQL.

**Última atualização:** 2024-01-19  
**Versão:** 1.0  

---

## 🎯 Roadmap Futuro

- [ ] Suporte a múltiplos bancos de dados
- [ ] Criptografia de backups em trânsito e em repouso
- [ ] Métricas e alertas via CloudWatch
- [ ] Backup incremental/diferencial
- [ ] Suporte a outras clouds (Azure, GCP)
- [ ] Verificação periódica de integridade
- [ ] Testes automáticos de restauração
- [ ] Dashboard de monitoramento

---

**Sucesso com seus backups! 🚀**
