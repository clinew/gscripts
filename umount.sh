#!/bin/bash

# Simple program that cleans up the mappings for a device. The name is a
# misnomer, since it doesn't actually unmount the mounted filesystem.
#
# Copyright (C) 2013, 2021 Wade T. Cline
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#/

# Name for the mapping of the device.
NAME="device"

# Parse arguments.
arguments_parse() {
	# Parse switch arguments.
	while getopts "n:" opt; do
		case "$opt" in
		n)
			NAME="${OPTARG}"
			shift
			;;
		*)
			usage_print "Unknown argument: $opt"
			;;
		esac
		shift
	done

	# Parse optional positional argument
	if [ $# -gt 0 ]; then
		MOUNT_PATH="$1"
		shift
	fi
}

# Check for installed tools.
system_validate() {
	# Check for 'cryptsetup'.
	if ! command -v cryptsetup > /dev/null; then
		usage_print "Unable to find 'cryptsetup' utility."
	fi
}

# Print the usage message and exit.
usage_print() {
	# Print specific error message.
	if [ $# -eq 1 ]; then
		echo "ERROR: $1"
	fi

	# Print usage message.
	echo "./umount.sh [-n <name>] [path]"
	echo ""
	echo "     path: Path to unmount and to remove mappings from"
	echo ""
	echo "       -n: Name for the mapping of the device (default: "
	echo "           \"device\")"
	exit
}

# Validate system pre-requirements.
system_validate

# Parse the arugments.
arguments_parse $@

# Unmount via mount path.
if [ -n "${MOUNT_PATH}" ]; then
	# Find mount source.
	NAME="$(basename "$(findmnt -n -o SOURCE "${MOUNT_PATH}")")"

	# Unmount the path.
	umount "${MOUNT_PATH}"
	ret=$?
	if [ $ret -ne 0 ]; then
		# Unmount failed.
		exit 1
	fi
fi

# Remove the mappings.
./cryptsetup.sh free "${NAME}"
