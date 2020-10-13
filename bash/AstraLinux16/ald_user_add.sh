#!/bin/bash
# Generate users list
for num on {1..100}; do echo user$num >> userslist.txt

# Генерируем passfile (пароли вписываем свои)
echo "K/M:12345678" > passfile
echo "admin/admin:12345678" >> passfile
echo "default/user:12345678" >> passfile
chmod 400 passfile


for username in `cat userslist.txt`;
do
    echo "$username:12345678" >> passfile
    until (ald-admin user-add "$username" --home-type=local --group="Domain Users" -f --pass-file passfile);do sleep 1;done
# Мандатные уровни для создаваемых учетных записей
    ald-admin user-mac "$username" --min-lev-int 0 --max-lev-int 3 -f --pass-file passfile
done
rm -f passfile
