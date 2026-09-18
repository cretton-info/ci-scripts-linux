# Manutenção

| Script | Descrição |
|---|---|
| `manutencao_avancada.sh` | Atualiza pacotes, remove dependências não usadas, limita logs do journal (200MB/30 dias) e limpa recursos Docker não utilizados (`docker system prune`). Requer `sudo`. |

## Uso

```bash
sudo ~/scripts/manutencao_avancada.sh
```

Bom candidato para rodar semanalmente via cron em VPS/home lab.
