# Ideias e Melhorias Futuras

Backlog de sugestões levantadas em revisão do repositório (2026-09-30). Não são compromissos, só
ideias anotadas para não perder — implementar sob demanda.

## 🔔 Observabilidade

- ~~**Estender o webhook de alerta além do `health_check.sh`.**~~ — feito: `alert_webhook()` movida
  pra `lib/common.sh`, agora usada também por `backup_multiperfil.sh` (origem ausente, tar falhou,
  backup corrompido), `restaurar_backup.sh` (checksum não confere, espaço insuficiente) e
  `manutencao_avancada.sh` (falha em `full-upgrade`/`install -f`).
- **Modo `--json` em `health_check.sh` e `inventario_universal.sh`**, pra alimentar um dashboard
  central (Grafana, Uptime Kuma, planilha) sem parsear texto.
- **Painel de frota** — script `status_frota.sh` que roda `health_check.sh --json` via SSH em vários
  hosts (lista em `hosts.conf`) e agrega numa tabela só.

## 🛡️ Confiabilidade

- ~~**Lock de concorrência no backup** (`flock`)~~ — feito em `backup_multiperfil.sh` (lock por
  perfil em `~/backups_sistema/.lock_<perfil>`).
- ~~**Guard-rail no `RETENCAO_DIAS`**~~ — feito em `backup_multiperfil.sh` (recusa valores < 1).
- ~~**Checar espaço livre antes de restaurar em `/`**~~ — feito em `restaurar_backup.sh` (soma o
  tamanho descompactado via `tar -tvzf` e compara com `df` do destino, nos dois modos).
- ~~**"Simulado de restauração" agendável**~~ — feito: novo script `backup/simulado_restauracao.sh`,
  não interativo, integrado ao `painel.sh` (opção 7) e ao `alert_webhook`.
- ~~**`--dry-run` na manutenção e no backup**~~ — feito nos dois: `manutencao_avancada.sh` usa
  `apt-get -s` pras etapas de pacote e só avisa nas demais; `backup_multiperfil.sh` mostra
  diretórios/exclusões/tamanho estimado sem criar nada.

## 🧪 Testes automatizados

- ~~**Testes com bats-core para `lib/common.sh`.**~~ — feito: `tests/common.bats` (18 testes) cobre
  `has_cmd`, `confirm`, `detect_real_user`, `log_*`/`die`, `require_root` e `alert_webhook`
  (incluindo cooldown), rodando no CI junto do ShellCheck. Parsing de `apps.conf` ficou de fora —
  vive em `inventario_universal.sh`, não em `lib/common.sh`; precisaria ser extraído pra uma função
  testável primeiro.

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
