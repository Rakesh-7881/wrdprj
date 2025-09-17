#cloud-config
package_update: true
packages:
  - nginx
  - php-fpm
  - php-mysql
  - wget
  - unzip
runcmd:
  - systemctl enable nginx
  - systemctl start nginx
  - cd /var/www
  - wget https://wordpress.org/latest.zip -O /tmp/wordpress.zip
  - unzip /tmp/wordpress.zip -d /tmp
  - cp -r /tmp/wordpress/* /var/www/html/
  - chown -R www-data:www-data /var/www/html
  - chmod -R 755 /var/www/html
  - mv /var/www/html/wp-config-sample.php /var/www/html/wp-config.php
  - sed -i "s/database_name_here/${db_name}/" /var/www/html/wp-config.php
  - sed -i "s/username_here/${db_user}/" /var/www/html/wp-config.php
  - sed -i "s/password_here/${db_pass}/" /var/www/html/wp-config.php
  - sed -i "s/localhost/${db_host}/" /var/www/html/wp-config.php
  - systemctl restart php8.1-fpm || true
  - systemctl restart nginx
