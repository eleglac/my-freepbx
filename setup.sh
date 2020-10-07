#!/bin/bash

### Some notes before we get started
#   1. This initial version of the script was taken wholesale from the following link:
#      https://wiki.freepbx.org/display/FOP/Installing+FreePBX+14+on+Ubuntu+18.04
#      and all credit and rights are retained by whoever already owns them.  Sangoma, I guess?
#      However, I took the liberty of fixing some bugs I saw (see previous commits for notes)
#      and have since added some features (specifically, setting up nftables and fail2ban)
#
#   2. BE SURE TO RUN THIS SCRIPT AS ROOT!  I think a "sudo" should do you, but
#      I can't pretend to know enough about Linux to guarantee it... sudo su definitely works!

### WHAT FOLLOWS IS THE GUIDE ITSELF

### Warnings
# 1. Manual installations of FreePBX is considered an EXPERTS ONLY exercise. This method of installation is enough to get CORE functionality of FreePBX. Non-commercial modules may not function as expected or detailed in the Wiki's. Certain modules and features may require additional software to be installed and configured on the server.
# 1a. **** COMMERCIAL MODULES CANNOT BE INSTALLED ON THIS OS ****
# 2. Do not use the 18.04.1 '-live' ISO image as it has significant, and critical bugs. If you do so, you will need to run the 'Is my installation buggy' fix. Make sure you do not use a -live, image, and instead use an ISO from the cdimages repository.
# 3. For Asterisk 16 you must enable app_macro in make menuselect

### Initial System Setup
# Nothing unusual is required when installing the machine, excepted to install openssh-server to accomplish the first step.
# Note that this installation guide installs PHP 5.6. PHP 7 and higher is NOT SUPPORTED on FreePBX 14, and is provided on a best-effort basis. 
# FreePBX Framework 14.0.3.15 and higher may install successfully with PHP 7, but it is not recommended.

### Allow SSH login as root: (optional, uncomment these two lines to activate when running this script)
# sed -ir 's/#?PermitRootLog.+/PermitRootLogin yes/' /etc/ssh/sshd_config
# systemctl restart sshd

### Check if your system is buggy
# There is an issue with Ubuntu 18.04.1 installing incorrectly - See this ticket for more information:
# https://bugs.launchpad.net/subiquity/+bug/1783129?comments=all
# Run the command 'grep backports /etc/apt/sources.list' and if it does not return anything, you need to run the fix that we supplied in comment 27.  
# Note that this forces the use of the US mirrors. If you're not in the US (eg, if you're in Australia), you can change the URLs from 'us.archive' to 'au.archive', by doing something like 
# sed -i 's/us.archive/au.archive/' /etc/apt/sources.list 
# which will speed up your upgrades and installations dramatically.

### Update your system
# Now that you have ensured your machine is functioning correctly, you can proceed with the installation (and don't forget, you must run all of this as root). 
# Start by installing the PHP 5.6 repository, and doing a complete update.

add-apt-repository ppa:ondrej/php < /dev/null
apt-get update && apt-get upgrade -y 

### Install Dependencies
# Note that this uses an older PHP 5.6. FreePBX 15 supports PHP 7.1 and higher.
# As part of this install, you may be asked (possibly several times) for a mysql password. 
# DO NOT SET A MYSQL PASSWORD AT THIS POINT. 
# Your machine will automatically generate a secure password later in the installation.
# When prompted for Email configuration, make sure you set this correctly! 
# Most machines will select 'Internet with smarthost', and use the SMTP server of your internet provider.

apt-get install -y openssh-server apache2 mysql-server mysql-client \
  mongodb curl sox mpg123 sqlite3 git uuid libodbc1 unixodbc unixodbc-bin \
  asterisk asterisk-core-sounds-en-wav asterisk-core-sounds-en-g722 \
  asterisk-dahdi asterisk-flite asterisk-modules asterisk-mp3 asterisk-mysql \
  asterisk-moh-opsound-g722 asterisk-moh-opsound-wav asterisk-opus \
  asterisk-voicemail dahdi dahdi-dkms dahdi-linux libapache2-mod-security2 \
  php5.6 php5.6-cgi php5.6-cli php5.6-curl php5.6-fpm php5.6-gd php5.6-mbstring \
  php5.6-mysql php5.6-odbc php5.6-xml php5.6-bcmath php-pear libicu-dev gcc \
  g++ make postfix libapache2-mod-php5.6
  
### Install NodeJS

curl -sL https://deb.nodesource.com/setup_10.x | bash -
apt-get install -y nodejs

### Fix Permissions for Asterisk user

useradd -m asterisk
chown asterisk. /var/run/asterisk
chown -R asterisk. /etc/asterisk
chown -R asterisk. /var/{lib,log,spool}/asterisk
chown -R asterisk. /usr/lib/asterisk
chsh -s /bin/bash asterisk
rm -rf /var/www/html

