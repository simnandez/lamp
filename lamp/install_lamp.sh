#!/bin/bash

# Configuración de variables
DB_ROOT_PASS="123456"
CURRENT_USER=$(whoami)
PHP_VERSIONS=("5.6" "7.0" "7.1" "7.2" "7.3" "7.4" "8.0" "8.1" "8.2" "8.3" "8.4" "8.5")

# 1. Actualización e instalación base
echo "--- Instalando Apache y MariaDB ---"
apt update && apt install -y apache2 mariadb-server php php-mysql wget lsb-release ca-certificates apt-transport-https

# 2. Securizar MariaDB y configurar root
echo "--- Configurando MariaDB ---"
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASS';"
mysql -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;"
mysql -e "FLUSH PRIVILEGES;"

# 3. Permisos de directorio web
echo "--- Configurando permisos en /var/www/html ---"
chgrp -R www-data /var/www/html/
chmod -R g+w /var/www/html/
find /var/www/html/ -type d -exec chmod 2775 {} \;
find /var/www/html/ -type f -exec chmod ug+rw {} \;
usermod -a -G www-data $CURRENT_USER

# 4. Repositorio de PHP (Sury)
echo "--- Añadiendo repositorio PHP de Sury ---"
wget -qO - https://packages.sury.org/php/README.txt | bash -x
apt update

# 5. Instalación de versiones de PHP y Xdebug
# Mapeo de versiones a sus directorios de API (zend_extension)
declare -A PHP_API=(
    ["5.6"]="20131226" ["7.0"]="20151012" ["7.1"]="20160303" ["7.2"]="20170718"
    ["7.3"]="20180731" ["7.4"]="20190902" ["8.0"]="20200930" ["8.1"]="20210902"
    ["8.2"]="20220829" ["8.3"]="20230831" ["8.4"]="20240924" ["8.5"]="20250925"
)

for ver in "${PHP_VERSIONS[@]}"; do
    echo "--- Instalando PHP $ver y extensiones ---"
    apt install -y php$ver php$ver-{xdebug,curl,gd,xml,mysql,mbstring,soap,intl,zip,imap,cgi}

    # mcrypt y xmlrpc solo para versiones antiguas
    if [[ "$ver" == "5.6" || "$ver" == "7.0" || "$ver" == "7.1" ]]; then
        apt install -y php$ver-mcrypt php$ver-xmlrpc
    fi

    # Configuración de Xdebug
    XDEBUG_INI="/etc/php/$ver/mods-available/xdebug.ini"
    API_DIR=${PHP_API[$ver]}

    echo "--- Configurando Xdebug para PHP $ver ---"
    cat <<EOF > $XDEBUG_INI
zend_extension="/usr/lib/php/$API_DIR/xdebug.so"
xdebug.remote_enable=1
xdebug.remote_handler=dbgp
xdebug.remote_mode=req
xdebug.remote_host=127.0.0.1
xdebug.remote_port=9003
xdebug.max_nesting_level=300
xdebug.mode=debug
EOF
done

# 6. MySQL Strict Mode
echo "--- Configurando MySQL Strict Mode ---"
cat <<EOF > /etc/mysql/conf.d/enable_strict_mode.cnf
[mysqld]
sql_mode=ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION
EOF

# 7. ModRewrite y Configuración Apache
echo "--- Configurando Apache Rewrite ---"
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

# 8. Logs en tmpfs (solo si disco SSD)
echo "--- Configurando logs en tmpfs ---"
cat <<EOF > /etc/tmpfiles.d/tmpfslogs.conf
d /var/log/apache2 755 root adm -
d /var/log/mysql 2755 mysql adm -
EOF

# Reiniciar servicios
systemctl restart apache2
systemctl restart mariadb

echo "------------------------------------------------"
echo " ¡Instalación completada con éxito! "
echo " Recordatorio: El usuario '$CURRENT_USER' ha sido añadido al grupo www-data."
echo " Reinicia tu sesión para aplicar los cambios de grupo."
echo "------------------------------------------------"