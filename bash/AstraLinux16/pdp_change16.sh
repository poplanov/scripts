#! /bin/bash
usage()
{
cat << EOF
Usage: $0 mac_label [path...]
EOF
}
IFS=$'\n'
set_label()
{

    local user_lev=$(echo $1|cut -d':' -f1)
    local user_ilev=$(echo $1|cut -d':' -f2)
    local user_cat=$(echo $1|cut -d':' -f3)
    local user_flags=$(echo $1|cut -d':' -f4)
    local root_lbl=$(pdp-ls -Mdn / | awk '{print $5}')
    local max_lev=$(echo $root_lbl | cut -d':' -f1)
    local max_ilev=$(echo $root_lbl | cut -d':' -f2)
    find $2 -type d -exec pdpl-file ${max_lev}:${max_ilev}:-1:ccnr '{}' \;
    find $2 -type f -exec pdpl-file $1 '{}' \;
    find $2 -type l -exec pdpl-file $user_lev:$user_ilev:$user_cat:ccnr '{}' \;
    find $2 -type d | tac | xargs -d '\n' pdpl-file $1
    return 0

}
if [[ -z $1 ]]; then

    usage
    exit 1

fi
mac_label="$1"
shift
if [[ -z $1 ]]; then

    set_label $mac_label $PWD
    exit 0

fi
while [[ -n $@ ]]; do

    set_label $mac_label "$1"
    shift

done
exit 0
