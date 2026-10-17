# Manutenção

| Script | Descrição |
|---|---|
| `manutencao_avancada.sh` | Rotina completa de manutenção (9 etapas): `apt full-upgrade`, correção de pacotes quebrados, `autoremove --purge`, limpeza do journal, Flatpak, Snap, Docker (com confirmação), lixeira/miniaturas do usuário, TRIM de SSD, e verificação de reboot pendente ao final. Requer `sudo`. |
| `atualizar_sistema.sh` | Só `apt update` + `apt full-upgrade`, nada mais — mais leve e previsível que a manutenção completa pra deixar agendado sem supervisão. Tem assistente embutido (`--agendar`) pra criar o agendamento no crontab do root. Requer `sudo`. |
| `verificar_agendamentos.sh` | Verifica se o backup (por perfil), a atualização automática e o simulado de restauração ainda estão sendo chamados pelo cron — alerta se algum estiver atrasado ou nunca tiver rodado com sucesso apesar de agendado. Requer `sudo`. |

## Uso

```bash
sudo ~/scripts/manutencao_avancada.sh
```

O `docker system prune` pede confirmação antes de rodar (mostra `docker system df` para você decidir).
Para rodar sem interação (ex.: cron), use `--yes`/`-y` ou `AUTO_YES=1`:

```bash
sudo ~/scripts/manutencao_avancada.sh --yes
# ou
AUTO_YES=1 sudo -E ~/scripts/manutencao_avancada.sh
```

**Etapas puladas automaticamente se a ferramenta não estiver instalada:** Flatpak, Snap, Docker,
`fstrim`. Nada trava por falta de uma delas.

**Quer ver o que ele faria antes de rodar de verdade?** Use `--dry-run` — mostra cada etapa (com
simulação real do `apt-get` pra pacotes) sem instalar, remover ou apagar nada:

```bash
sudo ~/scripts/manutencao_avancada.sh --dry-run
```

**Variáveis de ambiente:**

- `JOURNAL_MAX_SIZE` — tamanho máximo dos logs do journal (padrão: `200M`)
- `JOURNAL_MAX_AGE` — idade máxima dos logs do journal (padrão: `30d`)

Bom candidato para rodar semanalmente via cron em VPS/home lab (com `--yes`).

## Atualização automática (apt update + full-upgrade), sem o resto da manutenção

Se você só quer manter os pacotes atualizados no automático, sem a limpeza completa (Docker, Flatpak,
Snap, lixeira, TRIM) — mais previsível pra deixar rodando sem supervisão, principalmente num servidor
de cliente — use o `atualizar_sistema.sh`:

```bash
sudo ~/scripts/atualizar_sistema.sh              # roda agora
sudo ~/scripts/atualizar_sistema.sh --dry-run    # só mostra o que seria atualizado
```

**Agendar (assistente interativo, cria a entrada no crontab do root):**

```bash
sudo ~/scripts/atualizar_sistema.sh --agendar
```

Pergunta a frequência (diária ou semanal, com dia da semana) e o horário, e grava a linha no
crontab do root com um marcador (`# ci-scripts-linux:atualizar_sistema`) — rodar `--agendar` de novo
substitui o agendamento anterior em vez de duplicar. Também disponível no `painel` (opção 10).

**Remover o agendamento:**

```bash
sudo ~/scripts/atualizar_sistema.sh --desagendar
```

Pra conferir o que está agendado: `sudo crontab -l | grep ci-scripts-linux:atualizar_sistema`.

## O cron ainda está rodando? (`verificar_agendamentos.sh`)

`backup_multiperfil.sh`, `atualizar_sistema.sh` e `simulado_restauracao.sh` só alertam via
`WEBHOOK_URL` quando **falham** — se o cron parar de chamá-los de vez (crontab apagado numa
reinstalação, disco cheio, permissão quebrada depois de uma atualização do sistema), nada roda e
por isso nada alerta. É o jeito mais comum de um backup "parar de funcionar" sem ninguém notar até
precisar restaurar.

`verificar_agendamentos.sh` fecha essa lacuna rodando por fora: cada um dos três scripts grava um
heartbeat (timestamp) quando termina com sucesso, e este script compara a idade do heartbeat mais
recente com um limite esperado — pro backup e pro simulado, um limite configurável; pra atualização
automática, estimado a partir da própria linha de cron criada pelo `--agendar` (diária ou semanal).
Só avalia o que encontra configurado — não precisa ter os três.

```bash
sudo ~/scripts/verificar_agendamentos.sh
```

Bom candidato pra rodar diariamente via cron, com `WEBHOOK_URL` definida:

```
0 8 * * * WEBHOOK_URL="https://seu-n8n.exemplo.com/webhook/alerta" /home/<usuario>/scripts/verificar_agendamentos.sh > /dev/null 2>&1
```

**Variáveis de ambiente:**

- `AGENDAMENTO_MAX_HORAS_BACKUP` — horas sem um novo backup bem-sucedido por perfil até alertar
  (padrão: `48`; ajuste se seu backup for semanal, não diário).
- `AGENDAMENTO_MAX_HORAS_SIMULADO` — horas sem o simulado de restauração rodar com sucesso até
  alertar (padrão: `192` = 8 dias, pra um agendamento semanal com margem).

Também disponível no `painel` (opção 11).
