#!/bin/bash
##############################
#                            #
#  Создание снепшотов в вм   #
#         qemu/kvm           #  
#                            # 
##############################
set -x
data=`date +%Y-%m-%d`
logfile='/DATA/backup/kvm_snap.log'

#Получаем список ВМ
list_vm=`virsh -c qemu:///system list --all | tail -n +3 | awk '{print $2}'`
echo -e "\n----------Start create snapshots---------\n"
#Создаем снепшоты для вм с текущей датой
for vm in $list_vm
do
	echo -e "\n`date +"%Y-%m-%d_%H:%M:%S"` Start create snapshot for $vm" >> $logfile
	virsh -c qemu:///system snapshot-create-as --domain $vm --name "$data" --description "Snapshot at `date +"%Y-%m-%d_%H:%M:%S"`" >>$logfile
	echo -e "`date +"%Y-%m-%d_%H:%M:%S"` End create snapshot for $vm\n" >> $logfile
done
echo -e "\n----------End create snapshots---------\n"
