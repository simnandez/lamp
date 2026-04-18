#!/bin/bash

# --- CONFIGURACIÓN ---
LOAD_WARNING=9.0
LOAD_CRITICAL=14.0
EMAIL_ADMIN="simnandez@gmail.com"
EMAIL_SOC="javiairsoftgandia@gmail.com"
SERVICE="php7.1-fpm"
LOG_FILE="/var/log/server_monitor.log"

LOCK_WARNING="/tmp/last_warning_alert.lock"
LOCK_CRITICAL="/tmp/last_critical_alert.lock"

# Tiempos de espera (Cooldown) en segundos
WARNING_COOLDOWN=3600  # 1 hora
CRITICAL_COOLDOWN=900  # 15 min

# --- LÓGICA DE CARGA ---
CURRENT_LOAD=$(awk '{print $1}' /proc/loadavg)

# --- FUNCIÓN DE ALERTA ---
enviar_alerta() {
    TIPO=$1
    DEST=$2
    TOP_IP=$(tail -n 500 /home/tienda/logs/access_log | awk '{print $1}' | sort | uniq -c | sort -nr | head -n 1)
    PROCESOS=$(ps -eo pcpu,pmem,user,args --sort=-pcpu | head -n 10)

    CUERPO="Alerta: $TIPO
Carga actual: $CURRENT_LOAD
IP más activa (últimas 500 peticiones): $TOP_IP

Top procesos:
$PROCESOS"

echo "$CUERPO" | mail -s "[$TIPO] Servidor Airsoft" -a "From: Alertas Servidor <it@airsoftgandia.com>" "$DEST"
}

# --- PROCESO ---

NOW=$(date +%s)

# 1. NIVEL CRÍTICO
if [ $(echo "$CURRENT_LOAD > $LOAD_CRITICAL" | bc -l) -eq 1 ]; then

    # Comprobar si existe lock y si ha pasado el tiempo
    EN_COOLDOWN=0
    if [ -f "$LOCK_CRITICAL" ]; then
        LAST_TIME=$(stat -c %Y "$LOCK_CRITICAL")
        if [ $((NOW - LAST_TIME)) -lt $CRITICAL_COOLDOWN ]; then
            EN_COOLDOWN=1
        fi
    fi

    if [ $EN_COOLDOWN -eq 0 ]; then
        echo "$(date) - CRÍTICO: $CURRENT_LOAD. Reiniciando." >> $LOG_FILE
        enviar_alerta "REINICIO CRÍTICO" "$EMAIL_ADMIN,$EMAIL_SOC"
        systemctl restart $SERVICE
        touch "$LOCK_CRITICAL"
        rm -f "$LOCK_WARNING" # Permitir nuevo aviso si baja la carga
    fi

# 2. NIVEL WARNING
elif [ $(echo "$CURRENT_LOAD > $LOAD_WARNING" | bc -l) -eq 1 ]; then

    EN_COOLDOWN=0
    if [ -f "$LOCK_WARNING" ]; then
        LAST_TIME=$(stat -c %Y "$LOCK_WARNING")
        if [ $((NOW - LAST_TIME)) -lt $WARNING_COOLDOWN ]; then
            EN_COOLDOWN=1
        fi
    fi

    if [ $EN_COOLDOWN -eq 0 ]; then
        echo "$(date) - WARNING: $CURRENT_LOAD" >> $LOG_FILE
        enviar_alerta "AVISO PREVENTIVO" "$EMAIL_ADMIN"
        touch "$LOCK_WARNING"
    fi
fi
