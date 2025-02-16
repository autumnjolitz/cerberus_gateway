#!/bin/sh

set -euo pipefail

a="/$0"; a="${a%/*}"; a="${a:-.}"; a="${a##/}/"; SCRIPT_ROOT="$(cd "$a"; pwd)"

. "$SCRIPT_ROOT/common.sh"

DISK="${1:-}"
DISK_NAME="${2:-}"

if [ "x$DISK" = 'x' ]; then

    case "$(echo /dev/*)" in 
        *"/dev/nvme"[0-9]*)
            DISK="$(echo /dev/nvme[0-9]* | cut -f1 -d' ')"
            perror 'detected nvme disk '"${DISK}"
            ;;
        *"/dev/da"[0-9]*)
            DISK="$(echo /dev/da[0-9]* | cut -f1 -d' ')"
            perror 'detected scsi disk '"${DISK}"
            ;;
        *"/dev/ad"[0-9]*)
            DISK="$(echo /dev/ad[0-9]* | cut -f1 -d' ')"
            perror 'detected ata disk '"${DISK}"
            ;;
        *)
            perror 'Disk not given in the first argument and unable to deduce type!'
            exit 1
            ;;
    esac
    perror "Autodetected destination as '${DISK}'"
fi

BUILD_UUID="$(uuidgen)"
if [ "x${DISK_NAME}" = 'x' ]; then
    DISK_NAME="DragonFlyBSD-${BUILD_UUID}"
    perror "Disk name (argument 2) not specified, setting to ${DISK_NAME}"
fi

if [ ! -d "$SCRIPT_ROOT/post-install" ]; then
    perror "$SCRIPT_ROOT/post-install folder does not exist, making"'!'
    mkdir -p "$SCRIPT_ROOT/post-install"
fi


initialize_disk "$DISK" "$DISK_NAME"
setup_boot "$DISK_NAME"
setup_hammer2 "$DISK_NAME"
install_dragonfly "$DISK_NAME"

run_post_install_scripts
