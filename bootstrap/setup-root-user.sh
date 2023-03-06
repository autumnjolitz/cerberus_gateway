#!/usr/bin/env bash

set -euxo pipefail

SOURCE_HOSTNAME="${1:-}"
SOURCE_PORT="${2:-}"

if [ "x$SOURCE_HOSTNAME" = 'x' ] || [ "x$SOURCE_PORT" = 'x' ]
then
    if [ "x$SOURCE_HOSTNAME" = 'x' ]; then
        echo 'missing hostname'
    fi
    if [ "x$SOURCE_PORT" = 'x' ]; then
        echo 'missing port'
    fi
    exit 1
fi

if [ ! -f /root/.ssh/authorized_keys ]
then
    mkdir -p /root/.ssh
    touch /root/.ssh/authorized_keys
    chmod 0700 /root/.ssh
    chmod 0600 /root/.ssh/authorized_keys
fi

curl -s "http://${SOURCE_HOSTNAME}:${SOURCE_PORT}/root.pub" | tee -a /root/.ssh/authorized_keys
sed -i '' -e '$a\' /root/.ssh/authorized_keys
cat >> /etc/ssh/sshd_config << EOF
PermitRootLogin without-password
EOF
# This allows `tail -f /var/log/auth.log` for debugging SSH issues
rcrun enable syslogd
# Start the SSH service
rcrun enable sshd
