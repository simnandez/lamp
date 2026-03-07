LOG_PATH="/home/tienda/logs/access_log"

clear
echo "==============================================================="
echo "   PANEL DE CONTROL DE SEGURIDAD - AIRSOFT GANDIA"
echo "   Fecha: $(date)"
echo "==============================================================="

echo -e "\n1. ESTADO DEL SISTEMA (CPU y Carga)"
uptime
echo "---------------------------------------------------------------"

echo -e "\n2. TOP 10 IPs CON MÁS CONEXIONES ACTIVAS"
# Muestra cuántas conexiones tiene cada IP en este momento
netstat -ntu | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -nr | head -n 10
echo "---------------------------------------------------------------"

echo -e "\n3. TOP 10 IPs EN EL LOG DE ACCESO (Últimas 5000 líneas)"
# Analiza quién está pidiendo más páginas ahora mismo
tail -n 5000 $LOG_PATH | awk '{print $1}' | sort | uniq -c | sort -nr | head -n 10
echo "---------------------------------------------------------------"

echo -e "\n4. DETECTANDO PETICIONES SOSPECHOSAS (?q=Marca...)"
# Cuenta cuántas búsquedas de bots están entrando
BUSQUEDAS=$(tail -n 1000 $LOG_PATH | grep "?q=" | wc -l)
echo "Búsquedas maliciosas detectadas en las últimas 1000 líneas: $BUSQUEDAS"
echo "---------------------------------------------------------------"

echo -e "\n5. CONTADORES DE BLOQUEO (IPTABLES)"
# Muestra tus reglas de hoy y cuántos paquetes han parado
sudo iptables -L INPUT -n -v | grep DROP | awk '$1 > 0 {print "Rango: " $8 " | Bloqueos: " $1 " paquetes (" $2 " bytes)"}'
echo "==============================================================="

echo -e "\n[CONSEJO] Si ves una IP con >20 conexiones en el punto 2,"
echo "lanza: sudo iptables -I INPUT -s IP_AQUÍ -j DROP"
