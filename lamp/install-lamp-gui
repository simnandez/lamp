#!/usr/bin/env python3

import sys
import os
import subprocess
import pwd
from PyQt6.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout,
                             QHBoxLayout, QCheckBox, QPushButton, QTextEdit,
                             QLabel, QGroupBox, QScrollArea, QMessageBox, QFrame)
from PyQt6.QtCore import QThread, pyqtSignal, Qt
from PyQt6.QtGui import QFont

# --- CONFIGURACIÓN DE INSTALACIÓN ---
DB_ROOT_PASS = "123456"
PHP_VERSIONS = ["5.6", "7.0", "7.1", "7.2", "7.3", "7.4", "8.0", "8.1", "8.2", "8.3", "8.4", "8.5"]
PHP_API = {
    "5.6": "20131226", "7.0": "20151012", "7.1": "20160303", "7.2": "20170718",
    "7.3": "20180731", "7.4": "20190902", "8.0": "20200930", "8.1": "20210902",
    "8.2": "20220829", "8.3": "20230831", "8.4": "20240924", "8.5": "20250925"
}

class InstallWorker(QThread):
    log_signal = pyqtSignal(str)
    finished_signal = pyqtSignal(bool)

    def __init__(self, tasks, php_states):
        super().__init__()
        self.tasks = tasks
        self.php_states = php_states
        
        real_uid = None
        if os.environ.get('SUDO_UID'):
            real_uid = int(os.environ.get('SUDO_UID'))
        elif os.environ.get('PKEXEC_UID'):
            real_uid = int(os.environ.get('PKEXEC_UID'))
        else:
            # Intenta obtener el UID original mediante el archivo de auditoría del sistema
            try:
                with open('/proc/self/loginuid', 'r') as f:
                    luid = f.read().strip()
                    if luid and luid != '4294967295':
                        real_uid = int(luid)
            except Exception:
                pass

        if real_uid is not None and real_uid != 0:
            self.real_user = pwd.getpwuid(real_uid)[0]
        else:
            self.real_user = os.environ.get('SUDO_USER') or pwd.getpwuid(os.getuid())[0]
        
        # Extraer de forma segura rutas y credenciales del usuario objetivo
        try:
            user_info = pwd.getpwnam(self.real_user)
            self.user_home = user_info.pw_dir
            self.user_uid = user_info.pw_uid
            self.user_gid = user_info.pw_gid
        except KeyError:
            self.user_home = os.path.expanduser(f"~{self.real_user}")
            self.user_uid = os.getuid()
            self.user_gid = os.getgid()

    def run_cmd(self, cmd, desc):
        self.log_signal.emit(f"<b>[EJECUTANDO]</b> {desc}...")
        process = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        for line in process.stdout:
            self.log_signal.emit(f"<span style='color: #888;'>&nbsp;&nbsp;{line.strip()}</span>")
        process.wait()
        return process.returncode == 0

    def create_autostart(self):
        dir_path = os.path.join(self.user_home, ".config", "autostart")
        file_path = os.path.join(dir_path, "lamp-tray.desktop")
        content = "[Desktop Entry]\nExec=lamp-tray\nIcon=network-server\nName=lamp-tray\nTerminal=false\nType=Application\n"
        try:
            # Asegurar la existencia de directorios heredando correctamente el propietario
            os.makedirs(dir_path, exist_ok=True)
            
            with open(file_path, "w") as f: 
                f.write(content)
            
            os.chown(file_path, self.user_uid, self.user_gid)
            os.chown(dir_path, self.user_uid, self.user_gid)
            
            self.log_signal.emit(f"<span style='color: #27ae60;'>✔ Autostart creado con éxito en el Home de '{self.real_user}'.</span>")
        except Exception as e:
            self.log_signal.emit(f"<span style='color: #e74c3c;'>✘ Error en Autostart: {e}</span>")

    def setup_tmpfs_logs(self):
        conf = "d /var/log/apache2 755 root adm -\nd /var/log/mysql 2755 mysql adm -\n"
        try:
            with open('/etc/tmpfiles.d/tmpfslogs.conf', 'w') as f: f.write(conf)
            self.log_signal.emit("<span style='color: #27ae60;'>✔ Logs en RAM configurados (tmpfs).</span>")
        except Exception as e:
            self.log_signal.emit(f"✘ Error en tmpfs: {e}")

    def run(self):
        if self.tasks['base']:
            self.run_cmd("apt update && apt install -y apache2 mariadb-server php php-mysql wget lsb-release ca-certificates apt-transport-https gnupg2 curl", "Instalación Base")
        else:
            self.run_cmd("apt purge -y apache2 mariadb-server apache2-bin mariadb-client && apt autoremove -y", "Desinstalación Base (Apache y MariaDB)")
            
        if self.tasks['sql_sec']:
            sql_commands = [
                f"ALTER USER 'root'@'localhost' IDENTIFIED BY '{DB_ROOT_PASS}';",
                "DELETE FROM mysql.user WHERE User='';",
                "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');",
                "DROP DATABASE IF EXISTS test;",
                "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';",
                "GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;",
                "FLUSH PRIVILEGES;"
            ]
            full_sql = " ".join(sql_commands)
            self.run_cmd(f"mysql -u root -e \"{full_sql}\"", "Asegurando MariaDB (limpieza completa)")

        if self.tasks['sql_mode']:
            path = '/etc/mysql/conf.d/disable_strict_mode.cnf.back'
            conf = "[mysqld]\nsql_mode=ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION"
            with open(path, 'w') as f: f.write(conf)

        if self.tasks['sury']:
            cmd = "apt-get install -y extrepo && extrepo enable sury && apt update"
            self.run_cmd(cmd, "Repositorio PHP")
        else:
            if os.path.exists("/etc/apt/sources.list.d/php.list"):
                self.run_cmd("rm /etc/apt/sources.list.d/php.list && rm /usr/share/keyrings/deb.sury.org-php.gpg && apt update", "Eliminando Repositorio PHP")

        for ver, install in self.php_states.items():
            if install:
                libs = f"php{ver} libapache2-mod-php{ver} php{ver}-xdebug php{ver}-curl php{ver}-gd php{ver}-xml php{ver}-mysql php{ver}-mbstring php{ver}-soap php{ver}-intl php{ver}-zip php{ver}-imap php{ver}-cgi"
                if ver in ["5.6", "7.0", "7.1"]:
                    libs += f" php{ver}-mcrypt php{ver}-xmlrpc"

                if self.run_cmd(f"apt install -y {libs}", f"Instalando PHP {ver} y extensiones"):
                    ini = f"/etc/php/{ver}/mods-available/xdebug.ini"
                    if os.path.exists(os.path.dirname(ini)):
                        api = PHP_API.get(ver, "unknown")
                        with open(ini, 'w') as f:
                            f.write(f'zend_extension="/usr/lib/php/{api}/xdebug.so"\nxdebug.mode=debug\nxdebug.remote_port=9003\nxdebug.remote_enable=1\n')
            else:
                # Solo desinstalar si el paquete principal existe
                if os.path.exists(f"/etc/php/{ver}"):
                    self.run_cmd(f"apt purge -y php{ver}* && apt autoremove -y", f"Desinstalando PHP {ver}")

        if self.tasks['apache']:
            cmds = f"a2enmod rewrite && chown -R www-data:www-data /var/www/html && usermod -aG www-data {self.real_user} && systemctl restart apache2"
            self.run_cmd(cmds, "Apache y Permisos")
        else:
            self.run_cmd("a2dismod rewrite && systemctl restart apache2", "Deshabilitando ModRewrite")

        if self.tasks['tmpfs']:
            self.setup_tmpfs_logs()
        else:
            if os.path.exists('/etc/tmpfiles.d/tmpfslogs.conf'):
                os.remove('/etc/tmpfiles.d/tmpfslogs.conf')
                self.log_signal.emit("<span style='color: #e67e22;'>✔ Configuración tmpfs eliminada.</span>")

        if self.tasks['autostart']:
            self.create_autostart()
        else:
            path = os.path.join(self.user_home, ".config", "autostart", "lamp-tray.desktop")
            if os.path.exists(path):
                os.remove(path)
                self.log_signal.emit("<span style='color: #e67e22;'>✔ Autostart eliminado.</span>")

        self.finished_signal.emit(True)

