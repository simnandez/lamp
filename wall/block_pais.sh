#!/bin/bash

for country in "$@"; do
    # 1. Definimos nombres de sets
    SET_NAME="pais-$country"
    SET_TMP="${SET_NAME}-tmp"

    echo "Actualizando bloqueos para: $country..."

    # 2. Creamos un set temporal vacío
    ipset create "$SET_TMP" hash:net maxelem 200000 2>/dev/null
    ipset flush "$SET_TMP"

    # 3. Descargamos y llenamos el set TEMPORAL
    # Usamos -f para que curl falle si no hay conexión
    DATA=$(curl -sf "http://www.ipdeny.com/ipblocks/data/countries/$country.zone")

    if [ -z "$DATA" ]; then
        echo "Error: No se pudo obtener la lista para $country. Saltando..."
        ipset destroy "$SET_TMP"
        continue
    fi

    echo "$DATA" | sed "s/^/add $SET_TMP /" | ipset restore

    # 4. Si el set principal no existe, lo creamos
    ipset create "$SET_NAME" hash:net maxelem 200000 2>/dev/null

    # 5. EL TRUCO: Intercambiamos el temporal por el real
    # Esto es instantáneo y no afecta al tráfico en curso
    ipset swap "$SET_TMP" "$SET_NAME"

    # 6. Borramos el temporal (que ahora tiene lo viejo)
    ipset destroy "$SET_TMP"

    # 7. Verificamos IPTables
    if ! iptables -C INPUT -m set --match-set "$SET_NAME" src -j DROP 2>/dev/null; then
        iptables -I INPUT 3 -m set --match-set "$SET_NAME" src -j DROP
        echo "Regla de IPTables aplicada para $country."
    fi
done

netfilter-persistent save
echo "Proceso finalizado."