#!/usr/bin/env bash
# Parte 1 - Escalabilidad vertical, con Azure CLI (pensado para Azure Cloud Shell - Bash).
# Equivale a los pasos 1, 6, 10 y 13 hechos en el portal.
# Uso:
#   ./part1-vertical.sh create     # crea la VM B1ls y abre el puerto 3000
#   ./part1-vertical.sh scale-up   # cambia el tamano a B2ms (la VM se reinicia)
#   ./part1-vertical.sh scale-down # vuelve a B1ls para evitar cobros
#   ./part1-vertical.sh ip         # muestra la IP publica
set -eo pipefail

RG="${RG:-SCALABILITY_LAB}"
LOCATION="${LOCATION:-eastus2}"
VM="VERTICAL-SCALABILITY"
ADMIN="scalability_lab"
IMAGE="${IMAGE:-Ubuntu2404}"

ssh_args() {
  if [ -n "$SSH_KEY" ]; then echo "--ssh-key-values $SSH_KEY"; else echo "--generate-ssh-keys"; fi
}

case "$1" in
  create)
    az group create -n "$RG" -l "$LOCATION" -o none
    # shellcheck disable=SC2046
    az vm create -g "$RG" -n "$VM" -l "$LOCATION" \
      --image "$IMAGE" --size Standard_B1ls \
      --admin-username "$ADMIN" $(ssh_args) \
      --public-ip-sku Standard -o table
    # Inbound port rule para el puerto 3000 (paso 6)
    az vm open-port -g "$RG" -n "$VM" --port 3000 --priority 1010 -o none
    echo "Conectese con: ssh $ADMIN@$(az vm show -d -g "$RG" -n "$VM" --query publicIps -o tsv)"
    echo "y dentro de la VM ejecute scripts/setup-vm.sh"
    ;;
  scale-up)
    az vm resize -g "$RG" -n "$VM" --size Standard_B2ms -o none
    az vm show -g "$RG" -n "$VM" --query hardwareProfile.vmSize -o tsv
    ;;
  scale-down)
    az vm resize -g "$RG" -n "$VM" --size Standard_B1ls -o none
    az vm show -g "$RG" -n "$VM" --query hardwareProfile.vmSize -o tsv
    ;;
  ip)
    az vm show -d -g "$RG" -n "$VM" --query publicIps -o tsv
    ;;
  *)
    echo "Uso: $0 {create|scale-up|scale-down|ip}"
    exit 1
    ;;
esac
