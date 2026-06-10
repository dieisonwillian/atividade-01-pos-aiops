# 📦 Sistema de Backup PostgreSQL - Ledger Production

## 📋 Visão Geral

Suite completa de scripts bash para realizar backup automatizado do banco de dados PostgreSQL **ledger_prod**, fazer upload para AWS S3, e aplicar rotina de limpeza de arquivos antigos com logging detalhado.

---

## 📁 Arquivos Incluídos

### 1. **ledger-backup.sh** ⭐ (Script Principal)
Script principal que executa todo o processo de backup.

**Funcionalidades:**
- ✓ Validação de pré-requisitos
- ✓ Carregamento de credenciais do AWS Secrets Manager
- ✓ Teste de conectividade com PostgreSQL
- ✓ Execução de pg_dump com compressão gzip
- ✓ Upload para bucket S3
- ✓ Limpeza de backups com mais de 30 dias
- ✓ Logging completo em `/var/log/ledger-backup.log`

**Tamanho:** ~300 linhas | **Tempo de execução:** Depende do tamanho do banco

---

### 2. **setup-ledger-backup.sh** 🔧 (Setup Automatizado)
Script de configuração que automatiza a instalação e setup completo.

**O que faz:**
- ✓ Valida requisitos (pg_dump, AWS CLI, gzip, etc)
- ✓ Cria usuário `backup`
- ✓ Cria estrutura de diretórios
- ✓ Configura permissões de arquivo
- ✓ Configura cron job automático
- ✓ Gera template de configuração
- ✓ Oferece teste de backup

**Uso:**
```bash
sudo chmod +x setup-ledger-backup.sh
sudo ./setup-ledger-backup.sh
```

---

### 3. **validate-backup.sh** ✅ (Validação e Testes)
Script de validação para verificar integridade de todo o sistema.

**Testes incluídos:**
- ✓ Requisitos do sistema
- ✓ Disponibilidade de binários
- ✓ Diretórios e permissões
- ✓ Configuração de usuário
- ✓ Conectividade PostgreSQL
- ✓ Configuração AWS
- ✓ Integridade do script principal
- ✓ Espaço de armazenamento
- ✓ Análise de logs
- ✓ Teste funcional completo (opcional)

**Uso:**
```bash
chmod +x validate-backup.sh
./validate-backup.sh
```

---

### 4. **LEDGER-BACKUP-GUIDE.md** 📚 (Documentação Completa)
Guia detalhado com instruções passo-a-passo.

**Seções:**
1. Pré-requisitos
2. Instalação
3. Configuração
4. Execução
5. Troubleshooting
6. Monitoramento

**Como usar:**
```bash
cat LEDGER-BACKUP-GUIDE.md
# ou
less LEDGER-BACKUP-GUIDE.md
```

---

## 🚀 Quick Start

### Instalação Rápida (3 passos)

```bash
# 1. Dar permissão de execução
chmod +x ledger-backup.sh setup-ledger-backup.sh validate-backup.sh

# 2. Executar setup (como root)
sudo ./setup-ledger-backup.sh

# 3. Validar instalação
./validate-backup.sh
```

### Configuração Essencial

```bash
# 1. Criar secret no AWS Secrets Manager
aws secretsmanager create-secret \
  --name ledger-db-backup-password \
  --secret-string "sua-senha-de-backup" \
  --region us-east-1

# 2. Executar backup manualmente
sudo -u backup /opt/ledger-backup/ledger-backup.sh

# 3. Verificar logs
tail -f /var/log/ledger-backup.log
```

---

## 📊 Arquitetura e Fluxo

```
┌─────────────────────────────────────────────────────────────┐
│                    ledger-backup.sh                          │
└─────────────────────────────────────────────────────────────┘
           │
           ├─► Validar requisitos
           ├─► Carregar credenciais (AWS Secrets Manager)
           ├─► Testar conexão PostgreSQL
           │
           ├─► [ BACKUP ]
           │   ├─► pg_dump do banco ledger_prod
           │   ├─► Comprimir com gzip
           │   └─► Salvar em /var/backups/ledger/
           │
           ├─► [ UPLOAD ]
           │   └─► Upload para S3 (hvt-ledger-backups)
           │
           ├─► [ LIMPEZA ]
           │   ├─► Listar arquivos com 30+ dias
           │   ├─► Remover localmente
           │   └─► Remover do S3
           │
           └─► [ LOGGING ]
               └─► Registrar tudo em /var/log/ledger-backup.log
```

