#!/usr/bin/env bash
# Parte 2 - Escalabilidad horizontal, con Azure CLI (pensado para Azure Cloud Shell - Bash).
# Replica la configuracion de las imagenes de images/part2 (nombres, puertos y direcciones).
# Uso:
#   ./part2-horizontal.sh infra     # load balancer, backend pool, probe, regla, VNet y NSG
#   ./part2-horizontal.sh vm 1      # crea VM1 en la zona 1 y la agrega al backend pool
#   ./part2-horizontal.sh vms       # crea VM1, VM2 y VM3 (zonas 1, 2 y 3)
#   ./part2-horizontal.sh vm 4      # punto 3: cuarta VM
#   ./part2-horizontal.sh ip        # IP publica del balanceador
#   ./part2-horizontal.sh status    # estado de las VMs y del backend pool
# Las VMs instalan y arrancan FibonacciApp solas con cloud-init (scripts/setup-vm.sh).
# Si prefiere hacerlo a mano como dice el laboratorio, exporte MANUAL_SETUP=1.
set -eo pipefail

RG="${RG:-SCALABILITY_LAB}"
LOCATION="${LOCATION:-eastus2}"
IMAGE="${IMAGE:-Ubuntu2404}"
SIZE="${SIZE:-Standard_B1ls}"
REPO_URL="${REPO_URL:-https://github.com/juanesgl/ARSW_LOAD-BALANCING_AZURE.git}"
SETUP_URL="${SETUP_URL:-https://raw.githubusercontent.com/juanesgl/ARSW_LOAD-BALANCING_AZURE/main/scripts/setup-vm.sh}"

LB="SCALABILITY_LAB_LOAD_BALANCER"
LB_IP="SCALABILITY_LAB_LOAD_BALANCER_IP"
FRONTEND="LoadBalancerFrontEnd"
POOL="SCALABILITY_LAB_BACKEND_POOL"
PROBE="SCALABILITY_LAB_HEALTH_PROBE"
RULE="SCALABILITY_LAB_LOAD_BALANCING_RULE"
VNET="SCALABILITY_LAB_VIRTUAL_NETWORK"
SUBNET="SCALABILITY_LAB_SUBNET"
NSG="LOAD_BALANCER_NSG"

ssh_args() {
  if [ -n "$SSH_KEY" ]; then echo "--ssh-key-values $SSH_KEY"; else echo "--generate-ssh-keys"; fi
}

create_infra() {
  az group create -n "$RG" -l "$LOCATION" -o none

  # 1. Load balancer publico, SKU Standard, IP estatica zone-redundant
  az network public-ip create -g "$RG" -n "$LB_IP" -l "$LOCATION" \
    --sku Standard --allocation-method Static --zone 1 2 3 -o none
  az network lb create -g "$RG" -n "$LB" -l "$LOCATION" --sku Standard \
    --public-ip-address "$LB_IP" --frontend-ip-name "$FRONTEND" \
    --backend-pool-name "$POOL" -o none

  # 3. Health probe TCP:3000, intervalo 5 s
  az network lb probe create -g "$RG" --lb-name "$LB" -n "$PROBE" \
    --protocol Tcp --port 3000 --interval 5 -o none

  # 4. Regla: puerto 80 del frontend -> 3000 de los nodos, sin persistencia de sesion
  az network lb rule create -g "$RG" --lb-name "$LB" -n "$RULE" \
    --protocol Tcp --frontend-port 80 --backend-port 3000 \
    --frontend-ip-name "$FRONTEND" --backend-pool-name "$POOL" \
    --probe-name "$PROBE" --load-distribution Default --idle-timeout 4 -o none

  # 5. Virtual network 10.1.0.0/16 con subnet 10.1.0.0/24
  az network vnet create -g "$RG" -n "$VNET" -l "$LOCATION" \
    --address-prefixes 10.1.0.0/16 --subnet-name "$SUBNET" --subnet-prefixes 10.1.0.0/24 -o none

  # NSG compartido por todas las VMs: SSH (1000) y puerto 3000 (1010)
  az network nsg create -g "$RG" -n "$NSG" -l "$LOCATION" -o none
  az network nsg rule create -g "$RG" --nsg-name "$NSG" -n default-allow-ssh --priority 1000 \
    --protocol Tcp --destination-port-ranges 22 --access Allow --direction Inbound -o none
  az network nsg rule create -g "$RG" --nsg-name "$NSG" -n Port_3000 --priority 1010 \
    --protocol Tcp --destination-port-ranges 3000 --access Allow --direction Inbound -o none

  echo "Infraestructura lista. IP del balanceador: $(lb_ip)"
}

create_vm() {
  local i="$1"
  local name="VM$i"
  local user="vm$i"
  local zone=$(( (i - 1) % 3 + 1 ))

  # IP publica Standard zone-redundant para el nodo
  az network public-ip create -g "$RG" -n "$name-ip" -l "$LOCATION" \
    --sku Standard --allocation-method Static --zone 1 2 3 -o none

  # NIC en la subnet, con el NSG compartido y dentro del backend pool del balanceador
  az network nic create -g "$RG" -n "$name-nic" -l "$LOCATION" \
    --vnet-name "$VNET" --subnet "$SUBNET" --network-security-group "$NSG" \
    --public-ip-address "$name-ip" --lb-name "$LB" --lb-address-pools "$POOL" -o none

  local custom_data=()
  if [ -z "$MANUAL_SETUP" ]; then
    local cloud_init
    cloud_init="$(mktemp)"
    cat > "$cloud_init" <<EOF
#cloud-config
runcmd:
  - [ runuser, -l, $user, -c, "curl -fsSL $SETUP_URL | bash -s -- $REPO_URL" ]
EOF
    custom_data=(--custom-data "$cloud_init")
  fi

  # shellcheck disable=SC2046
  az vm create -g "$RG" -n "$name" -l "$LOCATION" --zone "$zone" \
    --image "$IMAGE" --size "$SIZE" --nics "$name-nic" \
    --admin-username "$user" $(ssh_args) "${custom_data[@]}" -o table

  echo "$name creada en la zona $zone. SSH: ssh $user@$(az network public-ip show -g "$RG" -n "$name-ip" --query ipAddress -o tsv)"
}

lb_ip() {
  az network public-ip show -g "$RG" -n "$LB_IP" --query ipAddress -o tsv
}

case "$1" in
  infra)  create_infra ;;
  vm)     create_vm "${2:?Indique el numero de la VM, p. ej. 4}" ;;
  vms)    for i in 1 2 3; do create_vm "$i"; done ;;
  ip)     lb_ip ;;
  status)
    az vm list -g "$RG" -d --query "[].{name:name, zone:zones[0], size:hardwareProfile.vmSize, state:powerState, ip:publicIps}" -o table
    az network lb address-pool show -g "$RG" --lb-name "$LB" -n "$POOL" \
      --query "backendIPConfigurations[].id" -o tsv | awk -F/ '{print "En el pool: " $9}'
    ;;
  *)
    echo "Uso: $0 {infra|vm <n>|vms|ip|status}"
    exit 1
    ;;
esac
