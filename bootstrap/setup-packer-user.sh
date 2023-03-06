#!/usr/bin/env bash

set -euxo pipefail

HTTP_SERVER=${1:-}
if [ "x${HTTP_SERVER}" = "x" ]
then
    echo 'HTTP_SERVER not passed in as first argument!'
    exit 1
fi

if ! id packer
then
    echo 'Adding our packer user...'
    pw add user packer -G wheel -h - -s /usr/local/bin/bash
    mkdir -p /home/packer
    chown -R packer:packer /home/packer
fi

if [ ! -d /home/packer/.ssh ]
then
    echo 'Adding initial skeletal packer/.ssh folder'
    mkdir /home/packer/.ssh
    chown packer:packer /home/packer/.ssh
    chmod 0700 /home/packer/.ssh
fi

if [ ! -f /home/packer/.ssh/authorized_keys ]
then
    echo 'Adding initial skeletal packer/.ssh/authorized_keys'
    touch /home/packer/.ssh/authorized_keys
    chown packer:packer /home/packer/.ssh/authorized_keys
    chmod 0600 /home/packer/.ssh/authorized_keys
fi

echo "adding ${HTTP_SERVER}/ssh.pub to ~packer/.ssh/authorized_keys"
curl $HTTP_SERVER/ssh.pub | tee -a /home/packer/.ssh/authorized_keys
