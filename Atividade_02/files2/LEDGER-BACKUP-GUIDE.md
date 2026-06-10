## DOCUMENTAÇÃO - Sistema de Backup PostgreSQL Ledger

### Índice
1. [Pré-requisitos](#pré-requisitos)
2. [Instalação](#instalação)
3. [Configuração](#configuração)
4. [Execução](#execução)
5. [Troubleshooting](#troubleshooting)
6. [Monitoramento](#monitoramento)

---

## Pré-requisitos

### Requisitos do Sistema
- **SO**: Linux (Ubuntu 18.04+, Debian 9+, CentOS 7+, Amazon Linux 2)
- **Permissões**: Root ou sudo sem senha
- **Espaço em disco**: Mínimo 2x o tamanho do banco de dados
- **Conectividade**: Acesso ao banco PostgreSQL e ao bucket S3

### Pacotes Necessários
```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y postgresql-client awscli curl jq

# CentOS/RHEL
sudo yum install -y postgresql awscli curl jq

# Amazon Linux 2
sudo amazon-linux-extras install -y postgresql10
sudo yum install -y awscli curl jq
```

### Permissões AWS
A instância EC2 deve ter uma IAM role com as seguintes permissões:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:*:*:secret:ledger-db-backup-password-*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::hvt-ledger-backups",
        "arn:aws:s3:::hvt-ledger-backups/*"
      ]
    }
  ]
}
```

### Requisitos de Rede
- Porta 5432 (PostgreSQL) acessível de `ledger-db.internal.hvt.io`
- Acesso ao endpoint S3 da AWS
- Acesso ao AWS Secrets Manager

---

## Instalação

### Passo 1: Preparar os Scripts

```bash
# Clonar ou baixar os scripts
git clone <repository> /opt/ledger-backup
cd /opt/ledger-backup

# Ou copiar manualmente
mkdir -p /opt/ledger-backup
cp ledger-backup.sh /opt/ledger-backup/
cp setup-ledger-backup.sh /opt/ledger-backup/
chmod +x /opt/ledger-backup/*.sh
```

### Passo 2: Executar Setup

```bash
sudo /opt/ledger-backup/setup-ledger-backup.sh
```

O script automaticamente:
- ✓ Cria usuário `backup`
- ✓ Cria diretórios necessários
- ✓ Configura permissões
- ✓ Instala cron job
- ✓ Configura log file

### Passo 3: Verificar Instalação

```bash
# Verificar diretórios
ls -la /var/backups/ledger
ls -la /opt/ledger-backup/

# Verificar usuário
id backup

# Verificar cron job
crontab -u backup -l

# Verificar log
tail -f /var/log/ledger-backup.log
```

---

## Configuração

### 1. Configurar AWS Secrets Manager

```bash
# Criar secret com a senha do banco
aws secretsmanager create-secret \
  --name ledger-db-backup-password \
  --description "Senha do usuário backup_user para PostgreSQL Ledger" \
  --secret-string "your-secure-password" \
  --region us-east-1

# Recuperar secret (teste)
aws secretsmanager get-secret-value \
  --secret-id ledger-db-backup-password \
  --region us-east-1 \
  --query 'SecretString' \
  --output text
```

### 2. Criar Usuário de Backup no PostgreSQL

```bash
# Conectar no banco como admin
psql -h ledger-db.internal.hvt.io -U postgres -d postgres

# Criar usuário
CREATE USER backup_user WITH PASSWORD 'sua-senha-segura';

# Conceder permissões
GRANT CONNECT ON DATABASE ledger_prod TO backup_user;

# Em seguida, conectar no banco ledger_prod
\c ledger_prod

# Dar permissão de leitura
GRANT USAGE ON SCHEMA public TO backup_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO backup_user;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO backup_user;

# Saída
\q
```

### 3. Testar Conectividade

```bash
# Testar acesso SSH/bastion se necessário
ssh -i sua-chave.pem ec2-user@backup-instance

# Testar conexão no banco
PGPASSWORD='sua-senha' psql \
  -h ledger-db.internal.hvt.io \
  -p 5432 \
  -U backup_user \
  -d ledger_prod \
  -c "SELECT version();"

# Testar acesso ao S3
aws s3 ls s3://hvt-ledger-backups/

# Testar acesso ao Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id ledger-db-backup-password \
  --query 'SecretString' \
  --output text
```

### 4. Configurar Variáveis de Ambiente (Opcional)

Se preferir não usar Secrets Manager, configure variável:

```bash
# Para o usuário backup
sudo su - backup
echo 'export PGPASSWORD="sua-senha-segura"' >> ~/.bashrc
source ~/.bashrc
exit
```

### 5. Ajustar Agendamento (Opcional)

Para alterar horário do cron job:

```bash
# Editar crontab do usuário backup
sudo crontab -u backup -e

# Exemplo: executar diariamente às 3 AM
0 3 * * * /opt/ledger-backup/ledger-backup.sh >> /var/log/ledger-backup.log 2>&1

# Exemplo: executar 4 vezes ao dia (a cada 6 horas)
0 */6 * * * /opt/ledger-backup/ledger-backup.sh >> /var/log/ledger-backup.log 2>&1
```

---

## Execução

### Execução Manual

```bash
# Como root
sudo /opt/ledger-backup/ledger-backup.sh

# Como usuário backup
sudo -u backup /opt/ledger-backup/ledger-backup.sh

# Com saída em tempo real
sudo -u backup /opt/ledger-backup/ledger-backup.sh | tee

# Apenas verificar logs
tail -100f /var/log/ledger-backup.log
```

### Forçar Execução Imediata

```bash
# Forçar execução do cron job agora
sudo -u backup at now < /opt/ledger-backup/ledger-backup.sh

# Ou via sudo
sudo systemctl status cron  # Verificar status do cron daemon
```

---

## Troubleshooting

### Problema: "pg_dump not found"

```bash
# Solução
sudo apt-get install postgresql-client

# Ou verificar instalação
which pg_dump
```

### Problema: "Permission denied"

```bash
# Verificar permissões
ls -la /opt/ledger-backup/ledger-backup.sh

# Corrigir
chmod 755 /opt/ledger-backup/ledger-backup.sh
chown root:root /opt/ledger-backup/ledger-backup.sh
```

### Problema: "Connection refused to PostgreSQL"

```bash
# Verificar conectividade
telnet ledger-db.internal.hvt.io 5432

# Testar com psql
psql -h ledger-db.internal.hvt.io -p 5432 -U backup_user -d ledger_prod -c "SELECT 1"

# Verificar firewall/security group
aws ec2 describe-security-groups --filters Name=group-name,Values=seu-sg

# Verificar variável PGPASSWORD
echo $PGPASSWORD  # Não deve estar vazio
```

### Problema: "Access denied for S3 bucket"

```bash
# Verificar credenciais AWS
aws sts get-caller-identity

# Verificar permissões no bucket
aws s3api list-objects-v2 --bucket hvt-ledger-backups --max-items 5

# Testar com aws s3 cp
echo "test" > /tmp/test.txt
aws s3 cp /tmp/test.txt s3://hvt-ledger-backups/test.txt
aws s3 rm s3://hvt-ledger-backups/test.txt
```

### Problema: "Secret not found in AWS Secrets Manager"

```bash
# Verificar secret
aws secretsmanager list-secrets --region us-east-1

# Recuperar valor
aws secretsmanager get-secret-value \
  --secret-id ledger-db-backup-password \
  --region us-east-1

# Criar se não existir
aws secretsmanager create-secret \
  --name ledger-db-backup-password \
  --secret-string "sua-senha" \
  --region us-east-1
```

### Problema: "Cron job não executou"

```bash
# Verificar status do cron
sudo systemctl status cron

# Reiniciar cron
sudo systemctl restart cron

# Verificar log do cron
sudo tail /var/log/syslog | grep CRON

# Verificar crontab
crontab -u backup -l

# Testar cron manualmente
sudo -u backup /opt/ledger-backup/ledger-backup.sh
```

### Problema: "Arquivo de backup muito pequeno"

```bash
# Validar banco de dados
psql -h ledger-db.internal.hvt.io -U backup_user -d ledger_prod \
  -c "SELECT pg_database_size(current_database());"

# Testar pg_dump
pg_dump -h ledger-db.internal.hvt.io -U backup_user -d ledger_prod \
  --format=plain | head -20

# Verificar espaço em disco
df -h /var/backups/ledger
```

---

## Monitoramento

### 1. Verificar Logs

```bash
# Últimas 50 linhas
tail -50 /var/log/ledger-backup.log

# Acompanhar em tempo real
tail -f /var/log/ledger-backup.log

# Buscar erros
grep "ERROR" /var/log/ledger-backup.log

# Buscar execuções bem-sucedidas
grep "SUCESSO" /var/log/ledger-backup.log

# Backup de hoje
grep "$(date '+%Y-%m-%d')" /var/log/ledger-backup.log
```

### 2. Verificar Arquivos de Backup

```bash
# Listar backups locais
ls -lh /var/backups/ledger/ | grep -E "\.sql\.gz$"

# Estatísticas de armazenamento
du -sh /var/backups/ledger/

# Backups no S3
aws s3 ls s3://hvt-ledger-backups/ --recursive --human-readable --summarize

# Backups com mais de 30 dias
aws s3api list-objects-v2 --bucket hvt-ledger-backups \
  --output table
```

### 3. Monitoramento Proativo

```bash
# Verificar se backup de hoje existe
BACKUP_DATE=$(date '+%Y%m%d')
if aws s3 ls s3://hvt-ledger-backups/ | grep "$BACKUP_DATE"; then
    echo "✓ Backup de hoje existe"
else
    echo "✗ Backup de hoje NÃO foi criado"
fi

# Script para monitoramento diário
cat > /opt/ledger-backup/check-backup.sh << 'EOF'
#!/bin/bash
BACKUP_DATE=$(date '+%Y%m%d')
if ! aws s3 ls s3://hvt-ledger-backups/ | grep "$BACKUP_DATE" > /dev/null; then
    echo "ALERTA: Backup de $BACKUP_DATE não encontrado"
    # Enviar notificação (SNS, Slack, etc)
fi
EOF

# Executar verificação diariamente
echo "0 3 * * * /opt/ledger-backup/check-backup.sh" | sudo crontab -u backup -
```

### 4. CloudWatch Integration (Opcional)

```bash
# Instalar CloudWatch Logs agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
sudo dpkg -i -E ./amazon-cloudwatch-agent.deb

# Configurar para monitorar log de backup
sudo tee /opt/aws/amazon-cloudwatch-agent/etc/config.json > /dev/null <<EOF
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/ledger-backup.log",
            "log_group_name": "/ledger/backup",
            "log_stream_name": "backup-stream"
          }
        ]
      }
    }
  }
}
EOF

# Iniciar agent
sudo systemctl start amazon-cloudwatch-agent
```

---

## Verificação Periódica Recomendada

**Diariamente:**
- [ ] Verificar se backup foi executado (ls -lh /var/backups/ledger/)
- [ ] Verificar logs para erros (grep ERROR /var/log/ledger-backup.log)

**Semanalmente:**
- [ ] Validar tamanho do backup vs tamanho do banco
- [ ] Testar restore do backup mais recente (em ambiente de teste)
- [ ] Verificar espaço em disco

**Mensalmente:**
- [ ] Revisar política de retenção
- [ ] Auditar custos de S3
- [ ] Validar backups de 30+ dias atrás foram removidos

---

## Suporte e Contato

Para problemas ou dúvidas:
- Verificar logs: `/var/log/ledger-backup.log`
- Contatar time de TI/DevOps
- Executar testes de conectividade conforme seções de troubleshooting

---

**Versão do Documento**: 1.0
**Data de Atualização**: 2024
**Responsável**: Equipe de TI
