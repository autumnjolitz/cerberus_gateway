#!/bin/sh

NEWROOT='/mnt'

if case "$(mount |  cut -d' ' -f3)" in *"$NEWROOT"*) true ;; *) false ;; esac; then
    >&2 echo "${NEWROOT}"' is already mounted, changing $NEWROOT'
    NEWROOT="$(mktemp -d)"
    >&2 echo '... now is '"${NEWROOT}"
fi

CHROOT=/usr/sbin/chroot
CHROOT_CMD="${CHROOT}"' '"${NEWROOT}"' sh -c'
TZ="${TZ:-America/Los_Angeles}"

chroot-run () {
    "${CHROOT}" "${NEWROOT}" /usr/bin/env $@
}

chroot-pkg () {
    "${CHROOT}" "${NEWROOT}" /usr/bin/env pkg $@
}

chroot-sh () {
    "${CHROOT}" "${NEWROOT}" sh -c "$@"
}

if [ "x${SCRIPT_HOME:-}" = 'x' ]; then
    a="/$0"; a="${a%/*}"; a="${a:-.}"; a="${a##/}/"; SCRIPT_HOME="$(cd "$a"; pwd)"
fi

perror() { 
    printf "[$(date -Iseconds)] %s\n" "$*" >&2; 
}

initialize_disk () {
    local disk="${1:-}"
    local disk_name="${2:-}"
    if [ "x${disk}" = 'x' ]; then
        perror 'disk not provided in first argument!'
        return 1
    fi
    if [ "x${disk_name}" = 'x' ]; then
        perror 'disk_name (second argument) must be provided!'
        return 1
    fi
    perror "Using ${disk}"
    if ! case "$disk" in /dev/*) true;; *) false ;; esac
    then
        perror "The device ${disk} must start with /dev"'!'
        return 2
    fi
    if [ ! -e "$disk" ]
    then
        perror "$disk cannot be found"'!'
        return 3
    fi
    perror "GPT initializing $disk..."
    gpt init -f -B -E "$disk"
    perror "Initializing disklabel64 ${disk}s1 with label: ${disk_name}..."
    disklabel64 -B -r -w "${disk}s1" auto "$disk_name"
    # Extract the existing disklabel
    disklabel64 "${disk}s1" >> "/tmp/$(basename $disk)-disklabel.proto"
    # Append for whole hammer partition with a swap partition
    cat << EOF >> "/tmp/$(basename $disk)-disklabel.proto"
a: 1G 0 4.2BSD
b: 8G * swap
d: * * HAMMER2
EOF
    # Install the partition layout
    disklabel64 -R "${disk}s1" "/tmp/$(basename $disk)-disklabel.proto"
    rm "/tmp/$(basename $disk)-disklabel.proto"
    return 0
}


setup_boot () {
    local disk_name="${1:-}"
    if [ "x${disk_name}" = 'x' ]; then
        perror 'disk_name (first argument) must be provided!'
        return 1
    fi
    # Install boot hierarchy (UFS only because the EFI loader only does UFS)
    local blocksize='16384'
    perror "Creating UFS boot partition"
    ls /dev/part-by-label/
    newfs \
        `# Label as boot` \
        -L BOOT \
        -b "${blocksize}" \
        -f "$(echo "${blocksize} 8 /p" | dc)" \
        `# Average file size of /boot` \
        -g 1035 \
        `# number of all files / number of all dirs = avg files per dir` \
        -h 276 \
        -m 10 "/dev/part-by-label/$disk_name.a"
    mount -t ufs "/dev/part-by-label/$disk_name.a" $NEWROOT
    # Copy boot to the Boot pfs
    perror "Copying /boot into place"
    cpdup -I /boot $NEWROOT/
    umount $NEWROOT
    perror "Copied /boot into place [Done]"
}

setup_hammer2 () {
    local disk_name="${1:-}"
    if [ "x${disk_name}" = 'x' ]; then
        perror 'disk_name (first argument) must be provided!'
        return 1
    fi

    perror 'Creating HAMMER2 filesystem @ROOT ...'
    newfs_hammer2 -L ROOT "/dev/part-by-label/$disk_name.d"
    mount -t hammer2 "/dev/part-by-label/$disk_name.d@ROOT" $NEWROOT

    perror 'Creating all PFS...'
    hammer2 -s $NEWROOT pfs-create usr
    hammer2 -s $NEWROOT pfs-create usr.dports
    hammer2 -s $NEWROOT pfs-create usr.local
    hammer2 -s $NEWROOT pfs-create usr.src
    hammer2 -s $NEWROOT pfs-create var
    hammer2 -s $NEWROOT pfs-create home
    hammer2 -s $NEWROOT pfs-create volatile
    hammer2 -s $NEWROOT pfs-create opt

    mkdir $NEWROOT/boot
    mkdir $NEWROOT/dev
    mkdir $NEWROOT/etc
    mkdir $NEWROOT/home
    mkdir $NEWROOT/usr
    mkdir $NEWROOT/var
    mkdir $NEWROOT/volatile
    mkdir $NEWROOT/opt

    # Mount the top level pfs
    mount -t ufs "/dev/part-by-label/$disk_name.a" $NEWROOT/boot
    mount_hammer2 @usr        $NEWROOT/usr 
    mount_hammer2 @var        $NEWROOT/var
    mount_hammer2 @home       $NEWROOT/home  
    mount_hammer2 @volatile   $NEWROOT/volatile
    mount_hammer2 @opt        $NEWROOT/opt

    # create usr and var mountpoints for the special pfs's
    mkdir $NEWROOT/usr/distfiles
    mkdir $NEWROOT/usr/dports
    mkdir $NEWROOT/usr/local
    mkdir $NEWROOT/usr/src
    mkdir $NEWROOT/var/crash
    mkdir $NEWROOT/var/log
    mkdir $NEWROOT/var/run
    mkdir $NEWROOT/var/spool

    # Mount the leaf pfs
    mount_hammer2 @usr.dports $NEWROOT/usr/dports
    mount_hammer2 @usr.local  $NEWROOT/usr/local 
    mount_hammer2 @usr.src    $NEWROOT/usr/src

    # Create the volatile directories
    mkdir $NEWROOT/volatile/usr.distfiles
    mkdir $NEWROOT/volatile/usr.obj
    mkdir $NEWROOT/volatile/var.cache
    mkdir $NEWROOT/volatile/var.crash
    mkdir $NEWROOT/volatile/var.log
    mkdir $NEWROOT/volatile/var.run
    mkdir $NEWROOT/volatile/var.spool

    # Remap volatiles:
    mount_null $NEWROOT/volatile/var.crash $NEWROOT/var/crash
    mount_null $NEWROOT/volatile/var.log $NEWROOT/var/log
    mount_null $NEWROOT/volatile/var.run $NEWROOT/var/run
    mount_null $NEWROOT/volatile/var.spool $NEWROOT/var/spool
    mount_null $NEWROOT/volatile/usr.distfiles $NEWROOT/usr/distfiles

    # remap /dev
    mount_null /dev $NEWROOT/dev
}

install_dragonfly() {
    local disk_name="${1:-}"
    if [ "x${disk_name}" = 'x' ]; then
        perror 'disk_name (first argument) must be provided!'
        return 1
    fi

    perror 'Filling filesystem...'
    copy_files

    perror 'Creating /boot/loader.conf...'
    cat > $NEWROOT/boot/loader.conf << EOF
vfs.root.mountfrom="hammer2:part-by-label/$disk_name.d@ROOT"
autoboot_delay="3"
EOF

    perror 'Creating /etc/fstab...'
    cat > $NEWROOT/etc/fstab << EOF
/dev/part-by-label/$disk_name.d@ROOT  /              hammer2 rw                        1 1
/dev/part-by-label/$disk_name.a       /boot          ufs     rw                        1 1
/dev/part-by-label/$disk_name.b       none           swap    sw                        0 0
@usr                                  /usr           hammer2 rw                        0 0
@usr.dports                           /usr/dports    hammer2 rw                        0 0
@usr.local                            /usr/local     hammer2 rw                        0 0
@usr.src                              /usr/src       hammer2 rw                        0 0
@var                                  /var           hammer2 rw                        0 0
@home                                 /home          hammer2 rw,nosuid                 0 0
@volatile                             /volatile      hammer2 rw                        0 0
@opt                                  /opt           hammer2 rw                        0 0

proc                                  /proc          procfs  rw                        0 0
tmpfs                                 /tmp           tmpfs   rw,nosuid,noexec,nodev    0 0
tmpfs                                 /var/tmp       tmpfs   rw,nosuid,noexec,nodev    0 0

# Remap the volatile pfs
/volatile/usr.distfiles               /usr/distfiles null    rw                        0 0
/volatile/usr.obj                     /usr/obj       null    rw                        0 0
/volatile/var.cache                   /var/cache     null    rw                        0 0
/volatile/var.crash                   /var/crash     null    rw                        0 0
/volatile/var.log                     /var/log       null    rw                        0 0
/volatile/var.run                     /var/run       null    rw                        0 0
/volatile/var.spool                   /var/spool     null    rw                        0 0

EOF

    cat > $NEWROOT/etc/rc.conf << EOF  
# initial rc.conf
dumpdev="/dev/part-by-label/$disk_name.b"

EOF

    perror 'Regenerating password database...'
    chroot-sh 'pwd_mkdb -p /etc/master.passwd'
    perror 'Setting root password to empty...'
    chroot-sh 'chpass -p "" root'
    # Enable internet inside chroot
    cp /etc/resolv.conf $NEWROOT/etc/resolv.conf  # This really solved the confusing "I can't find internet" error
    cp /etc/ssl/cert.pem $NEWROOT/etc/ssl/cert.pem # This avoids needing to do an insecure fetch of the certs!
    init_packages
}

copy_files () {
    cpdup -I / $NEWROOT
    cpdup -I /root $NEWROOT/root
    cpdup -I /usr $NEWROOT/usr
    cpdup -I /usr/local $NEWROOT/usr/local
    cpdup -I /var $NEWROOT/var
    cpdup -I /var/crash $NEWROOT/var/crash
    cpdup -I /var/log $NEWROOT/var/log
    cpdup -I /var/run $NEWROOT/var/run
    cpdup -I /var/spool $NEWROOT/var/spool
    if [ -d /etc.hdd ]; then
        perror "Copying /etc.hdd to $NEWROOT"
        cpdup -I /etc.hdd $NEWROOT/etc 
    else
        perror "/etc.hdd not found, assuming /etc can be used instead"
        cpdup -I /etc $NEWROOT/etc 
    fi
    if [ -d $NEWROOT/etc/.git ]; then
        perror "Removing prior git hierachy from $NEWROOT/etc"
        rm -rf $NEWROOT/etc/.git
    fi
    if [ -d $NEWROOT/usr/local/etc/.git ]; then
        perror "Removing prior git hierachy from $NEWROOT/usr/local/etc"
        rm -rf $NEWROOT/usr/local/etc/.git
    fi
}

cleanup () {
    perror 'Cleaning @ROOT...'
    rm -rf $NEWROOT/README* $NEWROOT/autorun* $NEWROOT/dflybsd.ico $NEWROOT/index.html
    # Remove the ssh key
    perror 'Zeroing out authorized_keys if present'
    truncate -s 0 $NEWROOT/root/.ssh/authorized_keys
    if [ -f $NEWROOT/etc/resolv.conf ]; then
        perror "Removing internet access override"
        rm $NEWROOT/etc/resolv.conf
    fi
    perror 'correcting permissions'
    chroot-sh 'mtree -i -deU -f /etc/mtree/BSD.var.dist -p /var'
    chroot-sh 'mtree -i -deU -f /etc/mtree/BSD.root.dist -p /'
    chroot-sh 'mtree -i -deU -f /etc/mtree/BSD.usr.dist -p /usr'
    perror 'initializing version control for /etc and /usr/local/etc'
    version_control_etc
}



init_packages () {
    chroot-sh "cd /usr && make pkg-bootstrap-force"
    chroot-pkg update
    perror 'Upgrading base packages...'
    chroot-pkg upgrade -y
    perror 'updating index again'
    chroot-pkg update
    perror "Checking for $(pwd)/packages.txt"
    if [ -f packages.txt ]; then
        local pkglist="$(grep -o '^[^#]*' packages.txt | xargs)"
        if [ "x$pkglist" = "x" ]; then
            perror "packages.txt empty"
        else
            perror "Installing $pkglist"
            chroot-pkg install -y $pkglist
        fi
    fi
}

version_control_etc () {
    if [ ! -f $NEWROOT/etc/,gitignore ]; then
        perror "Default initing ${NEWROOT}/etc/.gitignore"
        cat > $NEWROOT/etc/.gitignore << EOF
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
    fi
    if [ ! -f $NEWROOT/usr/local/etc/.gitignore ]; then
        perror "Default initing ${NEWROOT}/usr/local/etc/.gitignore"
        cat > $NEWROOT/usr/local/etc/.gitignore << EOF
*.sample
*.example
*/*.sample
*/*.example
zdump
zic
zoneinfo-*
*.png

EOF
    fi
    perror "Initializing /etc and /usr/local/etc git repository and logging as first commit."
    chroot-sh 'git config --global user.email "root@localhost"'
    chroot-sh 'git config --global user.name "Root"'
    chroot-sh 'git config --global init.defaultBranch main'
    chroot-sh 'cd /etc && git init && git add .gitignore && git commit -m "[.gitignore] add" && git add -A . && git commit -m "[*] initialized /etc"'
    chroot-sh 'cd /usr/local/etc && git init && git add .gitignore && git commit -m "[.gitignore] add" && git add -A . && git commit -m "[*] initialized /usr/local/etc"'
}


unmount () {
    perror 'Syncing...'
    sync
    perror 'Unmounting'
    for mountpt in $NEWROOT/boot $NEWROOT/usr/distfiles $NEWROOT/usr/dports $NEWROOT/usr/local $NEWROOT/usr/src $NEWROOT/var/crash $NEWROOT/var/log $NEWROOT/var/run $NEWROOT/var/spool $NEWROOT/usr $NEWROOT/var $NEWROOT/dev $NEWROOT/volatile $NEWROOT/home $NEWROOT
    do
        if [ -d "$mountpt" ]
        then
            if ! umount "$mountpt"
            then
                sync
                sleep 3
                perror "Force unmounting $mountpt"
                sync
                umount -f "$mountpt"
            fi
        else
            perror "$mountpt is not mounted"'!!!'
        fi
    done
    sync
}

on_post_install_error () {
    perror 'Unhandled error in handling post-install scripts!'
    unmount
}

run_post_install_scripts () {
    trap on_post_install_error EXIT
    perror "Looking at $SCRIPT_HOME/post-install for scripts..."
    for stage in $(ls -1 $SCRIPT_HOME/post-install)
    do
        perror "Executing $stage"
        . $SCRIPT_HOME/post-install/$stage
        perror "Executed $stage."
    done
    trap - EXIT
}

export NEWROOT

