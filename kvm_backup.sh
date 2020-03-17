#!/bin/bash

# Дата год-месяц-день
data=`date +%Y-%m-%d`
# Папка для бэкапов
backup_dir=/backup-vm
# Список работающих VM
vm_list=`virsh -c qemu:///system list | grep running | awk '{print $2}'`
# Список VM, заданных вручную, через пробел
#vm_list=(vm-1 vm-2)
# Лог файл
logfile="/var/log/kvmbackup.log"

# Использовать это условие, если список VM задается вручную
#for activevm in "${vm_list[@]}";
# Использовать это условие, если список работающих VM берется автоматически
for activevm in $vm_list
    do
        mkdir -p $backup_dir/$activevm
        # Записываем информацию в лог с секундами
        echo "`date +"%Y-%m-%d_%H-%M-%S"` Start backup $activevm" >> $logfile
        # Бэкапим конфигурацию
        virsh dumpxml $activevm > $backup_dir/$activevm/$activevm-$data.xml
        echo "`date +"%Y-%m-%d_%H-%M-%S"` Create snapshots $activevm" >> $logfile
        # Список дисков VM
        disk_list=`virsh -c qemu:///system domblklist $activevm | grep qcow2 | awk '{print $1}'`
        # Адрес дисков VM
        disk_path=`virsh -c qemu:///system domblklist $activevm | grep qcow2 | awk '{print $2}'`
        # Делаем снепшот диcков
        virsh -c qemu:///system snapshot-create-as --domain $activevm snapshot --disk-only --atomic --quiesce --no-metadata
        sleep 2
        for path in $disk_path
            do
                echo "`date +"%Y-%m-%d_%H-%M-%S"` Create backup $activevm $path" >> $logfile
                # Вычленяем имя файла из пути
                filename=`basename $path`
                # Бэкапим диск
                tar czf $backup_dir/$activevm/$filename.gz $path
                sleep 2
            done
        for disk in $disk_list
            do
                # Определяем путь до снепшота
                snap_path=`virsh -c qemu:///system domblklist $activevm | grep $disk | awk '{print $2}'`
                echo "`date +"%Y-%m-%d_%H-%M-%S"` Commit snapshot $activevm $snap_path" >> $logfile
                # Объединяем снепшот
                virsh -c qemu:///system blockcommit $activevm $disk --active --verbose --pivot
                sleep 2
                echo "`date +"%Y-%m-%d_%H-%M-%S"` Delete snapshot $activevm $snap_path" >> $logfile
                # Удаляем снепшот
                rm $snap_path
            done
        echo "`date +"%Y-%m-%d_%H-%M-%S"` End backup $activevm" >> $logfile
    done
