#!/bin/sh

set -euo pipefail

a="/$0"; a="${a%/*}"; a="${a:-.}"; a="${a##/}/"; ROOT=$(cd "$a"; pwd)

. $ROOT/common.sh

DISK=${1:-}
DISK_NAME=${2:-}
HOSTNAME=${3:-}

if [ "x$DISK" = 'x' ]; then
    perror 'Disk not given in the first argument!'
    exit 1
fi

BUILD_UUID=$(uuidgen)
if [ "x${DISK_NAME}" = 'x' ]; then
    DISK_NAME="DragonFlyBSD-${BUILD_UUID}"
    perror "Disk name (argument 2) not specified, setting to ${DISK_NAME}"
fi
if [ "x${HOSTNAME}" = 'x' ]; then
    HOSTNAME=$(echo "dragonfly-${BUILD_UUID}" |  cut -c -16)
    perror "Hostname (argument 3) not specified, setting to ${HOSTNAME}"
fi

if [ ! -d $ROOT/post-install ]; then
    perror "$ROOT/post-install folder does not exist, making"'!'
    mkdir -p $ROOT/post-install
fi


initialize_disk $DISK $DISK_NAME
setup_boot $DISK_NAME
setup_hammer2 $DISK_NAME
install_dragonfly $DISK_NAME $HOSTNAME

run_post_install_scripts

cleanup
unmount
