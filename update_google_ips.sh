#!/bin/bash

# ==========================================================
# CONFIGURACIÓN DE TERCEROS (PAGOS Y LOGÍSTICA)
# ==========================================================
# IPs fijas de seQura
IPS_SEQURA="34.253.159.179 34.252.147.155 52.211.243.177"

# Rangos de PayPal (Principales para Checkout y APIs)
IPS_PAYPAL="173.0.80.0/20 66.211.168.0/22 64.4.240.0/21 66.211.160.0/20"

# Rangos de Redsys (Pasarela de tarjetas España)
IPS_REDSYS="193.16.160.0/24 195.76.9.0/24 195.76.29.0/24"

# ==========================================================
# CONFIGURACIÓN DE NUESTRA INFRAESTRUCTURA (PROBANCE Y LA TEVA WEB)
MIS_IPS="80.24.12.77 34.78.139.107 $IPS_SEQURA $IPS_PAYPAL $IPS_REDSYS"
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
# Limpiar reglas previas para evitar duplicados
iptables -D INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null
iptables -D INPUT -m set --match-set google-whitelist src -j ACCEPT 2>/dev/null
iptables -D OUTPUT -m set --match-set google-whitelist dst -j ACCEPT 2>/dev/null

# 1. PERMITIR RESPUESTAS (La regla de oro para que el carrito NO se cuelgue)
# Permite que si el servidor inicia una conexión (ej. a PayPal), la respuesta entre de vuelta.
iptables -I INPUT 1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 2. WHITELIST PRIORITARIA (Google, PayPal, Redsys, seQura)
# Se pone en la posición #2 para que pase antes que cualquier bloqueo de país.
iptables -I INPUT 2 -m set --match-set google-whitelist src -j ACCEPT

# 3. SALIDA SEGURA (Permite que el servidor envíe datos a las pasarelas de pago)
iptables -I OUTPUT 1 -m set --match-set google-whitelist dst -j ACCEPT

# 4. Persistencia para que sobreviva a reinicios
sudo netfilter-persistent save > /dev/null 2>&1

echo "--------------------------------------------------------"
echo "¡LISTO! Configuración de Whitelist y Pagos aplicada."
echo "Rango de IPs en lista blanca: $TOTAL_IPS"
