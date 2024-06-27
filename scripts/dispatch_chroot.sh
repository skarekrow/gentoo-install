#!/bin/bash
set -uo pipefail


[[ $EXECUTED_IN_CHROOT != "true" ]] \
	&& { echo "This script must not be executed directly!" >&2; exit 1; }

# Source the systems profile
source /etc/profile

# Set default emerge flags for parallel emerges
export EMERGE_DEFAULT_OPTS="--jobs=10"

# Unset critical variables
unset key

# Execute the requested command
exec "$@"
