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


perror "Fetching dports into /usr/dports"
# ARJ: Because we've a special PFS for dports, we can't just rm -rf dports and create
# like via the Makefile. Instead we'll have to init it and then do a pull.
$CHROOT_CMD "cd /usr/dports && \
    git init -b master && \
    git remote add origin git://mirror-master.dragonflybsd.org/dports.git && \
    git pull origin master --depth 1 --allow-unrelated-histories && \
    git branch --set-upstream-to=origin/master master"

perror "Cloning kernel/userland sources"
$CHROOT_CMD "make -C /usr src-create-shallow"
perror "packages installed in chroot are:"
$CHROOT_CMD "pkg query -e '%#r == 0' '%n-%v'"