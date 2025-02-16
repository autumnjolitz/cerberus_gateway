#!/bin/sh

perror 'Installing sudo, curl, bash...'
chroot-sh 'pkg install -y bash sudo curl'

cat >> "$NEWROOT/etc/rc.conf" << EOF
dhclient_program="/usr/local/sbin/dual-dhclient"

sshd_enable="YES"
EOF

perror "Fetching dports into /usr/dports"
# ARJ: Because we've a special PFS for dports, we can't just rm -rf dports and create
# like via the Makefile. Instead we'll have to init it and then do a pull.
chroot-sh "cd /usr/dports && \
    git init -b master && \
    git remote add origin git://mirror-master.dragonflybsd.org/dports.git && \
    git pull origin master --depth 1 --allow-unrelated-histories && \
    git branch --set-upstream-to=origin/master master"

perror "Cloning kernel/userland sources"
chroot-sh "make -C /usr src-create-shallow"
perror "packages installed in chroot are:"
chroot-sh "pkg query -e '%#r == 0' '%n-%v'"