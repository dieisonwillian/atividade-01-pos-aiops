# PostgreSQL Backup to AWS S3 - Documentação

## 📋 Visão Geral

Script bash automatizado que realiza:
- ✅ Backup completo do PostgreSQL com `pg_dump`
- ✅ Compressão com gzip
- ✅ Upload para bucket AWS S3
- ✅ Listagem de arquivos antigos (> 30 dias)
- ✅ Limpeza automática de backups antigos
- ✅ Logging detalhado de todas as operações

---

## 🔧 Pré-requisitos

### Pacotes Obrigatórios

```bash
# Debian/Ubuntu
sudo apt-get update
sudo apt-get install -y postgresql-client aws-cli gzip curl

# Ou manualmente:
# - postgresql-client (contém pg_dump)
# - awscli (AWS CLI v1 ou v2)
# - gzip (geralmente pré-instalado)
```

### Permissões e Diretórios

```bash
# Criar diretório de backup
sudo mkdir -p /var/backups/ledger
sudo mkdir -p /var/log

# Ajustar permissões
sudo chmod 700 /var/backups/ledger
sudo touch /var/log/ledger-backup.log
sudo chmod 644 /var/log/ledger-backup.log

# Copiar script
sudo cp postgres-backup-s3.sh /usr/local/bin/postgres-backup-s3.sh
sudo chmod 755 /usr/local/bin/postgres-backup-s3.sh
```

---

## 🔐 Configuração AWS

### 1. Criar Bucket S3

```bash
aws s3api create-bucket \
    --bucket hvt-ledger-backups \
    --region us-east-1 \
    --create-bucket-configuration LocationConstraint=us-east-1
```

### 2. Configurar Credenciais AWS

#### Opção A: Usar AWS CLI
```bash
aws configure
# Inserir: AWS Access Key ID, Secret Access Key, Region (ex: us-east-1)
```

#### Opção B: Variáveis de Ambiente
```bash
export AWS_ACCESS_KEY_ID="sua-chave-aqui"
export AWS_SECRET_ACCESS_KEY="sua-secret-aqui"
export AWS_REGION="us-east-1"
```

#### Opção C: Arquivo de Credenciais (~/.aws/credentials)
```
[default]
aws_access_key_id = sua-chave-aqui
aws_secret_access_key = sua-secret-aqui

[default]
region = us-east-1
```

### 3. Política IAM Recomendada

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::hvt-ledger-backups",
                "arn:aws:s3:::hvt-ledger-backups/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "sts:GetCallerIdentity"
            ],
            "Resource": "*"
        }
    ]
}
```

---

## 🗄️ Configuração PostgreSQL

### Variáveis de Ambiente (opcional)

```bash
# Usar defaults ou definir:
export DB_NAME="ledger"              # Nome do banco
export DB_USER="postgres"            # Usuário PostgreSQL
export DB_HOST="localhost"           # Host do PostgreSQL
export DB_PORT="5432"                # Porta
export DB_PASSWORD="sua-senha"       # Senha (opcional, usar .pgpass é mais seguro)
export AWS_REGION="us-east-1"        # Região AWS
```

### Usar .pgpass para Autenticação Segura

```bash
# Criar arquivo
nano ~/.pgpass

# Adicionar linha:
# hostname:port:database:username:password
localhost:5432:ledger:postgres:sua_senha_aqui

# Ajustar permissões
chmod 600 ~/.pgpass
```

---

## ▶️ Uso

### Execução Manual

```bash
# Com defaults
/usr/local/bin/postgres-backup-s3.sh

# Com variáveis customizadas
DB_NAME=meudb DB_USER=admin postgres-backup-s3.sh
```

### Verificar Logs

```bash
# Ver últimas linhas
tail -f /var/log/ledger-backup.log

# Ver tudo
cat /var/log/ledger-backup.log

# Filtrar por nível
grep "\[ERROR\]" /var/log/ledger-backup.log
grep "\[SUCCESS\]" /var/log/ledger-backup.log
```

---

## 📅 Automação com Cron

### Setup Cron Job

```bash
# Editar crontab
sudo crontab -e

# Ou para usuário específico:
sudo -u postgres crontab -e
```

### Exemplos de Agendamento

```bash
# Diariamente às 2 AM
0 2 * * * /usr/local/bin/postgres-backup-s3.sh

# A cada 6 horas
0 */6 * * * /usr/local/bin/postgres-backup-s3.sh

# Toda segunda-feira às 3 AM
0 3 * * 1 /usr/local/bin/postgres-backup-s3.sh

# Com redirect de logs (recomendado)
0 2 * * * /usr/local/bin/postgres-backup-s3.sh >> /var/log/ledger-backup.log 2>&1
```

### Script de Instalação do Cron

```bash
#!/bin/bash
# Instalar cron job automaticamente

CRON_CMD="/usr/local/bin/postgres-backup-s3.sh"
CRON_SCHEDULE="0 2 * * *"  # 2 AM daily

