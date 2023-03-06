#!/usr/bin/env bash

set -euxo pipefail

SOURCE_HOSTNAME="${1:-}"
SOURCE_PORT="${2:-}"
USERNAME="${3:-}"
if [ "x$USERNAME" = 'x' ]
then
    echo 'username not given, assuming packer!'
    USERNAME='packer'
fi
GROUP=${USERNAME}

if [ "x$USERNAME" = 'xroot' ]
then
    HOME_DIRECTORY='/root'
    GROUP='wheel'
else
    HOME_DIRECTORY="/home/${USERNAME}"
fi

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

if ! id ${USERNAME}
then
    echo "Adding our ${USERNAME} user..."
    pw add user ${USERNAME} -G wheel -h - -s /usr/local/bin/bash
fi


if [ ! -f $HOME_DIRECTORY/.ssh/authorized_keys ]
then
    mkdir -p $HOME_DIRECTORY/.ssh
    touch $HOME_DIRECTORY/.ssh/authorized_keys
fi

chmod 0700 $HOME_DIRECTORY/.ssh
chmod 0600 $HOME_DIRECTORY/.ssh/authorized_keys
chown -R $USERNAME:$GROUP $HOME_DIRECTORY
chown -R $USERNAME:$GROUP $HOME_DIRECTORY/.ssh

curl -s "http://${SOURCE_HOSTNAME}:${SOURCE_PORT}/${USERNAME}.pub" | tee -a $HOME_DIRECTORY/.ssh/authorized_keys
sed -i '' -e '$a\' $HOME_DIRECTORY/.ssh/authorized_keys
if [ "x$USERNAME" = 'xroot' ]
then
    if ! grep -qE '^PermitRootLogin without-password' /etc/ssh/sshd_config
    then
        cat >> /etc/ssh/sshd_config << EOF
PermitRootLogin without-password
EOF
        if ((service -e | grep -q sshd) && service sshd status)
        then
            echo 'Configuration to SSH changed! Restarting!'
            service sshd restart
        fi
    fi
fi

if ! service -e | grep -q syslogd
then
    # This allows `tail -f /var/log/auth.log` for debugging SSH issues
    rcrun enable syslogd
else
    if ! service syslogd status
    then
        service syslogd start
    fi
fi
if ! service -e | grep -q sshd
then
    # Start the SSH service
    rcrun enable sshd
else
    if ! service sshd status
    then
        service sshd start
    fi
fi
