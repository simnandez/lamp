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

# --- PARTE 2: FIREWALL IPSET (Protección de prioridad en IPTables) ---
# 1. Crear el set si no existe (hash:net es necesario para rangos CIDR)
# Creamos el set para IPv4.
ipset create google-whitelist hash:net 2>/dev/null

# 2. Limpiar y rellenar el set con las IPs frescas
echo "Actualizando ipset google-whitelist..."
ipset flush google-whitelist
for ip in $LISTA_FINAL; do
    # Añadimos solo IPv4 al ipset (ipset estándar suele quejarse con IPv6 si no se especifica family inet6)
    if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        ipset add google-whitelist $ip 2>/dev/null
    fi
done

# 3. Inyectar la regla de prioridad en la posición #1 de IPTables
# Usamos -I (Insert) para asegurar que Google pase ANTES de cualquier baneo de país por ipset
if ! iptables -C INPUT -m set --match-set google-whitelist src -j ACCEPT 2>/dev/null; then
    sudo iptables -I INPUT -m set --match-set google-whitelist src -j ACCEPT
    echo "[OK] Regla de prioridad añadida a IPTables (Posición #1)."
fi

# 4. Persistencia para que sobreviva a reinicios
sudo netfilter-persistent save > /dev/null 2>&1

echo "--------------------------------------------------------"
echo "¡LISTO! Google y tus IPs son ahora prioridad #1 en el Firewall."
echo "Ahora la opción (P) de bloqueo de países es segura frente a Googlebot."