(crontab -l 2>/dev/null | grep -v "$CRON_CMD"; echo "$CRON_SCHEDULE $CRON_CMD") | crontab -
echo "Cron job instalado!"
```

---

## 📊 Monitoramento

### Verificar Status do Último Backup

```bash
# Ver últimas 10 linhas de sucesso
tail -10 /var/log/ledger-backup.log | grep SUCCESS

# Contar backups no S3
aws s3 ls s3://hvt-ledger-backups/ --human-readable --recursive

# Tamanho total dos backups
aws s3 ls s3://hvt-ledger-backups/ --human-readable --recursive --summarize
```

### Alertas por Email (Cron)

```bash
# Adicionar ao crontab com MAILTO
MAILTO=seu-email@example.com
0 2 * * * /usr/local/bin/postgres-backup-s3.sh

# Ou com script de notificação
0 2 * * * /usr/local/bin/postgres-backup-s3.sh && echo "Backup concluído" | mail -s "Backup PostgreSQL - Sucesso" seu-email@example.com || echo "Erro no backup" | mail -s "Backup PostgreSQL - ERRO" seu-email@example.com
```

---

## 🔄 Restauração

### Restaurar do S3

```bash
# Baixar backup do S3
aws s3 cp s3://hvt-ledger-backups/ledger_backup_20240119_140530.sql.gz /tmp/

# Descompactar
gunzip /tmp/ledger_backup_20240119_140530.sql.gz

# Restaurar no PostgreSQL
psql -U postgres -d ledger < /tmp/ledger_backup_20240119_140530.sql

# Ou em um novo banco
createdb novo_banco
psql -U postgres -d novo_banco < /tmp/ledger_backup_20240119_140530.sql
```

---

## 🐛 Troubleshooting

### Erro: "pg_dump não encontrado"
```bash
sudo apt-get install postgresql-client
```

### Erro: "Credenciais AWS inválidas"
```bash
# Verificar credenciais
aws sts get-caller-identity

# Reconfigurerar
aws configure
```

### Erro: "Bucket S3 não acessível"
```bash
# Testar acesso
aws s3 ls s3://hvt-ledger-backups/

# Verificar permissões IAM
aws iam get-user
```

### Erro: "Falha ao conectar ao PostgreSQL"
```bash
# Testar conexão
psql -h localhost -U postgres -d postgres -c "SELECT version();"

# Verificar credenciais .pgpass
cat ~/.pgpass
```

### Timeout de conexão
```bash
# Aumentar timeout (adicionar ao script):
export PGCONNECT_TIMEOUT=30
```

---

## 📝 Estrutura de Logs

```
[2024-01-19 14:05:30] [INFO] ========== INICIANDO BACKUP DO POSTGRESQL ==========
[2024-01-19 14:05:30] [INFO] Validando prerequisites...
[2024-01-19 14:05:31] [SUCCESS] Todos os prerequisites validados
[2024-01-19 14:05:31] [INFO] Validando conexão com PostgreSQL...
[2024-01-19 14:05:32] [SUCCESS] Conexão com PostgreSQL validada
[2024-01-19 14:05:33] [INFO] Iniciando backup do banco: ledger
[2024-01-19 14:05:45] [SUCCESS] Backup criado com sucesso: ledger_backup_20240119_140530.sql.gz (Tamanho: 245M)
[2024-01-19 14:05:46] [INFO] Iniciando upload para S3: s3://hvt-ledger-backups/ledger_backup_20240119_140530.sql.gz
[2024-01-19 14:06:15] [SUCCESS] Upload concluído com sucesso para S3
[2024-01-19 14:06:16] [INFO] Limpeza concluída: 2 arquivo(s) removido(s)
[2024-01-19 14:06:17] [SUCCESS] ========== BACKUP CONCLUÍDO COM SUCESSO ==========
```

---

## 📌 Checklist de Deployment

- [ ] Instalar pacotes: `postgresql-client`, `awscli`, `gzip`
- [ ] Criar diretório `/var/backups/ledger` com perms 700
- [ ] Criar/ajustar `/var/log/ledger-backup.log` com perms 644
- [ ] Configurar AWS CLI (`aws configure`)
- [ ] Testar acesso ao bucket S3
- [ ] Configurar `.pgpass` para autenticação segura
- [ ] Testar conexão PostgreSQL
- [ ] Executar script manualmente uma vez
- [ ] Configurar cron job
- [ ] Verificar logs (`/var/log/ledger-backup.log`)
- [ ] Testar restauração de um backup

---

## 🔗 Referências

- PostgreSQL pg_dump: https://www.postgresql.org/docs/current/app-pgdump.html
- AWS CLI S3: https://docs.aws.amazon.com/cli/latest/userguide/cli-services-s3.html
- AWS S3 Pricing: https://aws.amazon.com/s3/pricing/

---

## 📧 Suporte

Para problemas ou dúvidas, consulte os logs em `/var/log/ledger-backup.log`
