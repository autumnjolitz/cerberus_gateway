#!/bin/sh
# Custom commands example

perror 'Allowing group wheel to sudo w/o password'
cat > /mnt/usr/local/etc/sudoers.d/wheel << EOF
%wheel  ALL=(ALL)   NOPASSWD:ALL
EOF

cat >> /mnt/boot/loader.conf << EOF
if_bridge_load="YES"
pf_load="YES"
pflog_load="YES"
ichsmb_load="YES"
corepower_load="YES"
nvmm_load="YES"
EOF

cat >> /mnt/etc/sysctl.conf <<EOF
kern.cam.da.0.trim_enabled=1
EOF

perror 'Building world and kernel in nrelease for fast use of nrelease (slow!)'
$CHROOT_CMD "cd /usr/src/nrelease && time make buildworld1 buildkernel1"
