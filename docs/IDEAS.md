# Ideias e Melhorias Futuras

Backlog de sugestões levantadas em revisão do repositório (2026-09-30). Não são compromissos, só
ideias anotadas para não perder — implementar sob demanda.

## 🔔 Observabilidade

- ~~**Estender o webhook de alerta além do `health_check.sh`.**~~ — feito: `alert_webhook()` movida
  pra `lib/common.sh`, agora usada também por `backup_multiperfil.sh` (origem ausente, tar falhou,
  backup corrompido), `restaurar_backup.sh` (checksum não confere, espaço insuficiente) e
  `manutencao_avancada.sh` (falha em `full-upgrade`/`install -f`).
- ~~**Modo `--json` em `health_check.sh` e `inventario_universal.sh`**~~ — feito nos dois, validado
  com `jq`. `json_escape()` novo em `lib/common.sh` (trata aspas, barras, quebras de linha e
  caracteres de controle tipo cores ANSI). No caminho, achei e corrigi 3 bugs pré-existentes sem
  relação direta com o JSON: `free`/`lscpu` sem `LC_ALL=C` nunca casavam a etiqueta traduzida em
  locale pt_BR (alerta de memória e campo de CPU ficavam sempre vazios/nunca disparavam,
  silenciosamente); e `detectar_app` sem `</dev/null`+`timeout` travava o inventário inteiro se um
  app (ex.: Obsidian, Antigravity) não tratasse `--version` direito.
- ~~**Painel de frota**~~ — feito: novo script `monitoring/status_frota.sh` (opção 9 no `painel.sh`),
  agrega `health_check.sh --json` via SSH de vários hosts numa tabela só; host fora do ar não trava
  os outros. Config em `hosts.conf` (exemplo em `hosts.conf.example`).

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

- ~~**Notificação de conclusão, não só de falha**~~ — feito: `health_check.sh --resumo` manda um
  heartbeat pro webhook mesmo sem alerta, cooldown próprio via `RESUMO_COOLDOWN_HORAS` (padrão 24h,
  independente do cooldown dos alertas).
- ~~**Múltiplos destinos rclone simultâneos**~~ — feito: `RCLONE_REMOTO` aceita lista separada por
  vírgula, cada destino independente (falha num não impede os outros), alerta por destino via
  `alert_webhook`.
- ~~**`update.sh`**~~ — feito: `git pull` + `sudo ./install.sh`, com checagem de checkout git,
  aviso de alterações não commitadas, e relato correto se o `install.sh` falhar depois do pull
  (não finge sucesso).

## 📦 Distribuição / DX

- **Versionamento com tags/CHANGELOG** — saber em qual versão cada máquina de cliente está, sem
  precisar checar o SHA do commit.
- **`painel.sh` mostrar a versão instalada** — `install.sh` grava o SHA num arquivo `VERSION`.
