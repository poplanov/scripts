#!/bin/bash
set -x
# Дата год-месяц-день
data=`date +%Y-%m-%d`
# Папка для бэкапов
backup_dir=/DATA/backup
# Список работающих VM
vm_list=`virsh -c qemu:///system list | grep running | awk '{print $2}'`
offvm_list=`virsh -c qemu:///system list --all | grep shut | awk '{print $2}'`
# Список VM, заданных вручную, через пробел
#vm_list=(vm-1 vm-2)
# Лог файл
logfile="/DATA/backup/kvmbackup.log"
echo "-------START BACKUP $data---------" >> $logfile
# Использовать это условие, если список работающих VM берется автоматически
for activevm in $vm_list
    do
        mkdir -p $backup_dir/$activevm
        # Записываем информацию в лог с секундами
        echo "`date +"%Y-%m-%d_%H-%M-%S"` Start backup $activevm" >> $logfile
        # Бэкапим конфигурацию
        virsh -c qemu:///system dumpxml $activevm > $backup_dir/$activevm/$activevm-$data.xml 2>> $logfile
        echo -e "`date +"%Y-%m-%d_%H-%M-%S"` Create snapshots $activevm\n" >> $logfile
        # Список дисков VM
        disk_list=`virsh -c qemu:///system domblklist $activevm | grep qcow2 | awk '{print $1}'`
        # Адрес дисков VM
        disk_path=`virsh -c qemu:///system domblklist $activevm | grep qcow2 | awk '{print $2}'`
        # Делаем снепшот диcков
        virsh -c qemu:///system snapshot-create-as --domain $activevm snapshot --disk-only --atomic --no-metadata 2>> $logfile
        sleep 2
        for path in $disk_path
            do
                echo -e "`date +"%Y-%m-%d_%H-%M-%S"` Create backup $activevm $path\n" >> $logfile
                # Вычленяем имя файла из пути
                filename=`basename $path`
                # Бэкапим диск
                sudo tar czf $backup_dir/$activevm/$filename-$data.tgz $path 2>> $logfile 
                sleep 2
            done
        for disk in $disk_list
            do
                # Определяем путь до снепшота
                snap_path=`virsh -c qemu:///system domblklist $activevm | grep $disk | awk '{print $2}'`
                echo -e "`date +"%Y-%m-%d_%H-%M-%S"` Commit snapshot $activevm $snap_path" >> $logfile
                # Объединяем снепшот
                virsh -c qemu:///system blockcommit $activevm $disk --active --verbose --pivot 2>> $logfile
                sleep 3
                echo -e "\n`date +"%Y-%m-%d_%H-%M-%S"` Delete snapshot $activevm $snap_path\n" >> $logfile
                # Удаляем снепшот
                sudo rm $snap_path
            done
        echo -e "`date +"%Y-%m-%d_%H-%M-%S"` End backup $activevm\n" >> $logfile
done
for offvm in $offvm_list
    do
        mkdir -p $backup_dir/$offvm
        # Записываем информацию в лог с секундами
        echo -e "`date +"%Y-%m-%d_%H-%M-%S"` Start backup $offvm\n" >> $logfile
        # Бэкапим конфигурацию
        virsh dumpxml $offvm > $backup_dir/$offvm/$offvm-$data.xml
        echo -e "`date +"%Y-%m-%d_%H-%M-%S"` Create snapshots $offvm\n" >> $logfile
        # Список дисков VM
        offdisk_list=`virsh -c qemu:///system domblklist $offvm | grep qcow2 | awk '{print $1}'`
        # Адрес дисков VM
        offdisk_path=`virsh -c qemu:///system domblklist $offvm | grep qcow2 | awk '{print $2}'`
        for path in $offdisk_path
            do
                echo -e "`date +"%Y-%m-%d_%H-%M-%S"` Create backup $offvm $path" >> $logfile
                # Вычленяем имя файла из пути
                filename=`basename $path`
                # Бэкапим диск
                sudo tar czf $backup_dir/$offvm/$filename-$data.tgz $path 2>> $logfile
                sleep 2
            done
        echo -e "`date +"%Y-%m-%d_%H-%M-%S"` End backup $offvm\n" >> $logfile
done
echo "----------END BACKUP $date----------" >> $logfile
