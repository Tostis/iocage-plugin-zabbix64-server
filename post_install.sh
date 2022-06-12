#!/bin/sh

#enable all services
echo "Enabling all services..."
sysrc zabbix_agentd_enable="YES" 
sysrc zabbix_server_enable="YES" 
sysrc nginx_enable="YES" 
sysrc php_fpm_enable="YES" 
sysrc mysql_enable="YES" 


# Copy sample files to config files
echo "Creating Zabbix config files..."
ZABBIX_CONFIG_URI="https://raw.githubusercontent.com/xTITUSMAXIMUSX/iocage-plugin-zabbix6-server/master/zabbix.conf.php"
/usr/bin/fetch -o /usr/local/www/zabbix6/conf/zabbix.conf.php ${ZABBIX_CONFIG_URI} 
cp /usr/local/etc/zabbix6/zabbix_agentd.conf.sample /usr/local/etc/zabbix6/zabbix_agentd.conf 
cp /usr/local/etc/zabbix6/zabbix_server.conf.sample /usr/local/etc/zabbix6/zabbix_server.conf 


# update nginx conf
echo "Updating nginx config..."
NGINX_CONFIG_URI="https://raw.githubusercontent.com/xTITUSMAXIMUSX/iocage-plugin-zabbix6-server/master/nginx.conf"
rm /usr/local/etc/nginx/nginx.conf 
/usr/bin/fetch -o /usr/local/etc/nginx/nginx.conf ${NGINX_CONFIG_URI} 
chown www:www /usr/local/etc/nginx/nginx.conf 


# Update php-fpm config
echo "Updating php-fpm config..."
sed -i www.conf s/\;listen\.owner\ \=\ www/listen\.owner\ \=\ www/g /usr/local/etc/php-fpm.d/www.conf 
sed -i www.conf s/\;listen\.group\ \=\ www/listen\.group\ \=\ www/g /usr/local/etc/php-fpm.d/www.conf 
sed -i www.conf s/\;listen\.mode\ \=\ 0660/listen\.mode\ \=\ 0660/g /usr/local/etc/php-fpm.d/www.conf 


# Update PHP.ini
echo "Updating php.ini config"
cp /usr/local/etc/php.ini-production /usr/local/etc/php.ini 
sed -i php.ini s/post\_max\_size\ \=\ 8M/post\_max\_size\ \=\ 16M/g /usr/local/etc/php.ini 
sed -i php.ini s/max\_execution\_time\ \=\ 30/max\_execution\_time\ \=\ 300/g /usr/local/etc/php.ini 
sed -i php.ini s/max\_input\_time\ \=\ 60/max\_input\_time\ \=\ 300/g /usr/local/etc/php.ini 
sed -i php.ini s/\;date\.timezone\ \=\/date\.timezone\ \=\ America\\/Chicago/g /usr/local/etc/php.ini 


# Creating zabbix DB and user
echo -n "Creating Zabbix DB and user..."
service mysql-server start 
mysql_random_pass=$(openssl rand -hex 10)
mysql_admin_pass=$(awk NR==2 /root/.mysql_secret)
mysql_admin_random_pass=$(openssl rand -hex 10)

# Create  secure sql script
echo "UPDATE mysql.user SET Password=PASSWORD('$mysql_admin_random_pass') WHERE User='root';" >> secure_mysql.sql
echo "DELETE FROM mysql.user WHERE User='';" >> secure_mysql.sql
echo "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');" >> secure_mysql.sql
echo "DROP DATABASE IF EXISTS test;" >> secure_mysql.sql
echo "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';" >> secure_mysql.sql
echo "FLUSH PRIVILEGES;" >> secure_mysql.sql

# Create zabbix sql script
echo "create database zabbix character set utf8 collate utf8_bin;" >> createzabbixuser.sql
echo "CREATE USER 'zabbix'@'localhost' IDENTIFIED BY '$mysql_random_pass';" >> createzabbixuser.sql
echo "GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';" >> createzabbixuser.sql

# Run sql scripts
mysql -u root < secure_mysql.sql 
mysql -u root --password="$mysql_admin_random_pass" < createzabbixuser.sql 
mysql -u root --password="$mysql_admin_random_pass" zabbix < /usr/local/share/zabbix6/server/database/mysql/schema.sql 
mysql -u root --password="$mysql_admin_random_pass" zabbix < /usr/local/share/zabbix6/server/database/mysql/images.sql 
mysql -u root --password="$mysql_admin_random_pass" zabbix < /usr/local/share/zabbix6/server/database/mysql/data.sql 
echo " ok"

# update zabbix.conf.php file
sed -i zabbix.conf.php "9s/'';/'$mysql_random_pass';/g" /usr/local/www/zabbix6/conf/zabbix.conf.php
chown -R www:www /usr/local/www/zabbix6/conf/ 

# Add DB password to zabbix server config
sed -i zabbix_server.conf "s/# DBPassword=/DBPassword=$mysql_random_pass/g" /usr/local/etc/zabbix6/zabbix_server.conf

#Adding Usernames and passwords to post install notes
echo "Mysql Root Password: $mysql_admin_random_pass" > /root/PLUGIN_INFO
echo "Mysql Zabbix DB: zabbix" >> /root/PLUGIN_INFO
echo "Mysql Zabbix User: zabbix" >> /root/PLUGIN_INFO
echo "Mysql Zabbix Password: $mysql_random_pass" >> /root/PLUGIN_INFO
echo "Defualt Web Username: Admin" >> /root/PLUGIN_INFO
echo "Defualt Web Password: zabbix" >> /root/PLUGIN_INFO

# Starting services
echo "Staring services..."
service nginx start 
service zabbix_agentd start 
service zabbix_server start 
service php-fpm start 