class LampGui(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("ArKanum LAMP Installer 8.5.1")
        self.setMinimumSize(720, 800)
        self.init_ui()

    def init_ui(self):
        central = QWidget()
        self.real_user = os.environ.get('SUDO_USER') or pwd.getpwuid(os.getuid())[0]
        self.setCentralWidget(central)
        layout = QVBoxLayout(central)
        layout.setSpacing(8)

        title = QLabel("ArKanum LAMP Stack installer")
        title.setFont(QFont("sans-serif", 16, QFont.Weight.Bold))
        title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(title)

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.Shape.NoFrame)
        scroll_content = QWidget()
        self.opts_layout = QVBoxLayout(scroll_content)

        # SERVIDORES
        g_base = QGroupBox("Instalación Base")
        v_base = QVBoxLayout()
        self.chk_base = QCheckBox("Instalar Apache2, MariaDB y PHP")
        self.chk_sql_sec = QCheckBox("Asegurar MariaDB y configurar root")
        self.chk_sql_mode = QCheckBox("Poder usar MODO ESTRICTO en MariaDB")
        for c in [self.chk_base, self.chk_sql_sec, self.chk_sql_mode]: v_base.addWidget(c)
        g_base.setLayout(v_base); self.opts_layout.addWidget(g_base)

        # PHP
        g_php = QGroupBox("PHP (Repositorio Sury.org)")
        v_php = QVBoxLayout()
        self.chk_sury = QCheckBox("Añadir repositorio de múltiples versiones PHP")
        v_php.addWidget(self.chk_sury)
        php_grid = QWidget()
        grid = QHBoxLayout(php_grid); grid.setContentsMargins(10,0,0,0)
        self.php_checks = {}
        c1, c2 = QVBoxLayout(), QVBoxLayout()
        for i, v in enumerate(PHP_VERSIONS):
            cb = QCheckBox(f"PHP {v}")
            self.php_checks[v] = cb
            cb.toggled.connect(self.update_sury_checkbox)
            if i < 6: c1.addWidget(cb)
            else: c2.addWidget(cb)
        grid.addLayout(c1); grid.addLayout(c2)
        v_php.addWidget(php_grid); g_php.setLayout(v_php); self.opts_layout.addWidget(g_php)

        # OPTIMIZACIÓN Y ESCRITORIO
        g_ext = QGroupBox("Configuración Apache y permisos")
        v_ext = QVBoxLayout()
        self.chk_apache = QCheckBox("Habilitar ModRewrite y ajustar permisos en /var/www/html")
        self.chk_tmpfs = QCheckBox("Mover logs a RAM (tmpfs) - Recomendado para SSD")
        self.chk_autostart = QCheckBox("Añadir 'ArKanum lamp tray' al Inicio Automático")
        for c in [self.chk_apache, self.chk_tmpfs, self.chk_autostart]: v_ext.addWidget(c)
        g_ext.setLayout(v_ext); self.opts_layout.addWidget(g_ext)

        scroll.setWidget(scroll_content)
        layout.addWidget(scroll, stretch=1)

        # Detección inicial
        self.detect_installed_components()

        self.console = QTextEdit()
        self.console.setReadOnly(True)
        self.console.setFixedHeight(160)
        self.console.setStyleSheet("""QTextEdit {background-color: #000000;color: #FFFFFF;font-family: 'Monospace';font-size: 10pt;border: 1px solid #444444;}""")
        layout.addWidget(self.console)

        self.btn = QPushButton(" SINCRONIZAR CAMBIOS (INSTALAR / DESINSTALAR)")
        self.btn.setFixedHeight(50)
        self.btn.clicked.connect(self.start_process)
        layout.addWidget(self.btn)

    def detect_installed_components(self):
        def is_installed(pkg):
            return subprocess.call(["dpkg", "-s", pkg], stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT) == 0

        # Base
        if is_installed("apache2") or is_installed("mariadb-server"):
            self.chk_base.setChecked(True)

        # PHP Repo
        if os.path.exists("/etc/apt/sources.list.d/php.list"):
            self.chk_sury.setChecked(True)

        # PHP Versions
        for ver, cb in self.php_checks.items():
            if is_installed(f"php{ver}"):
                cb.setChecked(True)

        # Tmpfs
        if os.path.exists('/etc/tmpfiles.d/tmpfslogs.conf'):
            self.chk_tmpfs.setChecked(True)

        # Autostart
        user_home = pwd.getpwnam(self.real_user).pw_dir
        if os.path.exists(os.path.join(user_home, ".config", "autostart", "lamp-tray.desktop")):
            self.chk_autostart.setChecked(True)

    def update_sury_checkbox(self):
        any_php_selected = any(cb.isChecked() for cb in self.php_checks.values())
        if any_php_selected:
            self.chk_sury.setChecked(True)

    def log(self, text):
        self.console.append(text)
        self.console.verticalScrollBar().setValue(self.console.verticalScrollBar().maximum())

    def start_process(self):
        if os.geteuid() != 0:
            QMessageBox.critical(self, "Error", "Debes ejecutar como root.")
            return
        tasks = {
            'base': self.chk_base.isChecked(), 'sql_sec': self.chk_sql_sec.isChecked(),
            'sql_mode': self.chk_sql_mode.isChecked(), 'sury': self.chk_sury.isChecked(),
            'apache': self.chk_apache.isChecked(), 'tmpfs': self.chk_tmpfs.isChecked(),
            'autostart': self.chk_autostart.isChecked()
        }
        php_states = {v: cb.isChecked() for v, cb in self.php_checks.items()}
        self.btn.setEnabled(False)
        self.console.clear()
        self.worker = InstallWorker(tasks, php_states)
        self.worker.log_signal.connect(self.log)
        self.worker.finished_signal.connect(lambda: self.btn.setEnabled(True))
        self.worker.start()

if __name__ == "__main__":
    app = QApplication(sys.argv)
    app.setStyle("Fusion")
    win = LampGui()
    win.show()
    sys.exit(app.exec())