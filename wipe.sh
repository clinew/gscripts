#!/bin/bash

# Simple script that wipes the specified hard drives with psuedo-random 
# numbers.
#
# Copyright (C) 2013  Wade T. Cline
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


BLOCK_SIZE=4096
ITERATION_COUNT=7
SHUTDOWN=0
TEMP=""


# Print the usage message and exit the program.
function usage_print {
	# Print an optional error message.
	if [ $# -gt 0 ]; then
		echo "ERROR: $1"
	fi

	# Print the usage message.
	echo ""
	echo "USAGE: ./wipe.sh [-s] [-b block_size] [-n iterations] devices..."
	echo ""
	echo "-s: Shutdown the computer after wiping (default: no shutdown)."
	echo "-b: Blocksize to use when wiping (default: 4096)."
	echo "-n: Number of times to wipe each drive (default: 7)."

	# Exit the program
	exit 1
}


# Validate arguments.
if [ $EUID -ne 0 ]; then
	usage_print "Only 'root' may run this script."
fi

# Parse arguments.
while [ "${1:0:1}" == "-" ]; do
	case "$1" in
	-b) # Parse block size.
		shift
		# Check for positive number.
		if ! [[ $1 =~ ^[0-9]+$ ]]; then
			usage_print "'$1' is not a positive number."
		elif [ ${1} -eq 0 ]; then
			usage_print "Block size must be greater than zero."
		fi
		# Check for power of two.
		TEMP=$1
		while [ $TEMP -ne 1 ]; do
			if [ $(($TEMP % 2)) -ne 0 ]; then
				usage_print "Block size must be a power of two, was: $1."
			fi
			TEMP=$(($TEMP / 2))
		done
		# Assign the value.
		BLOCK_SIZE=$1
		shift
		;;
	-n) # Parse iteration count.
		shift
		# Check for positive number.
		if ! [[ ${1} =~ ^[0-9]+$ ]]; then
			usage_print "Iteration count must be a positive number, was: $1."
		elif [ ${1} -eq 0 ]; then
			usage_print "Iteration count must be greater than zero."
		fi
		# Assign the value.
		ITERATION_COUNT=$1
		shift
		;;
	-s) # Parse shutdown status.
		shift
		SHUTDOWN=1
		;;
	*)
		usage_print "Unrecognized option: $1"
	esac
done

# Parse devices.
if [ $# -eq 0 ]; then
	usage_print "Must specify one or more devices to wipe."
fi
for DEVICE in $@; do	
	if ! [ -b $DEVICE ]; then
		usage_print "${DEVICE} is not a block device file."
	fi
done

# Wipe drives.
for (( i=0 ; i < ${ITERATION_COUNT} ; i++ )); do
	echo "Beginning wiping iteration ${i} of ${ITERATION_COUNT}."
	for DEVICE in $@; do
		echo "Wiping ${DEVICE}."
		dd if=/dev/urandom of=${DEVICE} bs=${BLOCK_SIZE}
	done
done
echo "Done wiping."

# Shutdown the computer.
if [ $SHUTDOWN -eq 1 ]; then
	echo "Shutting down."
	init 0
fi
