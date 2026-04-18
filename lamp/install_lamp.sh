#!/bin/bash

# ==============================================================================
# FUNCIÓN DE CONFIRMACIÓN
# ==============================================================================
confirmar_paso() {
    echo -e "\n\e[1;33m¿Desea ejecutar: $1? (s/n)\e[0m"
    read -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        echo -e "\e[1;31m[SALTADO]\e[0m $1"
        return 1
    fi
    return 0
}

# Comprobar si se ejecuta como root
if [[ $EUID -ne 0 ]]; then
   echo "Este script debe ejecutarse como root (usa sudo)."
   exit 1
fi

# Configuración de variables
DB_ROOT_PASS="123456"
CURRENT_USER=$(logname || whoami)
PHP_VERSIONS=("5.6" "7.0" "7.1" "7.2" "7.3" "7.4" "8.0" "8.1" "8.2" "8.3" "8.4" "8.5")

# 1. Actualización e instalación base
if confirmar_paso "Actualización e instalación de Apache y MariaDB"; then
    apt update && apt install -y apache2 mariadb-server php php-mysql wget lsb-release ca-certificates apt-transport-https
fi

# 2. Securizar MariaDB y configurar root
if confirmar_paso "Configuración de seguridad y clave root para MariaDB"; then
    mariadb_secure_installation
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASS';"
    mysql -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;"
    mysql -e "FLUSH PRIVILEGES;"
fi

# 3. Permisos de directorio web
if confirmar_paso "Configurar permisos de grupo y escritura en /var/www/html"; then
    chgrp -R www-data /var/www/html/
    chmod -R g+w /var/www/html/
    find /var/www/html/ -type d -exec chmod 2775 {} \;
    find /var/www/html/ -type f -exec chmod ug+rw {} \;
    usermod -a -G www-data "$CURRENT_USER"
    echo "Usuario $CURRENT_USER añadido al grupo www-data."
fi

# 4. Repositorio de PHP (Sury)
if confirmar_paso "Añadir repositorio PHP de Sury.org"; then
    wget -qO - https://packages.sury.org/php/README.txt | bash -x
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

# 6. MySQL Strict Mode
if confirmar_paso "Configurar MariaDB en modo NO ESTRICTO"; then
    cat <<EOF > /etc/mysql/conf.d/enable_strict_mode.cnf.back
[mysqld]
sql_mode=ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION
EOF
fi

# 7. ModRewrite y Configuración Apache
if confirmar_paso "Habilitar ModRewrite y configurar permisos en Apache"; then
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
fi

# 8. Logs en tmpfs
if confirmar_paso "Configurar logs de Apache y MySQL en RAM (tmpfs)"; then
    cat <<EOF > /etc/tmpfiles.d/tmpfslogs.conf
d /var/log/apache2 755 root adm -
d /var/log/mysql 2755 mysql adm -
EOF
fi

# Reiniciar servicios
if confirmar_paso "Reiniciar servicios para aplicar cambios"; then
    systemctl restart apache2
    systemctl restart mariadb
fi

echo "------------------------------------------------"
echo -e "\e[1;32m¡Proceso finalizado!\e[0m"
echo "Recordatorio: El usuario '$CURRENT_USER' ha sido procesado."
echo "Si el usuario cambió de grupo, cierra sesión para que sea efectivo."
echo "------------------------------------------------"