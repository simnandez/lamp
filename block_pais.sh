#!/bin/bash
for country in "$@"; do
    ipset create "pais-$country" hash:net maxelem 200000 2>/dev/null
    echo "Actualizando bloqueos para: $country..."

    # Descargamos y preparamos el formato para ipset restore
    curl -s "http://www.ipdeny.com/ipblocks/data/countries/$country.zone" | \
    sed "s/^/add pais-$country /" | \
    ipset restore

    if ! iptables -C INPUT -m set --match-set "pais-$country" src -j DROP 2>/dev/null; then
        # IMPORTANTE: Insertamos en la posición 2 para no pisar la Whitelist de Google
        iptables -I INPUT 2 -m set --match-set "pais-$country" src -j DROP
        echo "Regla de IPTables aplicada para $country en posición #2."
    fi
done
netfilter-persistent save