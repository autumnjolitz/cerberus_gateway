#!/bin/sh

cat >> /mnt/etc/rc.conf << EOF
# rename em0 to a friendly name
ifconfig_em0_name="ext0"
# Use DHCP for ip addresses
ifconfig_ext0="DHCP"

sshd_enable="YES"
syslogd_enable="YES"

EOF

perror 'Installing sudo and bash...'
$CHROOT_CMD 'pkg install -y bash sudo'

perror "Cloning kernel/userland sources"
$CHROOT_CMD "cd /usr && make src-create-shallow"
