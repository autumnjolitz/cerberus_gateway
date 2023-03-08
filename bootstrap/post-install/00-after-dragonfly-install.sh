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


perror "Fetching depth 1 of dports into /usr/dports"
$CHROOT_CMD "cd /usr/dports && git init && git remote add origin git://mirror-master.dragonflybsd.org/dports.git && git pull --depth 1"

perror "Cloning kernel/userland sources"
$CHROOT_CMD "make -C /usr src-create-shallow"
perror "packages installed in chroot are:"
$CHROOT_CMD "pkg query -e '%#r == 0' '%n-%v'"