  GNU nano 7.2                                                                    update_google_ips.sh
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
IPS_GBOT=$(curl -s $URL_GBOT | jq -r '.prefixes[] | [.ipv4Prefix, .ipv6Prefix] | .[] | select(. != null)')
IPS_GOOG=$(curl -s $URL_GOOG | jq -r '.prefixes[] | [.ipv4Prefix, .ipv6Prefix] | .[] | select(. != null)')

# Unir todo y limpiar duplicados
LISTA_FINAL=$(echo "127.0.0.1/8 ::1 $MIS_IPS $IPS_GBOT $IPS_GOOG" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ')

if [ -z "$IPS_GBOT" ]; then
    echo "Error: No se pudo obtener la lista de Google."
    exit 1
fi

# 1. Crear/Sobreescribir el archivo de configuración permanente
# Esto aplica a TODOS los jails porque está en la sección [DEFAULT]
echo "[DEFAULT]
ignoreip = $LISTA_FINAL" > /etc/fail2ban/jail.d/google-whitelist.local

echo "Archivo /etc/fail2ban/jail.d/google-whitelist.local actualizado."

# 2. Recargar Fail2ban para aplicar los cambios en todos los jails
echo "Recargando Fail2ban..."
fail2ban-client reload > /dev/null

echo "--------------------------------------------------------"
echo "¡LISTO! Google y tus IPs están en la lista blanca global."
echo "Fail2ban ha sido recargado correctamente."
