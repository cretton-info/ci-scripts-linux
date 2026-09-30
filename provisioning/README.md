# Provisionamento

| Script | Descrição |
|---|---|
| `setup_pos_instalacao.sh` | Provisionamento pós-instalação (Debian/Ubuntu/Zorin): pacotes essenciais, UFW, fail2ban, Docker + Compose plugin, estrutura de diretórios padrão. Requer `sudo`. |
| `inventario_universal.sh` | Inventário de hardware e SO: CPU, GPU, memória (+ slots de RAM ocupados/livres, requer `sudo`), discos, interfaces de rede, runtimes (Docker, Compose, git, python3, node, npm), status do UFW/Tailscale/Ollama e apps desktop. Mostra o essencial na tela **e salva** `hardware_<modelo>.md` + `software_<modelo>.md` (mais completos que a tela) em `~/inventario/`. |

## Uso

```bash
sudo ~/scripts/setup_pos_instalacao.sh
bash ~/scripts/inventario_universal.sh          # sem sudo: tudo menos modelo/placa-mãe/BIOS/slots de RAM
sudo ~/scripts/inventario_universal.sh          # com sudo: inventário completo (via dmidecode)
bash ~/scripts/inventario_universal.sh --json   # saída em JSON, não grava nada em disco
```

Cada execução (exceto `--json`) sobrescreve `~/inventario/hardware_<modelo>.md` e
`~/inventario/software_<modelo>.md` (o `<modelo>` vem do `dmidecode -s system-product-name`, ou do
hostname sem `sudo`/sem dados de BIOS) — bom para levar pro Obsidian ou documentar a entrada de um
cliente. O modo `--json` é só leitura: imprime os mesmos dados em JSON pra stdout e não toca em
`~/inventario/` — pensado pra rodar com frequência num dashboard sem acumular arquivo repetido.

A lista de apps verificados vem de `apps.conf` (instalado junto em `~/scripts/apps.conf`) — edite
esse arquivo para adicionar/remover apps sem tocar no script. Uma reinstalação (`install.sh`) nunca
sobrescreve um `apps.conf` já existente. Cada app é checado por comando no PATH, pacote apt, flatpak,
snap e atalho `.desktop`, nessa ordem. Slots de memória, modelo, placa-mãe e BIOS usam `dmidecode` e
exigem root; em VMs sem BIOS/firmware completo pode não retornar dados.
