# Backup

| Script | Descrição |
|---|---|
| `backup_multiperfil.sh` | Backup rotativo em `tar.gz` por perfil (`docs`, `homelab`, `scripts`, `tudo`), com retenção configurável (`RETENCAO_DIAS`, padrão 7 dias). |
| `restaurar_backup.sh` | Restauração interativa de um backup, nos locais originais ou em diretório temporário para auditoria. Antes de sobrescrever o sistema, cria automaticamente um backup preventivo do estado atual em `~/backups_sistema/_seguranca_pre_restauracao/`. |

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
