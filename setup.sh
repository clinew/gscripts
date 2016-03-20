#!/bin/bash

# Script that will setup the root filesystem for a Gentoo OS.
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

# Block size for the root filesystem.
BLOCK_SIZE=4096
# Chunk size for a RAID-5 array (in KB).
CHUNK_SIZE=512
# How to set up the root filesystem.
COMMAND=""
# Devices to mount.
DEVICES=""
# Whether to format the specified device.
FORMAT=`false`
# Encryption mappings for the devices.
MAPPINGS=""
# Where to mount the root filesystem.
MOUNTPOINT="/mnt/gentoo"
# Passphrase for the specified devices.
PASSPHRASE=""
# Name for the RAID-5 device.
RAID_NAME="/dev/md0"
# Salt for the encrypted devices.
SALT="GoGetYourOwnSalt"

# Parse the arguments.
arguments_parse() {
	# Parse the command.
	if [ $# -lt 1 ]; then
		usage_print "Must specify a command"
	fi
	COMMAND=${1}
	shift

	# Parse any optional arguments.
	while [ "${1:0:1}" == '-' ]; do
		case "${1}" in
		-f|--format) # Format the device.
			FORMAT=true
			;;
		-h|--help)
			usage_print
			;;
		-m|--mountpoint)
			shift
			MOUNTPOINT=${1}
			if [ ! -d ${MOUNTPOINT} ]; then
				usage_print "Not a directory: ${MOUNTPOINT}"
			fi
			;;
		*) # Do nothing.
			;;
		esac
		shift
	done

	# Parse each block device.
	TEMP=($@)
	DEVICES=()
	for DEVICE in ${TEMP[@]}; do
		# Check for block device.
		if [[ ! -e ${DEVICE} ]]; then
			echo -n "Device '${DEVICE}' does not exist! Continue "
			echo "without? [y/N]"
			read INPUT
			if [[ ! -z ${INPUT} && ("${INPUT}" == "y" || "${INPUT}" == "Y") ]]; then
				continue
			else
				die "'${DEVICE}' does not exist"
			fi
		elif [ ! -b ${DEVICE} ]; then
			usage_print "Not a block device: ${DEVICE}"
		fi
		DEVICES+=(${DEVICE})
	done
}

# Print the erorr message and exit failure.
# 1:	Specified error message to print.
die() {
	# Print the error message.
	echo "ERROR: $1."

	# Exit failure.
	exit 1
}

# Reads the passphrase from the user.
passphrase_get() {
	local AGAIN=true
	local DONE=`false`
	local VERIFY=""

	# Read and possibly verify the passphrase.
	until [ ${DONE} ]; do
		# Read the passphrase.
		echo "Enter passphrase:"
		read -s PASSPHRASE

		# Verify the passphrase.
		if [ ${FORMAT} ]; then
			echo "Verify passphrase:"
			read -s VERIFY
		else
			# Or not.
			VERIFY=${PASSPHRASE}
		fi

		# Check passphrase match.
		if [ "${PASSPHRASE}" != "${VERIFY}" ]; then # Failure.
			# See if the user wishes to try again.
			echo "Passphrases do not match."
			echo "Try again? [Y/n]"
			read AGAIN
			if [ ${AGAIN} == "n" ]; then # Quitting.
				exit
			fi
			continue
		fi

		# Verified.
		DONE=true
	done
}

