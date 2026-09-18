# Manutenção

| Script | Descrição |
|---|---|
| `manutencao_avancada.sh` | Atualiza pacotes, remove dependências não usadas, limita logs do journal (200MB/30 dias) e limpa recursos Docker não utilizados (`docker system prune`). Requer `sudo`. |

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

Bom candidato para rodar semanalmente via cron em VPS/home lab (com `--yes`).
