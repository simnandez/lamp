#!/bin/bash
# Uso: ./unblock_pais.sh us gb (desbloquea USA y UK)

for country in "$@"; do
    echo "--- Procesando desbloqueo para: $country ---"

    # 1. Eliminar la regla de iptables (usamos un bucle por si acaso hay reglas duplicadas)
    while iptables -C INPUT -m set --match-set "pais-$country" src -j DROP 2>/dev/null; do
        sudo iptables -D INPUT -m set --match-set "pais-$country" src -j DROP
        echo "[OK] Regla de IPTables eliminada para $country."
    done

    # 2. Destruir el set de ipset
    if sudo ipset list "pais-$country" >/dev/null 2>&1; then
        sudo ipset destroy "pais-$country"
        echo "[OK] Set ipset 'pais-$country' destruido."
    else
        echo "[!] El set 'pais-$country' no existía."
    fi
done

# 3. Guardar cambios
sudo netfilter-persistent save
echo "--- Desbloqueo finalizado y persistido ---"