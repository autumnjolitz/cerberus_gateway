#!/bin/sh

set -euxo pipefail

CHROOT_CMD='/usr/sbin/chroot /mnt sh -c'
BUILD_UUID=$(uuidgen)
DISK_NAME="DragonFlyBSD-${BUILD_UUID}"

echo 'GPT initializing /dev/da0...'
gpt init -f -B /dev/da0
echo "Initializing disklabel64 /dev/da0s1 with label: ${DISK_NAME}..."
disklabel64 -B -r -w /dev/da0s1 auto $DISK_NAME
# Extract the existing disklabel
disklabel64 /dev/da0s1 >> /tmp/da0-disklabel.proto
# Append for whole hammer partition with a swap partition
cat << EOF >> /tmp/da0-disklabel.proto
a: 1G 0 4.2BSD
b: 8G * swap
d: * * HAMMER2
EOF
# Install the partition layout
disklabel64 -R da0s1 /tmp/da0-disklabel.proto
rm /tmp/da0-disklabel.proto

# Install boot hierarchy (UFS only because the EFI loader only does UFS)
# 32k block size and 4096 fragments
newfs -L BOOT -b 32768 -f 4096 -g 771957 -h 280 -m 5 /dev/part-by-label/$DISK_NAME.a
mount -t ufs /dev/part-by-label/$DISK_NAME.a /mnt
# Copy boot to the Boot pfs
cpdup -I /boot /mnt/
umount /mnt

echo 'Creating HAMMER2 filesystem @ROOT ...'
newfs_hammer2 -L ROOT /dev/part-by-label/$DISK_NAME.d
mount -t hammer2 /dev/part-by-label/$DISK_NAME.d@ROOT /mnt

echo 'Creating all PFS...'
hammer2 -s /mnt pfs-create usr
hammer2 -s /mnt pfs-create usr.dports
hammer2 -s /mnt pfs-create usr.local
hammer2 -s /mnt pfs-create usr.src
hammer2 -s /mnt pfs-create var
hammer2 -s /mnt pfs-create home
hammer2 -s /mnt pfs-create volatile

mkdir /mnt/boot
mkdir /mnt/dev
mkdir /mnt/etc
mkdir /mnt/home
mkdir /mnt/usr
mkdir /mnt/var
mkdir /mnt/volatile

# Mount the top level pfs
mount -t ufs /dev/part-by-label/$DISK_NAME.a /mnt/boot
mount_hammer2 @usr        /mnt/usr 
mount_hammer2 @var        /mnt/var
mount_hammer2 @home       /mnt/home  
mount_hammer2 @volatile   /mnt/volatile

# create usr and var mountpoints for the special pfs's
mkdir /mnt/usr/distfiles
mkdir /mnt/usr/dports
mkdir /mnt/usr/local
mkdir /mnt/usr/src
mkdir /mnt/var/crash
mkdir /mnt/var/log
mkdir /mnt/var/run
mkdir /mnt/var/spool

# Mount the leaf pfs
mount_hammer2 @usr.dports /mnt/usr/dports
mount_hammer2 @usr.local  /mnt/usr/local 
mount_hammer2 @usr.src    /mnt/usr/src

# Create the volatile directories
mkdir /mnt/volatile/usr.distfiles
mkdir /mnt/volatile/usr.obj
mkdir /mnt/volatile/var.cache
mkdir /mnt/volatile/var.crash
mkdir /mnt/volatile/var.log
mkdir /mnt/volatile/var.run
mkdir /mnt/volatile/var.spool

# Remap volatiles:
mount_null /mnt/volatile/var.crash /mnt/var/crash
mount_null /mnt/volatile/var.log /mnt/var/log
mount_null /mnt/volatile/var.run /mnt/var/run
mount_null /mnt/volatile/var.spool /mnt/var/spool
mount_null /mnt/volatile/usr.distfiles /mnt/usr/distfiles

# remap /dev
mount_null /dev /mnt/dev
echo 'Filling filesystem...'

cpdup -I / /mnt
cpdup -I /root /mnt/root
cpdup -I /usr /mnt/usr
cpdup -I /usr/local /mnt/usr/local
cpdup -I /var /mnt/var
cpdup -I /var/crash /mnt/var/crash
cpdup -I /var/log /mnt/var/log
cpdup -I /var/run /mnt/var/run
cpdup -I /var/spool /mnt/var/spool
cpdup -I /etc.hdd /mnt/etc 

echo 'Cleaning @ROOT...'

rm -rf /mnt/README* /mnt/autorun* /mnt/dflybsd.ico /mnt/index.html

echo 'Creating /boot/loader.conf...'
cat > /mnt/boot/loader.conf << EOF
vfs.root.mountfrom="hammer2:part-by-label/$DISK_NAME.d@ROOT"
if_bridge_load="YES"
pf_load="YES"
pflog_load="YES"
autoboot_delay="3"
EOF

echo 'Creating /etc/fstab...'
cat > /mnt/etc/fstab << EOF
/dev/part-by-label/$DISK_NAME.d@ROOT  /           hammer2 rw          1 1
/dev/part-by-label/$DISK_NAME.a       /boot       ufs     rw          1 1
/dev/part-by-label/$DISK_NAME.b       none        swap    sw          0 0
@usr                                  /usr        hammer2 rw          0 0
@usr.dports                           /usr/dports hammer2 rw          0 0
@usr.local                            /usr/local  hammer2 rw          0 0
@usr.src                              /usr/src    hammer2 rw          0 0
@var                                  /var        hammer2 rw          0 0
@home                                 /home       hammer2 rw,nosuid   0 0
@volatile                             /volatile   hammer2 rw          0 0

