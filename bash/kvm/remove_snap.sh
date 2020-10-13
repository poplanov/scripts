#!/bin/bash

data=`date '+%Y-%m-%d'`
logfile="/DATA/backup/kvm_snap.log"


list_vm=`virsh -c qemu:///system list --all | tail -n +3 | awk '{print $2}'`
echo "--------[$data]-Start removing olderes snapshot---------" >> $logfile
for vm in $list_vm; do 
	for snap in `virsh -c qemu:///system snapshot-list $vm | tail -n +3 | awk '{print $1}'`; 
	do 
		if [[ `date -d "-14day" '+%Y-%m-%d'` == $snap ]]; 
		then 
			echo "[$data]---VM is $vm. Snapshot $snap will be remove" >>$logfile
		    virsh -c qemu:///system snapshot-delete $vm --snapshotname $snap 2>>$logfile
			echo "[$data]---Vm is $vm. Snapshot $snap is removed"; >> $logfile
		fi 
	done; 
done;
echo "--------[$data]-Stop removing olderes snapshot---------" >> $logfile


# Удаление резервых копий дисков и конфигов старше 3 недель
echo "--------[$data]-Start removing old backups-------------" >> $logfile
sudo find /DATA/backup -type f -mtime +21 -delete 2>> $logfile
echo "--------[$data]-Stop removing old backups-------------" >> $logfile

