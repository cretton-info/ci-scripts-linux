# Manutenção

| Script | Descrição |
|---|---|
| `manutencao_avancada.sh` | Rotina completa de manutenção (9 etapas): `apt full-upgrade`, correção de pacotes quebrados, `autoremove --purge`, limpeza do journal, Flatpak, Snap, Docker (com confirmação), lixeira/miniaturas do usuário, TRIM de SSD, e verificação de reboot pendente ao final. Requer `sudo`. |

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

**Variáveis de ambiente:**

- `JOURNAL_MAX_SIZE` — tamanho máximo dos logs do journal (padrão: `200M`)
- `JOURNAL_MAX_AGE` — idade máxima dos logs do journal (padrão: `30d`)

Bom candidato para rodar semanalmente via cron em VPS/home lab (com `--yes`).
