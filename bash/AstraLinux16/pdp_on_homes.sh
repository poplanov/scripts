#!/bin/bash

# Установка метки безопасности после 
#           переноса экспортируемых домашних каталогов пользователей 

# Функция назначения метки безопасности
IFS=$'\n'
set_label()
{

    local root_lbl=$(pdp-ls -Mdn / | cut -d' ' -f6)
    local max_lev=$(echo $root_lbl | cut -d':' -f1)
    local max_ilev=$(echo $root_lbl | cut -d':' -f2)
    find $2 -type d -exec pdp-flbl ${max_lev}:${max_ilev}:-1:ccnr,ccnri '{}' \;
    find $2 -type f -exec pdp-flbl $1 '{}' \;
    find $2 -type d | tac | xargs -d '\n' pdp-flbl $1
    return 0

}

#Поиск каталогов 
for i in `find /ald_export_home/ -type d -name "l*[0-9]"`; do
	#Получение уровневого каталога
	lvldir=$(echo $i | tr / "\n" | tail -1 | head -1)

	#Формирование метки безопасности
	lvlmac=$(echo $lvldir | cut -c2)
	integrmac=$(echo $lvldir | cut -c4)
	catmac=$(echo $lvldir | cut -c6-8)
	attrmac=$(echo $lvldir | cut -c10-12)
	
	#Создаем линки на рабочий стол и mac
	echo "ln -s ~/Desktops/Desktop1 ~/Рабочий\ стол" > $i/.bash_profile
		
	#Установка метки безопасности на уровневые каталоги
	set_label $lvlmac:$integrmac:$catmac:$attrmac $i
done

read -p "Set mac label finished. Press enter to exit..."
