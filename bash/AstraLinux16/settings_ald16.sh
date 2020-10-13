#!/bin/bash

ip="192.168.1.1"
netmask="255.255.255.0"

hostname="srv-dc"
domain=".mil.ru"
sdomain="mil"

dnssrv="192.168.1.1"
path_to_www=/DATA/www/

### START ###
# 1. network
# 2. openssh-server
# 3. bind9
# 4. ntp server
# 5. ald
# 6. apache2
# 7. postgresql
# 8. ftp

# config network
function network {
echo " 
auto lo
iface lo inet loopback
auto eth0
iface eth0 inet static
	address $ip
	netmask $netmask " > /etc/network/interfaces

echo "127.0.0.1	localhost
$ip	$hostname$domain	$hostname" > /etc/hosts

systemctl restart networking
}

function sshd {
# openssh-server 
if [[ -z `whereis ssh | cut -d ':' -f2` ]]; then
	apt install openssh-server -y
fi

systemctl enable ssh
systemctl restart ssh
}

function bind9 {
# bind9
if [[ -z `whereis bind9 | cut -d ':' -f2` ]]; then
	apt install bind9 -y
fi

fqdn=$hostname$domain
sip=`echo $ip | cut -c1-10`
echo "$TTL 604800
@ IN SOA $fqdn. root$domain. (
20110913 ; Serial
604800 ; Refresh
86400 ; Retry
2419200 ; Expire
604800 ) ; Negative Cache TTL
	IN		NS		$hostname
$hostname           IN		A		$ip
srv-kav         IN              CNAME           $hostname
srv-ossec       IN              CNAME           $hostname
srv-log         IN              CNAME           $hostname
srv-repo         IN              CNAME           $hostname
@               IN              MX      10      $hostname
; for example
srv2	           IN		A		192.168.10.2
arm01           IN              A               192.168.10.101
arm02           IN              A               192.168.10.102
arm03           IN              A               192.168.10.103" > /etc/bind/db.$sdomain


echo "$TTL 604800
@ IN SOA $fqdn. root$domain. (
2011091301 ; Serial
604800 ; Refresh
86400 ; Retry
2419200 ; Expire
604800 ) ; Negative Cache TTL
IN				NS	$fqdn.
1			IN	PTR	$fqdn.
; for example
2			IN	PTR	srv2.mil.ru.
3			IN	PTR	srv3.mil.ru.
N			IN	PTR	srvN.mil.ru.
101			IN	PTR	arm01.mil.ru.
102			IN	PTR	arm02.mil.ru.
103			IN	PTR	arm03.mil.ru." > /etc/bind/db.$sip

revip=`echo $sip | awk 'BEGIN { FS = "."}; { print $3"."$2"."$1}'`
zone=`echo $domain | sed '/./s///'`

cp /etc/bind/named.conf.{local,local_bal} /etc/bind/named.conf.local.bak
echo "zone "$zone" {
type master;
file "/etc/bind/db.$sdomain";
};
zone "$revip.in-addr.arpa" {
type master;
file "/etc/bind/db.$sip";
};">/etc/bind/named.conf.local

echo ". 3600000 IN NS A.ROOT-SERVERS.NET.
A.ROOT-SERVERS.NET.	3600000	A	$ip">/etc/bind/db.root

cp /etc/bind/named.conf.{options,options_bak}
echo "acl \"corpnet\" {$sip.0/24; 127.0.0.1;};
options {
directory \"/var/cache/bind\";
auth-nxdomain no;
listen-on-v6 { any; };
allow-query {\"corpnet\";};
};"> /etc/bind/named.conf.options

echo "search $zone
nameserver $ip" >/etc/resolv.conf
chattr +i /etc/resolv.conf
}

function ntp {
# ntp
cp /etc/ntp.{conf,conf_bak}
echo "driftfile /var/lib/ntp/ntp.drift
statsdir /var/log/ntpstats/
statistics loopstats peerstats clockstats
filegen loopstats file loopstats type day enable
filegen peerstats file peerstats type day enable
filegen clockstats file clockstats type day enable
server 127.127.1.0
fudge 127.127.1.0 stratum 0
restrict -4 default kod notrap nomodify nopeer noquery
restrict -6 default kod notrap nomodify nopeer noquery
restrict 127.0.0.1
restrict ::1
restrict network $sip.0 mask $netmask nomodify notrap">/etc/ntp.conf

systemctl enable ntp
systemctl restart ntp
}