---

## ⚙️ Configuração

### Variáveis Principais

Editar `ledger-backup.sh` seção "CONFIGURAÇÕES":

```bash
# Diretórios
BACKUP_DIR="/var/backups/ledger"
LOG_FILE="/var/log/ledger-backup.log"

# PostgreSQL
DB_HOST="ledger-db.internal.hvt.io"
DB_PORT="5432"
DB_NAME="ledger_prod"
DB_USER="backup_user"

# AWS
BUCKET_NAME="hvt-ledger-backups"
AWS_REGION="us-east-1"

# Retenção
RETENTION_DAYS=30
```

### Cron Job

Padrão (diariamente às 2 AM):
```
0 2 * * * /opt/ledger-backup/ledger-backup.sh
```

Alternativas:
```bash
# 4 vezes ao dia (a cada 6 horas)
0 */6 * * * /opt/ledger-backup/ledger-backup.sh

# 3 AM diariamente
0 3 * * * /opt/ledger-backup/ledger-backup.sh

# Segundas e sextas às 1 AM
0 1 * * 1,5 /opt/ledger-backup/ledger-backup.sh
```

---

## 📝 Logging

### Estrutura do Log

```
[2024-01-15 02:00:01] [INFO] ===============================================
[2024-01-15 02:00:01] [INFO] Iniciando processo de backup do PostgreSQL
[2024-01-15 02:00:05] [INFO] Pré-requisitos validados com sucesso
[2024-01-15 02:00:10] [INFO] Backup SQL realizado com sucesso
[2024-01-15 02:00:15] [INFO] Upload para S3 realizado com sucesso
[2024-01-15 02:00:16] [INFO] Expurgo concluído: 2 arquivos removidos
[2024-01-15 02:00:20] [INFO] SUCESSO
```

### Acompanhar Logs

```bash
# Tempo real
tail -f /var/log/ledger-backup.log

# Últimas 100 linhas
tail -100 /var/log/ledger-backup.log

# Buscar erros
grep "ERROR" /var/log/ledger-backup.log

# Últimos backups bem-sucedidos
grep "SUCESSO" /var/log/ledger-backup.log | tail -5

# Backups de hoje
grep "$(date '+%Y-%m-%d')" /var/log/ledger-backup.log
```

---

## 🔒 Segurança

### IAM Role Necessária

A instância EC2 deve ter permissões:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "arn:aws:secretsmanager:*:*:secret:ledger-db-backup-password-*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
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

### Boas Práticas

- ✓ Usar AWS Secrets Manager para senha
- ✓ Não commitar senha em scripts
- ✓ Criptografar backups no S3 (AES256)
- ✓ Usar bucket privado
- ✓ Manter permissões de arquivo restritas
- ✓ Revisar logs regularmente

---

## ⚠️ Troubleshooting Comum

### "pg_dump not found"
```bash
sudo apt-get install postgresql-client
```

### "Access denied S3"
```bash
# Verificar credenciais
aws sts get-caller-identity

# Verificar permissões
aws s3 ls s3://hvt-ledger-backups/
```

### "Connection refused PostgreSQL"
```bash
# Testar conectividade
telnet ledger-db.internal.hvt.io 5432

# Verificar senha
echo $PGPASSWORD
```

### "Permission denied"
```bash
chmod 755 /opt/ledger-backup/*.sh
sudo chown root:root /opt/ledger-backup/*.sh
```

### "Cron não executou"
```bash
# Verificar cron status
sudo systemctl status cron

# Verificar crontab
crontab -u backup -l

# Logs do cron
sudo tail /var/log/syslog | grep CRON
```

Para problemas mais complexos, consultar **LEDGER-BACKUP-GUIDE.md** seção Troubleshooting.

---

## 📊 Monitoramento

### Verificação Diária

```bash
# Listar backups mais recentes
ls -lhtr /var/backups/ledger/ | tail -5

# Verificar último backup no S3
aws s3 ls s3://hvt-ledger-backups/ --recursive | tail -5

# Status do script (deve ser executado às 2 AM)
tail /var/log/ledger-backup.log
```

