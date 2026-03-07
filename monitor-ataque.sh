#!/bin/bash

# --- Definición de Colores ---
VERDE='\033[0;32m'
ROJO='\033[0;31m'
AMARILLO='\033[1;33m'
AZUL='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color (Reset)

LOG_PATH="/home/tienda/logs/access_log"

clear
echo -e "${AZUL}===============================================================${NC}"
echo -e "${CYAN}   SUPERVISOR DE TRÁFICO GEO-LOCALIZADO - AIRSOFT GANDIA${NC}"
echo -e "   $(date)"
echo -e "${AZUL}===============================================================${NC}"

echo -e "\n${AMARILLO}1. RESUMEN DE CARGA DEL SERVIDOR${NC}"
LOAD=$(uptime | awk -F'load average:' '{ print $2 }')
echo -e "Carga (1, 5, 15 min):${VERDE} $LOAD ${NC}"
echo "---------------------------------------------------------------"

echo -e "\n${AMARILLO}2. TOP 10 IPs ACTIVAS + PAÍS (Últimas 5000 líneas)${NC}"
echo -e "${AZUL} REQ.  |      IP        |   PAÍS${NC}"
echo "---------------------------------------------------------------"

tail -n 5000 $LOG_PATH | awk '{print $1}' | sort | uniq -c | sort -nr | head -n 10 | while read count ip; do
    # Si tiene más de 500 peticiones lo marcamos en rojo (posible bot)
    if [ "$count" -gt 500 ]; then COLOR_REQ=$ROJO; else COLOR_REQ=$VERDE; fi

    pais=$(geoiplookup $ip | awk -F', ' '{print $2}' | cut -c1-20)

    # Si el país no es Spain, lo avisamos en amarillo
    if [[ "$pais" != *"Spain"* ]]; then COLOR_PAIS=$AMARILLO; else COLOR_PAIS=$NC; fi

    printf "${COLOR_REQ}%-5s${NC}  | %-14s | ${COLOR_PAIS}%s${NC}\n" "$count" "$ip" "$pais"
done

echo "---------------------------------------------------------------"

echo -e "\n${AMARILLO}3. ESTADO DEL MURO (Baneos trabajando)${NC}"
# Solo mostramos reglas que realmente estén parando tráfico (> 0 paquetes)
sudo iptables -L INPUT -n -v | grep DROP | awk '$1 > 0' | while read pkts bytes target prot opt in out source dest; do
    printf "Bloqueados: ${ROJO}%-8s${NC} | Rango: ${CYAN}%s${NC}\n" "$pkts" "$source"
done

echo -e "${AZUL}===============================================================${NC}"
echo -e "${AMARILLO}[BOTÓN DEL PÁNICO]${NC}"
echo -e "Para banear un rango: ${ROJO}sudo iptables -I INPUT -s X.X.X.X/16 -j DROP${NC}"