proc                         /proc    procfs  rw               0 0
tmpfs                        /tmp     tmpfs rw,nosuid,noexec,nodev    0 0
tmpfs                        /var/tmp tmpfs rw,nosuid,noexec,nodev    0 0

# Remap the volatile pfs
/volatile/usr.distfiles                 /usr/distfiles     null rw 0 0
/volatile/usr.obj                       /usr/obj           null rw 0 0
/volatile/var.cache                     /var/cache         null rw 0 0
/volatile/var.crash                     /var/crash         null rw 0 0
/volatile/var.log                       /var/log           null rw 0 0
/volatile/var.run                       /var/run           null rw 0 0
/volatile/var.spool                     /var/spool         null rw 0 0

EOF

echo "Generating rc.conf..."
cat > /mnt/etc/rc.conf << EOF  
# initial rc.conf
dumpdev="/dev/part-by-label/$DISK_NAME.b"
hostname="dragonfly-${BUILD_UUID}"
ifconfig_em0="DHCP"
sshd_enable="YES"
dntpd_enable="YES"

EOF
echo "Adding /etc/.gitignore"
cat > /mnt/etc/.gitignore << EOF
*.db  # Any binary db file
*/*.db
localtime
nsswitch.conf
host.conf
motd
master.passwd
resolv.conf
dumpdates
ssh/moduli
defaults/
ssh/ssh_host_dsa_key
ssh/ssh_host_dsa_key.pub
ssh/ssh_host_ecdsa_key
ssh/ssh_host_ecdsa_key.pub
ssh/ssh_host_ed25519_key
ssh/ssh_host_ed25519_key.pub
ssh/ssh_host_key
ssh/ssh_host_key.pub
ssh/ssh_host_rsa_key
ssh/ssh_host_rsa_key.pub
ssl/private
os-release
EOF
echo "Adding /usr/local/etc/.gitignore"
cat > /mnt/usr/local/etc/.gitignore << EOF
*.sample
*.example
*/*.sample
*/*.example
zdump
zic
zoneinfo-*
*.png

EOF

echo 'Regenerating password database...'
$CHROOT_CMD 'pwd_mkdb -p /etc/master.passwd'

echo 'Setting root password...'
echo $ROOT_PASSWORD | $CHROOT_CMD 'pw mod user root -h 0'

echo 'Upgrading base packages...'
cp /etc/resolv.conf /mnt/etc/resolv.conf  # This really solved the confusing "I can't find internet" error
$CHROOT_CMD "cd /usr && make pkg-bootstrap-force"
$CHROOT_CMD 'pkg update'
$CHROOT_CMD 'pkg upgrade -y'
echo 'Installing sudo and bash...'
$CHROOT_CMD 'pkg install -y bash sudo'
echo 'Allowing group wheel to sudo...'
cat > /mnt/usr/local/etc/sudoers.d/wheel << EOF
%wheel  ALL=(ALL)       ALL
EOF
rm /mnt/etc/resolv.conf

echo 'Allocate our packer user...'
echo $PACKER_USER_PASSWORD | $CHROOT_CMD 'pw add user packer -G wheel -h 0 -s /usr/local/bin/bash'
# Disable passwd access for this user:

mkdir /mnt/home/packer
(cd /mnt/home/packer && fetch $HTTP_SERVER/ssh.pub)

# Now setup the ssh key for this user
$CHROOT_CMD 'chown -R packer:packer /home/packer'
$CHROOT_CMD 'mkdir /home/packer/.ssh'
$CHROOT_CMD 'chown packer:packer /home/packer/.ssh'
$CHROOT_CMD 'chmod 0700 /home/packer/.ssh'
$CHROOT_CMD 'mv /home/packer/ssh.pub /home/packer/.ssh/authorized_keys'
$CHROOT_CMD 'chmod 0600 /home/packer/.ssh/authorized_keys'

echo "Initializing /etc git repository and logging as first commit."
$CHROOT_CMD 'git config --global user.email "root@localhost"'
$CHROOT_CMD 'git config --global user.name "Root"'
$CHROOT_CMD 'git config --global init.defaultBranch main'
$CHROOT_CMD 'cd /etc && git init && git add .gitignore && git commit -m "[.gitignore] add" && git add -A . && git commit -m "[*] initialized /etc"'
$CHROOT_CMD 'cd /usr/local/etc && git init && git add .gitignore && git commit -m "[.gitignore] add" && git add -A . && git commit -m "[*] initialized /usr/local/etc"'
$CHROOT_CMD 'mtree -i -deU -f /etc/mtree/BSD.var.dist -p /var'
$CHROOT_CMD 'mtree -i -deU -f /etc/mtree/BSD.root.dist -p /'
$CHROOT_CMD 'mtree -i -deU -f /etc/mtree/BSD.usr.dist -p /usr'

echo 'Syncing...'
echo 'Unmounting'
umount /mnt/boot
umount /mnt/usr/distfiles
umount /mnt/usr/dports
umount /mnt/usr/local
umount /mnt/usr/src
umount /mnt/var/crash
umount /mnt/var/log
umount /mnt/var/run
umount /mnt/var/spool
umount /mnt/usr
umount /mnt/var
umount /mnt/dev
umount /mnt/volatile
umount /mnt/home
umount /mnt