function aldinit {
# ald
cp /etc/ald/ald.conf /etc/ald/ald.conf.orig

sed -i 's/DOMAIN=.*/DOMAIN='$domain'/' /etc/ald/ald.conf
sed -i 's/SERVER=.*/SERVER='$fqdn'/' /etc/ald/ald.conf
if [[ -z `grep TICKET_MAX /etc/ald/ald.conf` ]]; then
	echo "TICKET_MAX_LIFE=7d
TICKET_MAX_RENEWABLE_LIFE=14d" >> /etc/ald/ald.conf
fi

ald-init init
}

function postgresql {
clear

apt-get install -y postgresql-9.6 postgresql-client-9.6 postgresql-contrib-9.6 postgresql-doc-9.6 postgresql-pltcl-9.6 

#set locale
sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
mkdir -p /DATA/main

#dropcluster
pg_dropcluster 9.6 main --stop
pg_createcluster --locale=ru_RU.UTF-8 -d /DATA/main 9.6 main

# files
sed -i "s/#krb_server_keyfile =.*/krb_server_keyfile='\/etc\/postgresql\/9.6\/main\/krb5.keytab'/" /etc/postgresql/9.6/main/postgresql.conf   
sed -i 's/ac_enable_sequence_mac\t=.*/ac_enable_sequence_mac\t= false/' /etc/postgresql/9.6/main/postgresql.conf
sed -i 's/ac_ignore_socket_maclabel\t=.*/ac_ignore_socket_maclabel\t= false/' /etc/postgresql/9.6/main/postgresql.conf
sed -i "s/listen_addresses =.*/listen_addresses =\'*\'/" /etc/postgresql/9.6/main/postgresql.conf

#pg_hba
echo -e "local\t\tall\tpostgres\ttrust
host\t\tall\tpostgres\t127.0.0.1/32\ttrust
host\t\tall\tall\t127.0.0.1/32\tgss
host\t\tall\tall\t$sip.0\tgss" > /etc/postgresql/9.6/main/pg_hba.conf

#pg_tune
memtotal=$(cat /proc/meminfo | grep MemTotal | awk '{ print $2  }')
shared_buffers=$((($memtotal / 6)/1024))
work_mem=$((($memtotal - $shared_buffers) / 20 / 1024))
maintenance_work_mem=$((($memtotal - $shared_buffers) / 4 / 1024))

sed -i 's/shared_buffers =.*/shared_buffers = '$shared_buffers'MB/' /etc/postgresql/9.6/main/postgresql.conf
sed -i 's/#work_mem =.*/work_mem = '$work_mem'MB/' /etc/postgresql/9.6/main/postgresql.conf
sed -i 's/#maintenance_work_mem =.*/maintenance_work_mem = '$maintenance_work_mem'MB/' /etc/postgresql/9.6/main/postgresql.conf
/etc/init.d/postgresql restart
sed -i 's/#random_page_cost =.*/random_page_cost = 2.0/' /etc/postgresql/9.6/main/postgresql.conf
sed -i 's/#effective_cache_size =.*/effective_cache_size = 512MB/' /etc/postgresql/9.6/main/postgresql.conf
sed -i 's/#default_statistics_target =.*/default_statistics_target = 5000/' /etc/postgresql/9.6/main/postgresql.conf
sed -i 's/#join_collapse_limit =.*/join_collapse_limit = 10/' /etc/postgresql/9.6/main/postgresql.conf
sed -i 's/#autovacuum =.*/autovacuum = off/' /etc/postgresql/9.6/main/postgresql.conf

page_size=`getconf PAGE_SIZE`
phys_pages=`getconf _PHYS_PAGES`
shmall=`expr $phys_pages / 2`
shmmax=`expr $shmall \* $page_size`

grep "kernel.shmmax = $shmmax" /etc/sysctl.conf >> /dev/null
if [[ $? -ne 0 ]]; then echo kernel.shmmax = $shmmax >> /etc/sysctl.conf; fi

grep "kernel.shmall = $shmall" /etc/sysctl.conf >> /dev/null
if [[ $? -ne 0 ]]; then echo kernel.shmall = $shmall >> /etc/sysctl.conf; fi

sysctl -p


echo -e "Выполнить на домене:
ald-admin service-add postgres/{fqdn}\nald-admin sgroup-svc-add postgres/{fqdn} --sgroup=mac\n\n
На сервере БД:\n
ald-client update-svc-keytab postgres/{fqdn} --ktfile=\"/etc/postgresql/9.6/main/krb5.keytab\"
chown postgres /etc/postgresql/9.6/main/krb5.keytab"

read -n 1 -s -r -p "Press any key to continue"
}

