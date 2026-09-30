# Ideias e Melhorias Futuras

Backlog de sugestões levantadas em revisão do repositório (2026-09-30). Não são compromissos, só
ideias anotadas para não perder — implementar sob demanda.

## 🔔 Observabilidade

- **Estender o webhook de alerta além do `health_check.sh`.** Hoje só ele avisa (disco/memória/
  serviço). Extrair a lógica de envio pra `lib/common.sh` como `alert_webhook()` reutilizável e
  chamar nos pontos de falha de `backup_multiperfil.sh` (tar corrompido, origens ausentes),
  `restaurar_backup.sh` (checksum não bate) e `manutencao_avancada.sh` (falha grave de pacotes).
- **Modo `--json` em `health_check.sh` e `inventario_universal.sh`**, pra alimentar um dashboard
  central (Grafana, Uptime Kuma, planilha) sem parsear texto.
- **Painel de frota** — script `status_frota.sh` que roda `health_check.sh --json` via SSH em vários
  hosts (lista em `hosts.conf`) e agrega numa tabela só.

## 🛡️ Confiabilidade

- ~~**Lock de concorrência no backup** (`flock`)~~ — feito em `backup_multiperfil.sh` (lock por
  perfil em `~/backups_sistema/.lock_<perfil>`).
- ~~**Guard-rail no `RETENCAO_DIAS`**~~ — feito em `backup_multiperfil.sh` (recusa valores < 1).
- **Checar espaço livre antes de restaurar em `/`** em `restaurar_backup.sh` — comparar `df` com o
  tamanho do `.tar.gz` antes de extrair.
- **"Simulado de restauração" agendável** — modo não interativo que extrai o backup mais recente
  num diretório temporário, confere arquivos-chave (ex.: `etc/passwd`) e reporta por webhook.
- **`--dry-run` na manutenção e no backup**, pra rodar em cliente novo com confiança.

## 🧪 Testes automatizados

- Hoje só tem ShellCheck (lint). Funções puras em `lib/common.sh` (`detect_real_user`, `confirm`,
  `has_cmd`, parsing de `apps.conf`) são testáveis com **bats-core** sem precisar de root, rodando
  na mesma esteira do GitHub Actions.

## ✨ Funcionalidades novas

- **Notificação de conclusão, não só de falha** — resumo diário/semanal via webhook. Silêncio total
  também pode significar "o cron parou", não só "está tudo bem".
- **Múltiplos destinos rclone simultâneos** (`RCLONE_REMOTO` como lista separada por vírgula) pra
  redundância 3-2-1 real.
- **`update.sh`** — `git pull` + `sudo ./install.sh` numa linha só.

## 📦 Distribuição / DX

- **Versionamento com tags/CHANGELOG** — saber em qual versão cada máquina de cliente está, sem
  precisar checar o SHA do commit.
- **`painel.sh` mostrar a versão instalada** — `install.sh` grava o SHA num arquivo `VERSION`.