### Verificação Semanal

```bash
# Tamanho total
du -sh /var/backups/ledger/

# Teste de restore (em ambiente de teste)
# Restaurar um backup em DB de teste

# Validação completa
./validate-backup.sh
```

---

## 🐛 Debug e Verbose

### Executar com Debug

```bash
# Ativar modo verbose
bash -x /opt/ledger-backup/ledger-backup.sh

# Redirecionar saída
/opt/ledger-backup/ledger-backup.sh &> /tmp/backup-debug.log
tail -f /tmp/backup-debug.log
```

### Testar Conexões

```bash
# PostgreSQL
PGPASSWORD='sua-senha' psql \
  -h ledger-db.internal.hvt.io \
  -p 5432 \
  -U backup_user \
  -d ledger_prod \
  -c "SELECT version();"

# S3
aws s3 ls s3://hvt-ledger-backups/

# Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id ledger-db-backup-password
```

---

## 📞 Suporte

### Checklist de Troubleshooting

- [ ] Todos os binários instalados (`./validate-backup.sh`)
- [ ] Diretórios e permissões OK
- [ ] Credenciais AWS configuradas
- [ ] IAM role com permissões corretas
- [ ] PostgreSQL acessível
- [ ] Bucket S3 acessível
- [ ] Secret em Secrets Manager
- [ ] Cron job ativo
- [ ] Logs sendo gravados

### Contato

Para suporte:
1. Coletar logs: `tail -50 /var/log/ledger-backup.log`
2. Executar validação: `./validate-backup.sh`
3. Contatar time de TI/DevOps

---

## 📋 Checklist de Implantação

- [ ] Todos os scripts com permissão de execução
- [ ] Setup executado: `sudo ./setup-ledger-backup.sh`
- [ ] IAM role configurada na instância
- [ ] Secret criado no AWS Secrets Manager
- [ ] Usuário PostgreSQL criado com permissões
- [ ] Teste manual executado com sucesso
- [ ] Cron job validado
- [ ] Logs sendo gerados
- [ ] Validação completa: `./validate-backup.sh`
- [ ] Documentação lida: `LEDGER-BACKUP-GUIDE.md`

---

## 📈 Estatísticas

### Tamanho Típico dos Arquivos

```
Banco de dados:        ~50-100 GB
Backup (SQL):          ~15-30 GB  (compressão 3:1)
Backup (gzip):         ~5-10 GB   (compressão 10:1)
Tempo de backup:       15-45 min (depende do hardware)
```

### Custos AWS Estimados

```
S3 Standard:          $0.023 por GB/mês
S3 Storage IA:        $0.0125 por GB/mês
Data Transfer:        Entrada grátis
Secrets Manager:      $0.40 por secret/mês
```

---

## 🔄 Manutenção

### Backup de Backup

```bash
# Exportar configuração do cron
crontab -u backup -l > backup-crontab.bak

# Exportar logs
cp /var/log/ledger-backup.log ledger-backup.log.bak

# Exportar scripts
tar -czf ledger-backup-scripts.tar.gz /opt/ledger-backup/
```

### Atualizar Scripts

```bash
# Backup da versão anterior
cp /opt/ledger-backup/ledger-backup.sh /opt/ledger-backup/ledger-backup.sh.bak

# Copiar nova versão
cp ledger-backup.sh /opt/ledger-backup/ledger-backup.sh
chmod 755 /opt/ledger-backup/ledger-backup.sh

# Validar
./validate-backup.sh
```

---

## 📄 Licença e Versão

- **Versão:** 1.0
- **Data:** 2024
- **Responsável:** Equipe de TI
- **Status:** Production Ready ✓

---

## 🎯 Próximas Etapas

1. **Agora:** Revisar este README
2. **Próximo:** Ler `LEDGER-BACKUP-GUIDE.md`
3. **Depois:** Executar `sudo ./setup-ledger-backup.sh`
4. **Validar:** Executar `./validate-backup.sh`
5. **Monitor:** Acompanhar logs diariamente

---

**Última atualização:** 2024
**Status:** ✅ Pronto para produção
