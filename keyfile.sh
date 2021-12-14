#!/bin/bash

# Simple script that creates a keyfile using a loopback device and the kernel
# random-number generator.
# Copyright (C) 2014 Wade T. Cline
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Validate system pre-requirements.
system_validate() {
	# Check for 'losetup'.
	if ! command -v losetup > /dev/null; then
		usage_print "Unable to find 'losetup' utility"
	fi
}

# Print the usage message and exit the program.
# 1:	An error message (optional).
usage_print() {
	# Print the error message.
	if [ $# -gt 0 ]; then
		echo "ERROR: ${1}."
		echo ""
	fi

	# Print the usage message.
	echo "USAGE:"
	echo "./keyfile.sh <filename>"
	echo ""
	
	# Exit failure.
	exit 1
}

# Validate arguments.
if [ $# -ne 1 ]; then
	usage_print "Invalid argument count: $#"
fi

# Validate system.
system_validate

# Set up the file.
truncate -s 1536 ${1}
if [ $? -ne 0 ]; then
	usage_print "Error creating file: $?"
fi

# Set up the loopback device.
LOOP_DEVICE=`losetup -f`
losetup ${LOOP_DEVICE} ${1}
if [ $? -ne 0 ]; then
	usage_print "Error creating loop device: $?"
fi

# Get the random numbers.
echo "Getting random numbers. Remember to create lots of entropy by mashing"
echo "on the keyboard. It make take a few screens-worth of mashed keys, so"
echo "be patient!"
dd if=/dev/random of=${LOOP_DEVICE}

# Deactive the loopback device.
losetup -d ${LOOP_DEVICE}
