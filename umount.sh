#!/bin/bash

# Simple program that cleans up the mappings for a device. The name is a
# misnomer, since it doesn't actually unmount the mounted filesystem.
#
# Copyright (C) 2013 Wade T. Cline
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
	# Parse optional arguments.
	while [ $# -gt 0 ]; do
		case "$1" in
		-n|--name)
			shift
			NAME=$1
			shift
			;;
		*)
			usage_print "Unrecognized option: $1"
		esac
	done
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
	echo "./umount.sh [-n <name>]"
	echo ""
	echo "-n|--name: Name for the mapping of the device (default: "
	echo "           \"device\")"
	exit
}

# Validate system pre-requirements.
system_validate

# Parse the arugments.
arguments_parse $@

# Remove the mappings.
./cryptsetup.sh free ${NAME}
