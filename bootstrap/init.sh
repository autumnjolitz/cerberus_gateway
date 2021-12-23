#!/bin/sh

set -eu

CHROOT_CMD='/usr/sbin/chroot /mnt sh -c'
BUILD_UUID=$(uuidgen)
DISK_NAME="DragonFlyBSD-${BUILD_UUID}"

echo 'GPT initializing /dev/da0...'
gpt init -f -B /dev/da0
echo "Initializing disklabel64 /dev/da0s1 with label: ${DISK_NAME}..."
disklabel64 -B -r -w /dev/da0s1 auto $DISK_NAME
disklabel64 /dev/da0s1 >> /tmp/da0-disklabel.proto

cat << EOF >> /tmp/da0-disklabel.proto
a: * 0 HAMMER2
b: 8G * swap
EOF

disklabel64 -R da0s1 /tmp/da0-disklabel.proto
rm /tmp/da0-disklabel.proto

echo 'Creating HAMMER2 filesystem @ROOT ...'
newfs_hammer2 -L ROOT /dev/part-by-label/$DISK_NAME.a

mount /dev/part-by-label/$DISK_NAME.a@ROOT /mnt
echo 'Creating @BOOT PFS...'
hammer2 -s /mnt pfs-create BOOT
mkdir /mnt/boot
mount /dev/part-by-label/$DISK_NAME.a@BOOT /mnt/boot

echo 'Filling filesystem...'
set -x
cpdup -I / /mnt
cpdup -I /boot /mnt/boot
cpdup -I /var /mnt/var
mkdir -p /mnt/dev
mount -t null /dev /mnt/dev
cpdup -I /usr/local/etc /mnt/usr/local/etc
cpdup -I /root /mnt/root
set +x

echo 'Cleaning @ROOT...'
cd /mnt
rm -rf README* autorun* dflybsd.ico index.html etc
mv etc.hdd etc
cd /

echo 'Creating /boot/loader.conf...'
cat > /mnt/boot/loader.conf << EOF
vfs.root.mountfrom="hammer2:part-by-label/$DISK_NAME.a@ROOT"
if_bridge_load="YES"
pf_load="YES"
pflog_load="YES"
autoboot_delay="3"
EOF

echo 'Creating /etc/fstab...'
cat > /mnt/etc/fstab << EOF
/dev/part-by-label/$DISK_NAME.a@ROOT  /      hammer2 rw                                1 1
/dev/part-by-label/$DISK_NAME.a@BOOT  /boot  hammer2 rw                                1 1
/dev/part-by-label/$DISK_NAME.b       none   swap    sw                                0 0
tmpfs                                 /tmp   tmpfs   rw,nosuid,nodev,noatime,size=256M 0 0
proc                                  /proc  procfs  rw                                0 0
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

echo 'Syncing...'
sync
echo 'Unmounting /mnt/boot...'
umount /mnt/boot
umount /mnt/dev
echo 'Unmounting /mnt...'
umount /mnt
