#!/usr/bin/env bash

TARGETHOST="$1"

echo "ssh ${TARGETHOST}"

ansible-playbook -v -i "${TARGETHOST}," site.yml -e '{
"ansible_become_pass": "",
}'

