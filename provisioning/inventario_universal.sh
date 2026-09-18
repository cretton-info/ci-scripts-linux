#!/bin/bash
# ==============================================================================
# SCRIPT DE INVENTÁRIO COMPLETO DE HARDWARE & OS
# Consultoria de TI & Gestão de Infraestrutura
# ==============================================================================
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || source "${SCRIPT_DIR}/lib/common.sh"

echo "=========================================================="
echo " 📊 INVENTÁRIO DE HARDWARE & SISTEMA OPERACIONAL "
echo "=========================================================="

echo -e "\n🖥️  Sistema:"
echo "  Hostname: $(hostname)"
if [ -f /etc/os-release ]; then
    (. /etc/os-release; echo "  SO: ${PRETTY_NAME:-desconhecido}")
fi
echo "  Kernel: $(uname -r)"
echo "  Arquitetura: $(uname -m)"

echo -e "\n🔩 CPU:"
if has_cmd lscpu; then
    lscpu | grep -E 'Model name|Socket|Core|Thread'
else
    grep -m1 'model name' /proc/cpuinfo
fi

echo -e "\n💾 Memória:"
free -h

echo -e "\n📀 Discos e Partições:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE 2>/dev/null || df -h

echo -e "\n🌐 Interfaces de Rede:"
ip -brief addr show 2>/dev/null

echo -e "\n📦 Pacotes / Runtimes relevantes:"
for pkg_cmd in "docker --version" "docker compose version" "git --version" "python3 --version" "node --version"; do
    if has_cmd "${pkg_cmd%% *}"; then
        printf "  %s\n" "$($pkg_cmd 2>/dev/null | head -n1)"
    fi
done

echo -e "\n=========================================================="
