#!/bin/bash

# ==========================================================
# CONFIGURACIÓN DE TERCEROS (PAGOS Y LOGÍSTICA)
# ==========================================================
# IPs fijas de seQura
IPS_SEQURA="34.253.159.179 34.252.147.155 52.211.243.177"

# Rangos de PayPal (Global + Europa + IPN)
IPS_PAYPAL="173.0.80.0/20 66.211.168.0/22 64.4.240.0/21 66.211.160.0/20 91.243.0.0/23 185.177.52.0/22"

# Rangos de Redsys (Pasarela de tarjetas España - Servired/4B)
IPS_REDSYS="193.16.160.0/24 195.76.9.0/24 195.76.29.0/24 194.224.159.0/24 82.223.1.0/24"

# Nuestra infraestructura y colaboradores
MIS_IPS="80.24.12.77 34.78.139.107 $IPS_SEQURA $IPS_PAYPAL $IPS_REDSYS"

# URLs oficiales de Google
URL_GBOT="https://developers.google.com/static/search/apis/ipranges/googlebot.json"
URL_GOOG="https://www.gstatic.com/ipranges/goog.json"
URL_GUSER="https://developers.google.com/crawling/ipranges/user-triggered-agents.json"

echo "Descargando rangos de Google (Bot, Cloud y User-Triggered)..."

# Extraer IPs de las tres URLs
IPS_GBOT=$(curl -s $URL_GBOT | jq -r '.prefixes[] | [.ipv4Prefix, .ipv6Prefix] | .[] | select(. != null)' 2>/dev/null)
IPS_GOOG=$(curl -s $URL_GOOG | jq -r '.prefixes[] | [.ipv4Prefix, .ipv6Prefix] | .[] | select(. != null)' 2>/dev/null)
IPS_GUSER=$(curl -s $URL_GUSER | jq -r '.prefixes[] | [.ipv4Prefix, .ipv6Prefix] | .[] | select(. != null)' 2>/dev/null)

# Unir todo y limpiar duplicados
LISTA_FINAL=$(echo "127.0.0.1/8 ::1 $MIS_IPS $IPS_GBOT $IPS_GOOG $IPS_GUSER" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ')

# Conteo para información visual
TOTAL_IPS=$(echo "$LISTA_FINAL" | wc -w)

if [ -z "$IPS_GBOT" ] || [ "$TOTAL_IPS" -lt 10 ]; then
    echo "Error: No se pudo obtener la lista de Google o la lista es demasiado corta."
    exit 1
fi

# 1. Crear/Sobreescribir el archivo de configuración permanente
echo "[DEFAULT]
ignoreip = $LISTA_FINAL" > /etc/fail2ban/jail.d/google-whitelist.local

echo "Recargando Fail2ban..."
if fail2ban-client reload > /dev/null 2>&1; then
    echo "--------------------------------------------------------"
    echo "¡OK! Fail2ban actualizado ($TOTAL_IPS rangos)."
else
    echo "--------------------------------------------------------"
    echo "ERROR: El archivo se creó pero Fail2ban no pudo recargar."
    echo "Revisa la sintaxis con: fail2ban-client -d"
    exit 1
fi

# --- PARTE 2: FIREWALL IPSET (Prioridad para Pasarelas y Google) ---
# Crear el set de Whitelist si no existe
ipset create google-whitelist hash:net 2>/dev/null
ipset flush google-whitelist

echo "Actualizando ipset google-whitelist..."
for ip in $LISTA_FINAL; do
    # Añadir solo IPv4 al ipset estándar
    if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        ipset add google-whitelist $ip 2>/dev/null
    fi
done

# --- PARTE 3: REGLAS DE IPTABLES (EL ORDEN ES VITAL) ---
# 1. Primero nos aseguramos de que la regla de ESTABLISHED esté en el TOP 1
iptables -D INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null
iptables -I INPUT 1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 2. El IPSET de Whitelist (Google + PayPal + Redsys) en el TOP 2
iptables -D INPUT -m set --match-set google-whitelist src -j ACCEPT 2>/dev/null
iptables -I INPUT 2 -m set --match-set google-whitelist src -j ACCEPT

# 3. La salida (OUTPUT) para que el servidor pueda hablar con PayPal
iptables -D OUTPUT -m set --match-set google-whitelist dst -j ACCEPT 2>/dev/null
iptables -I OUTPUT 1 -m set --match-set google-whitelist dst -j ACCEPT

# 4. Persistencia para que sobreviva a reinicios
sudo netfilter-persistent save > /dev/null 2>&1

echo "--------------------------------------------------------"
echo "¡LISTO! Configuración de Whitelist y Pagos aplicada."
echo "Rango de IPs en lista blanca: $TOTAL_IPS"
