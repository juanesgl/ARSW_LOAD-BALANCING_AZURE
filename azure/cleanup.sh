#!/usr/bin/env bash
# Elimina el grupo de recursos completo (VMs, discos, IPs, load balancer, VNet...) para no generar cobros.
set -eo pipefail

RG="${RG:-SCALABILITY_LAB}"
az group delete -n "$RG" --yes --no-wait
echo "Eliminacion de $RG en curso. Verifique con: az group exists -n $RG"
