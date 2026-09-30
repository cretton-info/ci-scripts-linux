# Backup

| Script | Descrição |
|---|---|
| `backup_multiperfil.sh` | Backup rotativo em `tar.gz` por perfil (`docs`, `homelab`, `scripts`, `tudo`), com retenção configurável (`RETENCAO_DIAS`, padrão 7 dias). |
| `restaurar_backup.sh` | Restauração interativa de um backup, nos locais originais ou em diretório temporário para auditoria. Antes de sobrescrever o sistema, cria automaticamente um backup preventivo do estado atual em `~/backups_sistema/_seguranca_pre_restauracao/`, com retenção própria (`RETENCAO_PREVENTIVOS_DIAS`, padrão 30 dias). |

> **Atenção:** os argumentos `docs` e `tudo` gravam, respectivamente, nas pastas `documentos/` e
> `completo/` dentro de `~/backups_sistema/` (não `docs/` nem `tudo/`). `homelab` e `scripts` geram
> pastas com o mesmo nome do argumento. É o nome da pasta que aparece na hora de restaurar.

## Uso

```bash
# Backup direto por parâmetro (ideal para cron)
sudo ~/scripts/backup_multiperfil.sh homelab

# Menu interativo
sudo ~/scripts/backup_multiperfil.sh --menu

# Restauração (sempre requer sudo)
sudo ~/scripts/restaurar_backup.sh
```

## Exemplo de crontab

```
0 3 * * * /home/<usuario>/scripts/backup_multiperfil.sh homelab > /dev/null 2>&1
0 12 * * * /home/<usuario>/scripts/backup_multiperfil.sh docs > /dev/null 2>&1
```

## Atenção

Restaurar no modo "locais originais" sobrescreve arquivos do sistema em `/`. O script sempre lista o
conteúdo do backup e pede confirmação explícita antes de prosseguir, além de gerar um backup preventivo
automático — mas revise o backup preventivo salvo antes de descartá-lo.

Os preventivos em `~/backups_sistema/_seguranca_pre_restauracao/` são limpos automaticamente depois de
`RETENCAO_PREVENTIVOS_DIAS` dias (padrão: 30). Para mudar:

```bash
RETENCAO_PREVENTIVOS_DIAS=60 sudo -E ~/scripts/restaurar_backup.sh
```

## Verificação de integridade

Todo backup criado pelo `backup_multiperfil.sh` é testado (`tar -tzf`) e ganha um checksum
(`<arquivo>.tar.gz.sha256`) logo após ser gravado — se o `.tar.gz` sair corrompido, o script apaga o
arquivo e falha na hora, em vez de deixar um backup ruim para trás.

O `restaurar_backup.sh` confere esse checksum antes de tocar em qualquer coisa e recusa restaurar um
backup que não bate. Backups antigos sem `.sha256` (de antes dessa verificação existir) caem
automaticamente para um teste de leitura do `tar` como fallback.

## Exclusão de padrões

O backup já exclui automaticamente `.git`, `node_modules`, `__pycache__` e `.cache` de qualquer
origem incluída. Para excluir padrões extras (ex.: logs, caches específicos de um cliente), use
`EXCLUDE_PATTERNS` com padrões separados por vírgula:

```bash
EXCLUDE_PATTERNS="*.log,tmp/*" sudo -E ~/scripts/backup_multiperfil.sh homelab
```

(`sudo -E` é necessário para a variável de ambiente passar para o processo com privilégio.)

## Backup remoto (rclone)

Se `RCLONE_REMOTO` estiver definida, o `backup_multiperfil.sh` envia o `.tar.gz` e o `.sha256`
recém-criados para esse destino logo após a verificação de integridade local, via
[rclone](https://rclone.org/) (`rclone copy`, não apaga nada no remoto). Uma falha no envio só
gera um aviso — o backup local já está garantido antes de tentar o remoto.

```bash
# Configura o remote uma vez (S3-compatível, SFTP, WebDAV, Google Drive, etc.)
rclone config

# Testa manualmente
RCLONE_REMOTO="b2:meu-bucket/cliente-x" sudo -E ~/scripts/backup_multiperfil.sh homelab
```

No crontab:

```
0 3 * * * RCLONE_REMOTO="b2:meu-bucket/cliente-x" /home/<usuario>/scripts/backup_multiperfil.sh homelab > /dev/null 2>&1
```

O arquivo acaba em `<remote>/<perfil>/`, ex.: `b2:meu-bucket/cliente-x/homelab/`.

Flags extras do rclone (ex.: `--transfers 4`) via `RCLONE_FLAGS`:

```bash
RCLONE_REMOTO="b2:meu-bucket/cliente-x" RCLONE_FLAGS="--transfers 4" sudo -E ~/scripts/backup_multiperfil.sh homelab
```

Requer o binário `rclone` instalado e configurado (`rclone config`) no mesmo usuário/root que roda
o script — se não estiver instalado, o script apenas avisa e segue com o backup local normalmente.

**Passo a passo completo pra configurar o Google Drive** (criação do remote, autenticação sem
navegador no servidor, restringir a uma pasta, criptografia opcional):
[docs/BACKUP_REMOTO.md](../docs/BACKUP_REMOTO.md).
