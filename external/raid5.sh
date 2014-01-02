#!/bin/bash

# Script that will either format an encrypted RAID-5 device or try to
# mount the encrypted RAID-5 device.
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

# Block size for the filesystem.
BLOCK_SIZE=4096
# Chunk size for the RAID-5 array (in KB).
CHUNK_SIZE=512
# Command for the script.
COMMAND=""
# Devices in the RAID-5 array.
DEVICES=""
# Mappings for the devices in the RAID-5 array.
MAPPINGS=""
# Passphrase for the specified devices.
PASSPHRASE=""
# Salt for the specified devices.
SALT=""
# Name for the mapping of the RAID-5 array.
RAID_NAME="/dev/md0"

# Parses the arguments.
function arguments_parse {
	# Parse argument count.
	if [ $# -lt 1 ]; then
		usage_print "Must specify a command"
	fi

	# Parse the command.
	COMMAND=${1}
	shift

	# Parse the passphrase.
	if [ $# -lt 1 ]; then
		usage_print "Must specify a passphrase"
	fi
	PASSPHRASE=${1}
	shift

	# Parse the salt.
	if [ $# -lt 1 ]; then
		usage_print "Must specify a salt"
	fi
	SALT=${1}
	shift

	# Parse the devices.
	if [ $# -lt 3 ]; then
		usage_print "RAID-5 arrays use at least 3 devices; specified: $#"
	fi
	DEVICES=($@)
	for DEVICE in ${DEVICES}; do
		if [ ! -b ${DEVICE} ]; then
			usage_print "Not a block device: ${DEVICE}."
		fi
	done
}

# Formats the specified encrypted devices as a RAID-5 array.
function raid_format {
	# Prepare each of the specified devices. 
	for DEVICE in ${DEVICES[@]}; do
		# Get the device name.
		DEVICE_NAME=`echo ${DEVICE} | sed "s/.*\///"`

		# Generate a keyfile for the device.
		DEVICE_KEY="${DEVICE_NAME}.key"
		./keyfile.sh "${DEVICE_KEY}"
		if [ $? -ne 0 ]; then
			usage_print "Error generating keyfile for ${DEVICE}"
		fi

		# Initialize the mapping.
		./cryptsetup.sh init -n ${DEVICE_NAME} -k ${DEVICE_KEY} ${DEVICE} ${PASSPHRASE} ${SALT}
		if [ $? -ne 0 ]; then
			usage_print "Error generating mapping for ${DEVICE}"
		fi
		MAPPINGS=("${MAPPINGS[@]}" "/dev/mapper/${DEVICE_NAME}")
	done

	# Create the RAID-5 array.
	mdadm --create --verbose -c ${CHUNK_SIZE} ${RAID_NAME} --level=5 --raid-devices=${#DEVICES[@]} ${MAPPINGS[*]}

	# Format the RAID-5 array.
	STRIDE=$(( (${CHUNK_SIZE} * 1024) / ${BLOCK_SIZE} ))
	STRIPE_WIDTH=$(( ${STRIDE} * (${DEVICE_COUNT} - 1) ))
	mkfs.ext4 -m 1 -b ${BLOCK_SIZE} -E stride=${STRIDE},stripe-width=${STRIPE_WIDTH} ${RAID_NAME} 	
}

# Sets up the mappings for the specified encrypted devices as a RAID-5 array.
function raid_init {
	# Prepare each of the specified devices.
	if [ ! -b ${RAID_NAME} ]; then
		# Prepare each of the specified devices.
		for DEVICE in ${DEVICES[@]}; do
			# Get the device name.
			DEVICE_NAME=`echo ${DEVICE} | sed "s/.*\///"`

			# Get the keyfile name.
			DEVICE_KEY="${DEVICE_NAME}.key"

			# Initialize the mapping.
			./cryptsetup.sh init -n ${DEVICE_NAME} -k ${DEVICE_KEY} ${DEVICE} ${PASSPHRASE} ${SALT}
			if [ $? -ne 0 ]; then
				usage_print "Error getting mapping for ${DEVICE}"
			fi
			MAPPINGS=("${MAPPINGS[@]}" "/dev/mapper/${DEVICE_NAME}")
			mdadm -Q "/dev/mapper/${DEVICE_NAME}"
		done

		# Assemble the array.
		mdadm --assemble ${RAID_NAME} ${MAPPINGS[*]}
		if [ $? -ne 0 ]; then
			usage_print "Assembling array failed: $?"
		fi
	fi	
}

# Check system pre-requirements.
function system_validate {
	# Check for 'mdadm' utility.
	if ! command -v mdadm > /dev/null; then
		usage_print "Unable to find 'mdadm' utility"
	fi
}

# Prints a usage message and then exits the program.
# 1:	An error message (optional).
function usage_print {
	# Print the error message.
	if [ $# -gt 0 ]; then
		echo "ERROR: ${1}."
		echo ""
	fi

	# Print the usage message.
	echo "USAGE:"
	echo "./raid5.sh <format|init> <passphrase> <salt> <device1> <device2> <device3> ..."
	echo ""
	echo "  format: Formats the specified encrypted devices as a RAID-5 array."
	echo "  init: Maps the specified encrypted devices as a RAID-5 array."
	exit 1
}

# Validate the system.
system_validate

# Parse the arguments.
arguments_parse $@

# Call the appropriate command.
case "${COMMAND}" in
format)
	raid_format
	;;
init)
	raid_init
	;;
*)
	usage_print "Command ${COMMAND} not recognized"
esac
