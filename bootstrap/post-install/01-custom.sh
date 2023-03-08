#!/bin/sh
# Custom commands example

perror 'Allowing group wheel to sudo w/o password'
cat > /mnt/usr/local/etc/sudoers.d/wheel << EOF
%wheel  ALL=(ALL)   NOPASSWD:ALL
EOF
perror 'Adding kernel modules to load at boot'
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
