#!/bin/sh
# Custom commands example

perror 'Allowing group wheel to sudo w/o password'
cat > $NEWROOT/usr/local/etc/sudoers.d/wheel << EOF
%wheel  ALL=(ALL)   NOPASSWD:ALL
EOF
perror 'Adding kernel modules to load at boot'
cat >> $NEWROOT/boot/loader.conf << EOF
boot_serial="YES"
comconsole_speed="115200"
console="comconsole"
if_ena_load="YES"
if_bridge_load="YES"
pf_load="YES"
pflog_load="YES"
# ichsmb_load="YES"
# corepower_load="YES"
nvmm_load="YES"
tpm_load="YES"
snd_hda_load="YES"
kern.cam.scsi_delay=1000

EOF

# chroot-sh 'curl https://sh.rustup.rs -sSf | sh'
chroot-sh 'pkg install -y $(pkg search -S pkg-name "cloud-init" | col | cut -f1 | head -1)'

# install dhcp wrapper
DHCLIENT_WRAPPER=/usr/local/share/dhclient-wrapper

for filename in $(echo "${NEWROOT}/usr/local/etc/rc.d/"cloud*)
do
    perror 'Prepending '"${DHCLIENT_WRAPPER}"' to PATH'
    sed -i '' 's|PATH=|PATH='"${DHCLIENT_WRAPPER}/bin"':|g' "$filename"
done

perror 'cloudinit rc.d: 

'"$(cat "${NEWROOT}/usr/local/etc/rc.d/cloudinit")"



mkdir -p "${NEWROOT}/${DHCLIENT_WRAPPER}/bin"

cat >> "${NEWROOT}/${DHCLIENT_WRAPPER}/bin/dhclient" << EOF


EOF

chmod +x $NEWROOT/usr/local/bin/dhclient

perror 'Setting up rc.conf with just cloudinit, no extra conf'
cat >> $NEWROOT/etc/rc.conf << EOF
# ARJ: disabled this -- cloudinit may have other ideas
# ifconfig_ena0="DHCP"
# ifconfig_ena1="DHCP"
# ifconfig_ena2="DHCP"
# ifconfig_ena3="DHCP"

cloudinit_enable="YES"
EOF

perror 'Silence warnings from ssh_import_id failing due to platform'
cat >> "$NEWROOT/usr/local/etc/cloud/cloud.cfg" << EOF

# Allow ssh public keys to work ? (ARJ doubtful :/)
unverified_modules: ["ssh_import_id"]
EOF

for filename in $(echo "$NEWROOT/usr/local/etc/cloud/cloud.cfg.d/"*.cfg)
do
    if [ "$(head -1 "$filename")" != '#cloud-config' ]; then
        perror "${filename} lacks a '#cloud-config' header"'! Adding'
        sed -i '' '1s/^/#cloud-config\n/' "$filename"
    fi
done
perror "Running hammer2 cleanup"
chroot-run hammer2 cleanup
perror "Running hammer2 cleanup [Done]"

# chroot-sh 'export BUILD_HOME="$(mktemp -d)" && \
# cd "$BUILD_HOME" && \
# mkdir -p /opt/aws-cli && \
# curl -sLv https://awscli.amazonaws.com/awscli.tar.gz | tar -xzvf - --strip-components 1 &&
# ./configure --prefix=/opt/aws-cli --with-download-deps --with-install-type=portable-exe &&
# make &&
# make install && \
# /opt/aws-cli/bin/aws --version && \
# cd .. &&
# rm -rf "$BUILD_HOME"
# '


# ARJ: draw rest of the owl
# chroot-sh 'pkg install go121 gmake && \
# git clone https://github.com/autumnjolitz/amazon-ssm-agent.git --depth 1 -b ports/dragonflybsd && \
# cd amazon-ssm-agent && gmake build-dragonfly package-dragonfly && \
# pkg add -I bin/dragonfly_amd64/pkg/amazon-ssm-agent-Latest.pkg && \
# rm -rf amazon-ssm-agent && pkg remove -y go121 gmake'
