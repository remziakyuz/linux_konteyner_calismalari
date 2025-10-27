Podman Guestbook Lab Dosyaları
==============================
Dizinler:
  $ sudo mkdir -pv /mnt/web_app  #  -> index.php bu dizine kopyalanmalı
  $ sudo chown $USER:$USER /mnt/web_app
  $ chmod 775 /mnt/web_app
  $ sudo mkdir -pv /mnt/db       # -> MariaDB veri dizini
  $ sudo chown $USER:$USER /mnt/db
  $ chmod 775 /mnt/db

Hızlı başlatma:
  $ podman network create app-net
  $ podman network create db-net

$ sudo ./add-lab-ca.sh lab-ca.crt

  $ podman pull registry.lab.akyuz.tech/db/mariadb:latest 
  $ podman run -d --name mariadb  --network db-net \
             -p 3306:3306 -v /mnt/db:/var/lib/mysql:Z  \
			 -e MYSQL_ROOT_PASSWORD=TA3RDA   registry.lab.akyuz.tech/db/mariadb:latest 


  # Şema yükleme
  $ sudo yum install mariadb # kendi sanal makinemize mysql komutu yukluyoruz
  
  $ wget https://repo.akyuz.tech/lab/guestbook/db_init.sql
  
  $ mysql -h 127.0.0.1 -uroot -pTA3RDA < db_init.sql
  
  # MYSQL için oluşturulan poda mariadb yüklenirse aşağıdaki yöntem kullanılabilir.

  podman exec -i mariadb mysql -uroot -predhat < db_init.sql

  # Web
  $ podman run -d --name apache  --network app-net -p 8080:80  \
              -v  /mnt/web_app/:/var/www/html:Z  \
			  -e DB_HOST=mariadb -e DB_USER=root -e DB_PASSWORD=TA3RDA  -e DB_NAME=appdb \
               registry.lab.akyuz.tech/webservers/php-fpm-httpd:rocky9

   $ podman network connect db-net apache


   $ cp -iv index.php /mnt/web_app/ -iv
   
   $ chmod 644  /mnt/web_app/index.php    
   
   $ ls -la /mnt/web_app/



$ sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4"  forward-port port="80" protocol="tcp" to-port="8080" '

$ sudo firewall-cmd --reload

$ sudo firewall-cmd --list-all

$ curl http://127.0.0.1:8080/


# Test: http://app1.lab.akyuz.tech:8080



Uygulamayı servis olarak çalıştırmak:

$ 	~/.config/systemd/user

$ podman generate systemd --new --name apache --files

$ cp -iv container-apache.service ~/.config/systemd/user/

$ podman generate systemd --new --name mariadb --files

$ cp -iv container-mariadb.service ~/.config/systemd/user/

$ systemctl --user daemon-reload

$ systemctl --user status container-mariadb.service container-apache.service

$ systemctl --user enable --now  container-mariadb.service container-apache.service

$ journalctl --user-unit=container-apache

$ journalctl --user-unit=container-mariadb

Troubleshooting kısa notlar:
  podman logs <isim|id>
  systemctl status container-<servis>
  journalctl -f -u container-<servis>
  podman network inspect <ağ>
  firewall-cmd --list-ports


