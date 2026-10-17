# Manutenção

| Script | Descrição |
|---|---|
| `manutencao_avancada.sh` | Rotina completa de manutenção (9 etapas): `apt full-upgrade`, correção de pacotes quebrados, `autoremove --purge`, limpeza do journal, Flatpak, Snap, Docker (com confirmação), lixeira/miniaturas do usuário, TRIM de SSD, e verificação de reboot pendente ao final. Requer `sudo`. |
| `atualizar_sistema.sh` | Só `apt update` + `apt full-upgrade`, nada mais — mais leve e previsível que a manutenção completa pra deixar agendado sem supervisão. Tem assistente embutido (`--agendar`) pra criar o agendamento no crontab do root. Requer `sudo`. |

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
