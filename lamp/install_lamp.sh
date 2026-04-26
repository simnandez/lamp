#!/bin/bash

# Salir si hay errores, variables no definidas o fallos en tuberías
set -euo pipefail

# ==============================================================================
# CONFIGURACIÓN Y COLORES
# ==============================================================================
DB_ROOT_PASS="123456"
CURRENT_USER=$(logname || echo $USER)
PHP_VERSIONS=("5.6" "7.0" "7.1" "7.2" "7.3" "7.4" "8.0" "8.1" "8.2" "8.3" "8.4" "8.5")

VERDE="\e[1;32m"
ROJO="\e[1;31m"
AMARILLO="\e[1;33m"
AZUL="\e[1;34m"
RESET="\e[0m"

# ==============================================================================
# FUNCIONES AUXILIARES
# ==============================================================================
log_info()    { echo -e "${AZUL}[INFO]${RESET} $1"; }
log_success() { echo -e "${VERDE}[OK]${RESET} $1"; }
log_error()   { echo -e "${ROJO}[ERROR]${RESET} $1"; }

confirmar_paso() {
    echo -e "\n${AMARILLO}¿Deseas ejecutar: $1? (s/n)${RESET}"
    read -n 1 -r
    echo
    [[ $REPLY =~ ^[Ss]$ ]]
}

# Comprobar root
if [[ $EUID -ne 0 ]]; then
   log_error "Este script debe ejecutarse como root (usa sudo)."
   exit 1
fi

# ==============================================================================
# 1. ACTUALIZACIÓN E INSTALACIÓN BASE
# ==============================================================================
if confirmar_paso "Actualización e instalación de base (Apache, MariaDB, Utilerías)"; then
    apt update
    apt install -y apache2 mariadb-server wget lsb-release ca-certificates apt-transport-https gnupg2 curl
fi

# ==============================================================================
# 2. CONFIGURACIÓN DE SEGURIDAD MARIADB (AUTOMATIZADA)
# ==============================================================================
if confirmar_paso "Configurar MariaDB (Password Root y Seguridad)"; then
    log_info "Asegurando MariaDB y configurando root..."
    mysql -u root -p'123456' -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASS';"
    mysql -u root -p'123456' -e "DELETE FROM mysql.user WHERE User='';"
    mysql -u root -p'123456' -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
    mysql -u root -p'123456' -e "DROP DATABASE IF EXISTS test;"
    mysql -u root -p'123456' -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
    mysql -u root -p'123456' -e "FLUSH PRIVILEGES;"
    log_success "Base de datos configurada y asegurada."
fi

# ==============================================================================
# 3. MODO NO ESTRICTO MARIADB
# ==============================================================================
if confirmar_paso "Configurar MariaDB en modo NO ESTRICTO"; then
    log_info "Cambiando sql_mode..."
    cat <<EOF > /etc/mysql/conf.d/disable_strict_mode.cnf.back
[mysqld]
sql_mode=ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION
EOF
    log_success "Modo estricto desactivado."
fi

# ==============================================================================
# 4. REPOSITORIO SURY (MÉTODO MODERNO)
# ==============================================================================
if confirmar_paso "Añadir repositorio PHP de Sury.org"; then
    log_info "Instalando llaves y repo de Sury..."
    curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg
    echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
    apt update
fi

# 5. Instalación de versiones de PHP y Xdebug
declare -A PHP_API=(
    ["5.6"]="20131226" ["7.0"]="20151012" ["7.1"]="20160303" ["7.2"]="20170718"
    ["7.3"]="20180731" ["7.4"]="20190902" ["8.0"]="20200930" ["8.1"]="20210902"
    ["8.2"]="20220829" ["8.3"]="20230831" ["8.4"]="20240924" ["8.5"]="20250925"
)

if confirmar_paso "Instalar todas las versiones de PHP (${PHP_VERSIONS[*]})"; then
    for ver in "${PHP_VERSIONS[@]}"; do
        echo "--- Instalando PHP $ver ---"
        apt install -y php$ver php$ver-{xdebug,curl,gd,xml,mysql,mbstring,soap,intl,zip,imap,cgi}

        if [[ "$ver" == "5.6" || "$ver" == "7.0" || "$ver" == "7.1" ]]; then
            apt install -y php$ver-mcrypt php$ver-xmlrpc
        fi

        # Configuración de Xdebug
        XDEBUG_INI="/etc/php/$ver/mods-available/xdebug.ini"
        API_DIR=${PHP_API[$ver]}

        if [ -d "/etc/php/$ver" ]; then
            cat <<EOF > "$XDEBUG_INI"
zend_extension="/usr/lib/php/$API_DIR/xdebug.so"
xdebug.remote_enable=1
xdebug.remote_handler=dbgp
xdebug.remote_mode=req
xdebug.remote_host=127.0.0.1
xdebug.remote_port=9003
xdebug.max_nesting_level=300
xdebug.mode=debug
EOF
        fi
    done
fi

# ==============================================================================
# 6. APACHE Y PERMISOS DE DIRECTORIO
# ==============================================================================
if confirmar_paso "Habilitar ModRewrite y configurar permisos en Apache"; then
    log_info "Configurando Apache y permisos de /var/www/html..."
    a2enmod rewrite

    CONF_FILE="/etc/apache2/sites-available/000-default.conf"
    if ! grep -q "<Directory /var/www/html>" "$CONF_FILE"; then
        sed -i '/DocumentRoot \/var\/www\/html/a \
        <Directory /var/www/html>\
            Options Indexes FollowSymLinks\
            AllowOverride All\
            Require all granted\
        </Directory>' "$CONF_FILE"
    fi

    # Ajuste de permisos
    chown -R www-data:www-data /var/www/html
    find /var/www/html -type d -exec chmod 2775 {} \;
    find /var/www/html -type f -exec chmod 0664 {} \;
    usermod -aG www-data "$CURRENT_USER"
fi

# ==============================================================================
# 7. LOGS EN RAM (TMPFS)
# ==============================================================================
if confirmar_paso "Configurar logs de Apache y MySQL en RAM (tmpfs)"; then
    log_info "Configurando tmpfiles para logs..."
    cat <<EOF > /etc/tmpfiles.d/tmpfslogs.conf
d /var/log/apache2 755 root adm -
d /var/log/mysql 2755 mysql adm -
EOF
fi

# ==============================================================================
# REINICIO Y FINALIZACIÓN
# ==============================================================================
if confirmar_paso "Reiniciar servicios para aplicar cambios"; then
    systemctl restart apache2 mariadb
fi

echo -e "\n${VERDE}================================================${RESET}"
echo -e "${VERDE}¡PROCESO FINALIZADO CON ÉXITO!${RESET}"
echo -e "Usuario '${CURRENT_USER}' listo."
echo -e "SQL Mode: No Estricto configurado."
echo -e "Xdebug: Puerto 9003."
echo -e "${VERDE}================================================${RESET}\n"