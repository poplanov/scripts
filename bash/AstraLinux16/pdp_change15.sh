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

    local root_lbl=$(pdp-ls -Mdn / | cut -d' ' -f6)
    local max_lev=$(echo $root_lbl | cut -d':' -f1)
    local max_ilev=$(echo $root_lbl | cut -d':' -f2)
    find $2 -type d -exec pdp-flbl ${max_lev}:${max_ilev}:-1:ccnr,ccnri '{}' \;
    find $2 -type f -exec pdp-flbl $1 '{}' \;
    find $2 -type d | tac | xargs -d '\n' pdp-flbl $1
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