function apache2 {

# Install packages for apache2
apt-get install -y apache2 libapache2-mod-php7.0 libapache2-mod-auth-kerb php7.0 php7.0-curl php7.0-gd php7.0-pgsql php7.0-xmlrpc php7.0-xsl php7.0-imagick php7.0-intl openssh-server zip rsync bsd-mailx

#Enable mod apache2
a2enmod auth_kerb
a2enmod rewrite

# Set /etc/apache2/site-enabled/000-default
cp /etc/apache2/sites-available/default /etc/apache2/sites-available/default.bak
echo "<VirtualHost *:80>
	ServerAdmin webmaster@localhost

	DocumentRoot /DATA/www
	<Directory />
		Options FollowSymLinks
		AllowOverride None
	</Directory>
	<Directory /DATA/www/>
		Options Indexes FollowSymLinks MultiViews
		AllowOverride All
		Order allow,deny
		allow from all
		AuthType Kerberos
		KrbAuthRealms $domain
		KrbServiceName HTTP/$host.$domain
		Krb5Keytab /etc/apache2/keytab
		KrbSaveCredentials on
		KrbMethodNegotiate on
		KrbMethodK5Passwd off
	</Directory>
ErrorLog ${APACHE_LOG_DIR}/error.log
	LogLevel warn

	CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>" > /etc/apache2/sites-available/default

# create folder for www
mkdir -p $path_to_www
#chown www-data /etc/apache2/keytab
#chmod 644 /etc/apache2/keytab
#chmod 1777 /var/lib/php5
#pdp-flbl 3:0:0xffffffffffffffff:0x5 /var/
#pdp-flbl 3:0:0xffffffffffffffff:0x5 /var/lib
#pdp-flbl 3:0:0xffffffffffffffff:0x5 /var/lib/php/7.0/

# setup php.ini
cp /etc/php/7.0/apache2/php.{ini,bak}
sed -i 's/upload_max_filesize =.*/upload_max_filesize = 2048M/' /etc/php5/apache2/php.ini
sed -i 's/memory_limit =.*/memory_limit = 2048M/' /etc/php5/apache2/php.ini
sed -i 's/post_max_size =.*/post_max_size = 2048M/' /etc/php5/apache2/php.ini
sed -i 's/max_execution_time =.*/max_execution_time = 2048M/' /etc/php5/apache2/php.ini
sed -i "s/;date.timezone =.*/date.timezone = 'Europe\/Moscow'/" /etc/php5/apache2/php.ini
/etc/init.d/apache2 restart
echo "
ald-admin service-add HTTP/$host.$domain
ald-admin sgroup-svc-add HTTP/$host.$domain  --sgroup=mac
ald-client update-svc-keytab HTTP/$host.$domain  --ktfile=\"/etc/apache2/keytab\" 
"
}

function ftp {
apt install vsftpd
cp /etc/vsftpd.{conf,conf_bak}
[ -x /DATA/repo ] || mkdir -p /DATA/repo/
echo "listen=YES
anonymous_enable=YES
use_localtime=YES
xferlog_enable=YES
xferlog_file=/var/log/vsftpd.log
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
rsa_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem
rsa_private_key_file=/etc/ssl/private/ssl-cert-snakeoil.key
ssl_enable=NO" > /etc/vsftpd.conf
sed -i 's/\/srv\/ftp/\DATA\/repo/' /etc/passwd
systemctl enable vsftpd
systemctl restart vsftpd
}


clear
option=0
until [ "$option" = "99" ]; do
echo -e "\t\t\tМеню скрипта\n"
echo -e "\t\tПеред началом развернуть локальный репозитарий!\n"
echo -e "\t1. network"
echo -e "\t2. bind9"
echo -e "\t3. openssh-server"
echo -e "\t4. ntp"
echo -e "\t5. ald"
echo -e "\t6. postgresql"
echo -e "\t7. apache2"
echo -e "\t8. ftp"
#echo -e "\t9. soon dovecot+exim"
#echo -e "\tA. soon cups"
echo -e "\t0. Выход"
echo -en "\t\tВведите номер раздела: "
read option
echo ""
 case $option in
0)
	clear
	option=99
        break ;;
1)
        network ;;
2)
        sshd ;;
3)
        bind9 ;;
4)
        ntp ;;
5)
        aldinit ;;
6)
        postgresql ;;
7)
        apache2 ;;
8)
        ftp ;;
9)
        break ;;
A)
        break ;;
*)

echo "Нужно выбрать раздел";;
esac
done

