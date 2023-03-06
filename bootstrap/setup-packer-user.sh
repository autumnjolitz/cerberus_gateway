#!/usr/bin/env bash

set -euxo pipefail

HTTP_SERVER='${ http_basename }'
if ! case $HTTP_SERVER in http://*) true;; esac
then
    echo 'HTTP_SERVER ('$HTTP_SERVER') invalid!'
    exit 1
fi

if ! id packer
then
    echo 'Adding our packer user...'
    pw add user packer -G wheel -h - -s /usr/local/bin/bash
fi

mkdir -p /home/packer/.ssh
touch /home/packer/.ssh/authorized_keys
chmod 0700 /home/packer/.ssh
chmod 0600 /home/packer/.ssh/authorized_keys
chown -R packer:packer /home/packer
chown -R packer:packer  -G /home/packer/.ssh
echo 'Adding initial skeletal packer/.ssh folder'
echo "adding $HTTP_SERVER/ssh.pub to ~packer/.ssh/authorized_keys"
curl $HTTP_SERVER/ssh.pub | tee -a /home/packer/.ssh/authorized_keys
sed -i '' -e '$a\' /home/packer/.ssh/authorized_keys