### Remove any 'sample' config files left over, and fix errors
# These are a security vulnerability and must be removed before installing freepbx. 
# There is also an incompatibility in the Ubuntu-supplied asterisk.conf which needs to be fixed.

rm -rf /etc/asterisk/ext* /etc/asterisk/sip* /etc/asterisk/pj* /etc/asterisk/iax* /etc/asterisk/manager*
sed -i 's/.!.//' /etc/asterisk/asterisk.conf

### Update Apache configuration

sed -i 's/\(^upload_max_filesize = \).*/\120M/' /etc/php/5.6/cgi/php.ini
sed -i 's/www-data/asterisk/' /etc/apache2/envvars
sed -i 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf
a2enmod rewrite
service apache2 restart

### Fix 'Pear-GetOpt' compatibility issue.
# The standard 'pear-getopt' uses 'each' which is Deprecated in PHP 7.  This simple patch fixes it

sed -i 's/ each(/ @each(/' /usr/share/php/Console/Getopt.php

### Install MySQL ODBC Connector
# The MySQL ODBC connector is used for CDRs.
mkdir -p /usr/lib/odbc
# NB: the original setup script used a dead link and installed the 5.3.11 connector; this seems to be an adequate fix.
curl -s http://www.mirrorservice.org/sites/ftp.mysql.com/Downloads/Connector-ODBC/5.3/mysql-connector-odbc-5.3.13-linux-ubuntu18.04-x86-64bit.tar.gz | \
  tar -C /usr/lib/odbc --strip-components=2 --wildcards -zxvf - */lib/*so

### Configure ODBC
# Note that this assumes you haven't previously configured ODBC on this machine. If so, you will need to manually add the required data.
# NB: original script had the line Setup=/usr/lib/odbc/libodbcmy5S.so, changed to Setup=.../libmyodbc5S.so

cat > /etc/odbc.ini << EOF
[MySQL-asteriskcdrdb]
Description=MySQL connection to 'asteriskcdrdb' database
driver=MySQL
server=localhost
database=asteriskcdrdb
Port=3306
Socket=/var/run/mysqld/mysqld.sock
option=3
Charset=utf8
EOF
cat > /etc/odbcinst.ini << EOF
[MySQL]
Description=ODBC for MySQL
Driver=/usr/lib/odbc/libmyodbc5w.so
Setup=/usr/lib/odbc/libmyodbc5S.so
FileUsage=1
EOF

### Fix Ubuntu/Debian Paths
# Debian and Ubuntu use /usr/share/asterisk for things like MOH and Sounds. 
# As sounds are now controlled by FreePBX, you need to delete the system sounds, and link them to the correct location.

rm -rf /var/lib/asterisk/moh
ln -s /usr/share/asterisk/moh /var/lib/asterisk/moh
rm -rf /usr/share/asterisk/sounds
ln -s /var/lib/asterisk/sounds /usr/share/asterisk/sounds
chown -R asterisk.asterisk /usr/share/asterisk

### Download and install FreePBX 14

cd /usr/src
wget http://mirror.freepbx.org/modules/packages/freepbx/freepbx-14.0-latest.tgz
tar zxf freepbx-14.0-latest.tgz
cd freepbx
./install -n

# If an error appears after install, then check php verison.
# To downgrade it, launch this cmd line:
# sudo a2dismod php7.x 
# sudo a2enmod php5.6
# sudo update-alternatives --set php /usr/bin/php5.6 
# sudo service apache2 restart

### You've done it!
# You can now start using FreePBX.  Open up your web browser and connect to the IP address or hostname of your new FreePBX server.  
# You will see the Admin setup page, which is where you set your 'admin' account password, and configure an email address to receive update notifications. 

### Install additional modules
# There are (at the time of writing) approximately 50 additional modules that can be installed to enhance the usability of your FreePBX machine.
# - you can install these individually via Module Admin, or, you can simply run 'fwconsole ma installall' to download and install all the additional modules available. 
# We hope you enjoy using FreePBX 14!

### Automatic Startup
# Please note you need to set up FreePBX to start asterisk (and it's associated services) on bootup. 
# You can view an example systemd startup script here:
# http://wiki.freepbx.org/display/HTGS/Example+systemd+startup+script+for+FreePBX

### nftables and fail2ban
#
# Adding these services brings this FreePBX install more in line with EvoPBX, which is what
# I'm more familiar with.  
# REMEMBER TO SET CORRECT MANAGEMENT IPS IN /etc/nftables/nftables_local.conf!
# REMEMBER TO SET CORRECT IGNORE IPS IN /etc/fail2ban/jail.local!

cd ~
apt-get install -y nftables fail2ban

systemctl enable nftables
systemctl enable fail2ban

# some good default nftables and fail2ban configs are in the 'etc' folder
# that came with this repo
# TODO: automatically add those defaults during the above install step
