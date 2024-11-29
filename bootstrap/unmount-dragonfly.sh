#!/bin/sh

set -euo pipefail

a="/$0"; a="${a%/*}"; a="${a:-.}"; a="${a##/}/"; ROOT=$(cd "$a"; pwd)

. $ROOT/common.sh

cleanup
unmount
