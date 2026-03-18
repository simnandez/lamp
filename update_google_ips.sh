#!/bin/bash

# ==========================================================
# CONFIGURACIÓN DE IPS PERMITIDAS DE TERCEROS PROBANCE Y LA TEVA WEB
MIS_IPS="80.24.12.77 34.78.139.107"
# ==========================================================

# URLs oficiales de Google
URL_GBOT="https://developers.google.com/static/search/apis/ipranges/googlebot.json"
URL_GOOG="https://www.gstatic.com/ipranges/goog.json"

echo "Descargando rangos de Google..."

# Extraer IPs de ambas URLs
IPS_GBOT=$(curl -s $URL_GBOT | jq -r '.prefixes[] | [.ipv4Prefix, .ipv6Prefix] | .[] | select(. != null)' 2>/dev/null)
IPS_GOOG=$(curl -s $URL_GOOG | jq -r '.prefixes[] | [.ipv4Prefix, .ipv6Prefix] | .[] | select(. != null)' 2>/dev/null)

# Unir todo y limpiar duplicados
LISTA_FINAL=$(echo "127.0.0.1/8 ::1 $MIS_IPS $IPS_GBOT $IPS_GOOG" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ')

# Conteo para información visual
TOTAL_IPS=$(echo "$LISTA_FINAL" | wc -w)

if [ -z "$IPS_GBOT" ] || [ "$TOTAL_IPS" -lt 10 ]; then
    echo "Error: No se pudo obtener la lista de Google o la lista es demasiado corta."
    exit 1
fi

# 1. Crear/Sobreescribir el archivo de configuración permanente
# Esto aplica a TODOS los jails porque está en la sección [DEFAULT]
echo "[DEFAULT]
ignoreip = $LISTA_FINAL" > /etc/fail2ban/jail.d/google-whitelist.local

echo "Archivo /etc/fail2ban/jail.d/google-whitelist.local actualizado ($TOTAL_IPS rangos)."

# 2. Recargar Fail2ban para aplicar los cambios en todos los jails
echo "Recargando Fail2ban..."
if fail2ban-client reload > /dev/null 2>&1; then
    echo "--------------------------------------------------------"
    echo "¡LISTO! Google y tus IPs están en la lista blanca global."
    echo "Fail2ban ha sido recargado correctamente."
else
    echo "--------------------------------------------------------"
    echo "ERROR: El archivo se creó pero Fail2ban no pudo recargar."
    echo "Revisa la sintaxis con: fail2ban-client -d"
    exit 1
fi
