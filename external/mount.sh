#!/bin/bash
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

# The device to mount.
DEVICE=""
# Whether to format the filesystem or not.
FORMAT=`false`
# Keyfile for the specified device.
KEYFILE=`false`
# Where to mount the device.
MOUNTPOINT=""
# Name for the mapping of the device.
NAME="device"
# Salt for the key-stretching algorithm.
SALT="1i8f0wjQpvtFbCRP"

# Parse arguments.
function arguments_parse {
	# Validate argument count.
	if [ $# -lt 2 ]; then
		usage_print "Too few arguments"
	fi

	# Parse optional arguments.
	while [ $# -gt 2 ]; do
		case "$1" in
		-f|--format)
			FORMAT=true
			shift
			;;
		-k|--key-file)
			shift
			KEYFILE=${1}
			if [ ! -f ${KEYFILE} ]; then
				usage_print "Key file ${KEYFILE} not a file"
			fi
			shift
			;;
		-n|--name)
			shift
			NAME=$1
			shift
			;;
		*)
			usage_print "Unrecognized option: $1"
		esac
	done

	# Parse base options
	DEVICE=${1}
	MOUNTPOINT=${2}
}

# Print the usage message.
# 1:	An error message (optional).
function usage_print {
	echo "ERROR: $1."
	echo ""
	echo "./mount.sh [-f] [-n name] [-k keyfile] <device> <mount point>"
	echo ""
	echo "--format: Format the specified filesystem as ext3; this will"
	echo "          also force-verify the passphrase."
	echo "  --name: Name for the mapping of the specified device."
	echo "		(default: \"device\")."
	echo "--key-file: Password-protected keyfile for the specified device."
	exit 1
}

# The main function, duh.
function main {
	# Cheap hack to seamlessly pass a keyfile argument.
	if [ ! -z ${KEYFILE} ]; then
		KEYFILE="-k ${KEYFILE}"
	fi

	# Call the correct main function.
	if [ $FORMAT ]; then
		main_format
	else
		main_normal
	fi
}

# Format and mount the filesystem.
function main_format {
	DONE=`false`

	# Read and verify the passphrase.
	until [ $DONE ]; do
		# Read the passphrase.
		echo "Enter password:"
		read -s PASSPHRASE

		# Read the verification passphrase.
		echo "Verify password:"
		read -s VERIFY

		# Verify the passphrases.
		if [ $PASSPHRASE != $VERIFY ]; then # Failure.
			# See if the user wishes to try again.
			echo "Passwords do not match."
			echo "Try again? [y/n]"
			read AGAIN
			if [ $AGAIN != "y" ]; then # Quitting.
				return
			fi
			continue
		fi

		# Verified.
		DONE=true
	done

	# Format and mount the device.
	./cryptsetup.sh init -n ${NAME} ${KEYFILE} ${DEVICE} ${PASSPHRASE} ${SALT}
	mkfs.ext3 "/dev/mapper/${NAME}"
	main_mount
	if [ $? -ne 0 ]; then
		echo "Something terrible has happened."
	else
		echo "Successfully mounted."
	fi
}

# Mounts the mapped device.
function main_mount {
	mount -t ext3 "/dev/mapper/${NAME}" "${MOUNTPOINT}"
	return $?
}

# Just mount the filesystem.
function main_normal {
	DONE=`false`

	# Continuously try to mount the filesystem.
	until [ $DONE ]; do
		echo "Passphrase:"

		# Read the passphrase.
		read -s PASSPHRASE

		# Setup cryptsetup.
		./cryptsetup.sh init -n ${NAME} ${KEYFILE} ${DEVICE} ${PASSPHRASE} ${SALT}

		# Mount the device.
		main_mount
		if [ $? -ne 0 ]; then
			./cryptsetup.sh free ${NAME}
			echo "Mount failed: Password incorrect, filesystem corrupted, or other issue."
			echo "Try again."
		else
			echo "Successfully mounted."
			DONE=true
		fi
	done
}

# Makes sure that the system can run the script. Right now that just means
# checking for the 'mkpasswd' utility. More checks could certainly be added.
function system_validate {
	# Check for root privileges.
	if [[ ${EUID} -ne 0 ]]; then
		usage_print "This script must be run as 'root'"
	fi

	# Check for 'cryptsetup' utility.
	if ! command -v cryptsetup > /dev/null; then
		usage_print "Unable to find 'cryptsetup' utility"
	fi

	# Check for 'mkpasswd' utility.
	if ! command -v mkpasswd > /dev/null; then
		usage_print "Unable to find 'mkpasswd' utility"
	fi
}

# Validate system pre-requirements.
system_validate

# Parse arguments.
arguments_parse $@

# Call main.
main