# Setup the root filesystem as an encrypted RAID-1 array.
# TODO: This code was copied from the RAID-5 code; refactor to remove
# duplicate work.
setup_raid1() {
	local ARGUMENTS="" # Extra arguments for 'mdadm'

	# Check for required utilities.
	validate_command "cryptsetup"
	validate_command "losetup"
	validate_command "mdadm"
	if [ ${FORMAT} ]; then
		validate_command "mkfs.ext4"
	fi
	validate_command "mkpasswd"

	# Check device count.
	if [ ${#DEVICES[@]} -lt 2 ]; then
		local INPUT=""

		# Formatting requires at least two devices.
		if [ ${FORMAT} ]; then
			usage_print "RAID-1 requires at least 2 devices; '${#DEVICES[@]}' specified"
		fi

		# Check if user wants a degraded mount.
		echo "Only '${#DEVICES[@]}' devices specified. Normal operation requires at least two devices. Continue anyways? [y/N]"
		read INPUT
		if [[ ! -z ${INPUT} && ("${INPUT}" == "y" || "${INPUT}" == "Y") ]]; then
			ARGUMENTS="--run"
			echo "Continuing..."
		else
			die "Quitting due to small device count"
		fi
	fi

	# Prepare each of the specified devices.
	for DEVICE in ${DEVICES[@]}; do
		local DONE=`false`

		# Get the device name.
		DEVICE_NAME=`echo ${DEVICE} | sed " s/.*\///"`

		# Get the keyfile.
		DEVICE_KEY="${DEVICE_NAME}.key"
		if [ ${FORMAT} ]; then
			# Generate a keyfile.
			echo "Generating keyfile '${DEVICE_KEY}' for '${DEVICE}'."
			./keyfile.sh "${DEVICE_KEY}"
			if [ $? -ne 0 ]; then
				die "Error generating keyfile for '${DEVICE}'"
			fi
		else
			if [ ! -f ${DEVICE_KEY} ]; then
				die "Device key '${DEVICE_KEY}' not found"
			fi
		fi

		# Initialize the encryption mappings.
		until [ ${DONE} ]; do
			# Initialize the mapping.
			./cryptsetup.sh init -n ${DEVICE_NAME} -k ${DEVICE_KEY} ${DEVICE} ${PASSPHRASE} ${SALT}
			if [ $? -ne 0 ]; then
				die "Error generating mapping for '${DEVICE}': $?"
			fi

			# Check for RAID-1 device.
			if [ ! ${FORMAT} ]; then
				mdadm --examine "/dev/mapper/${DEVICE_NAME}"
				if [ $? -ne 0 ]; then
					local AGAIN=""

					# Free the mapping.
					./cryptsetup.sh free ${DEVICE_NAME}

					# Prompt to re-enter passphrase.
					echo "Device '/dev/mapper/${DEVICE_NAME}' does not appear to be a RAID-5 device."
					echo "Re-enter passphrase (y) or quit (n)? [Y/n]"
					read AGAIN
					if [ ${AGAIN} == "n" ]; then # Quit.
						exit 1
					fi
					passphrase_get
					continue
				fi
			fi

			# Add the device to the mapping list.
			MAPPINGS=("${MAPPINGS[@]}" "/dev/mapper/${DEVICE_NAME}")
			DONE=true
		done
	done

	# Prepare the RAID-1 array.
	if [ ${FORMAT} ]; then
		# Create the RAID-1 array.
		mdadm --create --verbose ${RAID_NAME} --level=1 --raid-devices=${#DEVICES[@]} ${MAPPINGS[@]}
		if [ $? -ne 0 ]; then
			die "Error creating array: $?"
		fi

		# Format the filesystem.
		mkfs.ext4 -m 1 -b ${BLOCK_SIZE} ${RAID_NAME}
		if [ $? -ne 0 ]; then
			die "Error formatting filesystem: $?"
		fi
	else
		# Assemble the RAID-1 array.
		mdadm --assemble ${ARGUMENTS} ${RAID_NAME} ${MAPPINGS[@]}
		if [ $? -ne 0 ]; then
			die "Error assembling array: $?"
		fi
	fi

	# Mount the RAID-1 array.
	mount -t ext4 ${RAID_NAME} ${MOUNTPOINT}
	if [ $? -ne 0 ]; then
		die "Error mounting array: $?"
	fi
}

# Setup the root filesystem as an encrypted RAID-5 array.
setup_raid5() {
	local ARGUMENTS="" # Extra arguments for 'mdadm'

	# Check for required utilities.
	validate_command "cryptsetup"
	validate_command "losetup"
	validate_command "mdadm"
	if [ ${FORMAT} ]; then
		validate_command "mkfs.ext4"
	fi
	validate_command "mkpasswd"

	# Check device count.
	if [ ${#DEVICES[@]} -lt 3 ]; then
		local INPUT=""

		# Formatting requires at least three devices.
		if [ ${FORMAT} ]; then
			usage_print "RAID-5 requires at least 3 devices; '${#DEVICES[@]}' specified"
		fi

		# Check if user wants a degraded mount.
		echo "Only '${#DEVICES[@]}' devices specified. Normal operation requires at least three devices. Continue anyways? [y/N]"
		read INPUT
		if [[ ! -z ${INPUT} && ("${INPUT}" == "y" || "${INPUT}" == "Y") ]]; then
			ARGUMENTS="--run"
			echo "Continuing..."
		else
			die "Quitting due to small device count"
		fi
	fi

	# Prepare each of the specified devices.
	for DEVICE in ${DEVICES[@]}; do
		local DONE=`false`

		# Get the device name.
		DEVICE_NAME=`echo ${DEVICE} | sed " s/.*\///"`

		# Get the keyfile.
		DEVICE_KEY="${DEVICE_NAME}.key"
		if [ ${FORMAT} ]; then
			# Generate a keyfile.
			echo "Generating keyfile ${DEVICE_KEY} for ${DEVICE}."
			./keyfile.sh "${DEVICE_KEY}"
			if [ $? -ne 0 ]; then
				die "Error generating keyfile for ${DEVICE}"
			fi
		else
			if [ ! -f ${DEVICE_KEY} ]; then
				die "Device key ${DEVICE_KEY} not found"
			fi
		fi

		# Initialize the encryption mappings.
		until [ ${DONE} ]; do
			# Initialize the mapping.
			./cryptsetup.sh init -n ${DEVICE_NAME} -k ${DEVICE_KEY} ${DEVICE} ${PASSPHRASE} ${SALT}
			if [ $? -ne 0 ]; then
				die "Error generating mapping for ${DEVICE}: $?"
			fi

			# Check for RAID-5 device.
			if [ ! ${FORMAT} ]; then
				mdadm --examine "/dev/mapper/${DEVICE_NAME}"
				if [ $? -ne 0 ]; then
					local AGAIN=""

					# Free the mapping.
					./cryptsetup.sh free ${DEVICE_NAME}

					# Prompt to re-enter passphrase.
					echo "Device /dev/mapper/${DEVICE_NAME} does not appear to be a RAID-5 device."
					echo "Re-enter passphrase (y) or quit (n)? [Y/n]"
					read AGAIN
					if [ ${AGAIN} == "n" ]; then # Quit.
						exit 1
					fi
					passphrase_get
					continue
				fi
			fi
			
			# Add the device to the mapping list.
			MAPPINGS=("${MAPPINGS[@]}" "/dev/mapper/${DEVICE_NAME}")
			DONE=true
		done
	done

	# Prepare the RAID-5 array.
	if [ ${FORMAT} ]; then
		# Create the RAID-5 array.
		mdadm --create --verbose -c ${CHUNK_SIZE} ${RAID_NAME} --level=5 --raid-devices=${#DEVICES[@]} ${MAPPINGS[@]}
		if [ $? -ne 0 ]; then
			die "Error creating array: $?"
		fi

		# Format the filesystem.
		local STRIDE=$(( (${CHUNK_SIZE} * 1024) / ${BLOCK_SIZE} ))
		local STRIPE_WIDTH=$(( ${STRIDE} * (${DEVICE_COUNT} - 1) ))
		mkfs.ext4 -m 1 -b ${BLOCK_SIZE} -E stride=${STRIDE},stripe-width=${STRIPE_WIDTH} ${RAID_NAME}
		if [ $? -ne 0 ]; then
			die "Error formatting filesystem: $?"
		fi
	else
		# Assemble the RAID-5 array.
		mdadm --assemble ${ARGUMENTS} ${RAID_NAME} ${MAPPINGS[@]}
		if [ $? -ne 0 ]; then
			die "Error assembling array: $?"
		fi
	fi

	# Mount the RAID-5 array.
	mount -t ext4 ${RAID_NAME} ${MOUNTPOINT}
	if [ $? -ne 0 ]; then
		die "Error mounting array: $?"
	fi
}

setup_single() {
	# Check for required utilities.
	validate_command "cryptsetup"
	validate_command "losetup"
	if [ ${FORMAT} ]; then
		validate_command "mkfs.ext4"
	fi
	validate_command "mkpasswd"

	# Check device count.
	if [ ${#DEVICES[@]} -lt 1 ]; then
		usage_print "Single requires at least 1 device; none specified"
	elif [ ${#DEVICES[@]} -gt 1 ]; then
		usage_print "Single requires at most 1 device; ${DEVICES[@]} specified"
	fi

	# Prepare specified device.
	DEVICE=${DEVICES[0]}

	# Get the device name.
	DEVICE_NAME=`echo ${DEVICE} | sed " s/.*\///"`

	# Get the keyfile.
	DEVICE_KEY="${DEVICE_NAME}.key"
	if [ ${FORMAT} ]; then
		# Generate a keyfile.
		if [ -f ${DEVICE_KEY} ]; then
			echo "Keyfile ${DEVICE_KEY} for ${DEVICE} found; continuing."
		else
			echo "Generating keyfile ${DEVICE_KEY} for ${DEVICE}."
			./keyfile.sh "${DEVICE_KEY}"
			if [ $? -ne 0 ]; then
				die "Error generating keyfile for ${DEVICE}"
			fi
		fi
	else
		if [ ! -f ${DEVICE_KEY} ]; then
			die "Device key ${DEVICE_KEY} not found"
		fi
	fi

	# Initialize the disk.
	local DONE=`false`
	until [ ${DONE} ]; do
		# Initialize the mapping.
		./cryptsetup.sh init -n ${DEVICE_NAME} -k ${DEVICE_KEY} ${DEVICE} ${PASSPHRASE} ${SALT}
		if [ $? -ne 0 ]; then
			die "Error generating mapping for ${DEVICE}: $?"
		fi

		# Format the filesystem.
		if [ ${FORMAT} ]; then
			# Format the filesystem.
			mkfs.ext4 -m 1 -b ${BLOCK_SIZE} "/dev/mapper/${DEVICE_NAME}"
			if [ $? -ne 0 ]; then
				die "Error formatting filesystem: $?"
			fi
		fi

		# Mount the filesytem.
		mount -t ext4 "/dev/mapper/${DEVICE_NAME}" ${MOUNTPOINT}
		if [ $? -ne 0 ]; then
			local AGAIN=""

			# Free the mapping.
			./cryptsetup.sh free ${DEVICE_NAME}

			# Prompt to re-enter passphrase.
			echo "Unable to mount /dev/mapper/${DEVICE_NAME}."
			echo "Re-enter passphrase (y) or quit (n)? [Y/n]"
			read AGAIN
			if [ ${AGAIN} == "n" ]; then # Quit.
				exit 1
			fi
			passphrase_get
			continue
		fi
		DONE=true
	done
}

# Check the specified command exists.
# 1:	The command to check for.
validate_command() {
	# Validate argument count.
	if [ $# -ne 1 ]; then
		die "Invalid argument count: $#"
	fi

	# Check for the specified command.
	if ! command -v ${1} > /dev/null; then
		die "Unable to find '${1}' utility"
	fi
}

# Print the usage message and exit failure.
# 1:	The specific error message (optional).
usage_print() {
	# Print the specified error message.
	if [ $# -gt 0 ]; then
		echo "ERROR: ${1}"
		echo ""
	fi

	# Print the usage message
	echo "USAGE:"
	echo "./setup.sh <command> [-f|--format] [-m|--mountpoint <mountpoint>] <devices>..."
	echo ""
	echo "Available commands:"
	echo "  raid1   Set up the root filesystem as an encrypted RAID-1 device."
	echo "  raid5   Set up the root filesystem as an encrypted RAID-5 device."
	echo "  single  Set up the root filesystem as a single encrypted device."
	echo ""
	echo "Special options:"
	echo "  -f|--format      Formats the specified root filesystem before setting it up."
	echo "  -m|--mountpoint  Where to mount the root filesystem (default: '/mnt/gentoo')"

	# Exit failure
	exit 1
}

# Parse the arguments.
arguments_parse $@

# Get the passphrase.
passphrase_get

# Run the command.
case "${COMMAND}" in
raid1)
	setup_raid1
	;;
raid5)
	setup_raid5
	;;
single)
	setup_single
	;;
*)
	usage_print "Unrecognized command: ${COMMAND}"
	;;
esac
