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
# Where to mount the device.
MOUNTPOINT=""
# Name for the mapping of the device.
NAME="device"
# Salt for the key-stretching algorithm.
SALT_GLOBAL="1i8f0wjQpvtFbCRP"

# Parse arguments.
function arguments_parse {
	# Validate argument count.
	if [ $# -lt 2 ]; then
		echo "Too few arguments."
		usage_print
	fi

	# Parse optional arguments.
	while [ $# -gt 2 ]; do
		case "$1" in
		-f|--format)
			FORMAT=true
			shift
			;;
		-n|--name)
			shift
			NAME=$1
			shift
			;;
		*)
			echo "Unrecognized option: $1"
			usage_print
		esac
	done

	# Parse base options
	DEVICE=$1
	MOUNTPOINT=$2
}

# Print the usage message.
# 1:	An error message (optional).
function usage_print {
	echo "ERROR: $1."
	echo ""
	echo "./script.sh [-f] [-n <name>] <device> <mount point>"
	echo ""
	echo "--format: Format the specified filesystem as ext3; this will"
	echo "          also force-verify the passphrase."
	echo "  --name: Name for the mapping of the specified device."
	echo "		(default: \"device\")."
	exit 1
}

# Setup cryptsetup. (almost redundant)
# 1:	The passphrase.
function cryptsetup_init {
	# Validate arguments
	if [ $# -ne 1 ]; then
		echo "cryptsetup_init(); invalid argument count: $#."
	fi

	# Set up the decrypted device (paranoid much?).
	echo -n "Hashing/Setup."
	key_init $1
	echo "$KEY" | cryptsetup create --cipher serpent-xts-essiv:sha256 --hash sha512 ".${NAME}0" ${DEVICE}
	echo -n "."
	key_init $KEY $KEY
	echo "$KEY" | cryptsetup create --cipher aes-xts-essiv:sha256 --hash sha512 ".${NAME}1" /dev/mapper/".${NAME}0"
	echo -n "."
	key_init $KEY $KEY
	echo "$KEY" | cryptsetup create --cipher twofish-xts-essiv:sha256 --hash sha512 ".${NAME}2" /dev/mapper/".${NAME}1"
	echo -n "."
	key_init $KEY $KEY
	echo "$KEY" | cryptsetup create --cipher serpent-cbc-essiv:sha256 --hash sha512 ".${NAME}3" /dev/mapper/".${NAME}2"
	echo -n "."
	key_init $KEY $KEY
	echo "$KEY" | cryptsetup create --cipher aes-cbc-essiv:sha256 --hash sha512 ".${NAME}4" /dev/mapper/".${NAME}3"
	echo "."
	key_init $KEY $KEY
	echo "$KEY" | cryptsetup create --cipher twofish-cbc-essiv:sha256 --hash sha512 "${NAME}" /dev/mapper/".${NAME}4"
}

# Format the encrypted filesystem.
function cryptsetup_format {
	mkfs.ext3 "/dev/mapper/${NAME}"
}

# Remove cryptsetup mappings.
function cryptsetup_free {
	# Validate arguments.
	if [ $# -ne 0 ]; then
		echo "cryptsetup_free(); invalid argument count: $#."
	fi

	# Remove cryptsetup mappings.
	cryptsetup remove "${NAME}"
	cryptsetup remove ".${NAME}4"
	cryptsetup remove ".${NAME}3"
	cryptsetup remove ".${NAME}2"
	cryptsetup remove ".${NAME}1"
	cryptsetup remove ".${NAME}0"
}

# Try to mount the encrypted filesystem.
# return:	Whether or not the filesystem was mounted successfully;
#		specifically, the return value of 'mount'.
function cryptsetup_mount {
	mount -t ext3 /dev/mapper/$NAME $MOUNTPOINT
	return $?
}

# Initialize the key through a deliberately-slow Key Derivation Function (KDF).
# 1:	The specified passphrase to initialize the key with.
# 2:	(optional); Use part of the previous output as the salt.
function key_init {
	# Validate arguments.
	if [ $# -lt 1 ]; then
		echo "key_init() invalid argument count: $#."
	fi

	# Get the salt.
	if [ $# -eq 2 ]; then
		# Use the first 16 characters of the second argument.
		SALT=$(echo $2 | cut -c 1-16)
	else
		# Use the global salt.
		SALT=$SALT_GLOBAL
	fi

	# Execute the key derivation function.
	# The extra shenanegains with 'sed' is to prevent a corner-case where
	# both 'mkpasswd' and 'echo' would fail if the first line of the
	# passphrase is a '-'. What an ugly pain!
	KEY=$(echo -n "C$1" | sed "s/^.//" | mkpasswd -m sha-256 -R 72853 -s -S $SALT | cut -d '$' -f 5)
}

# The main function, duh.
function main {
	if [ $FORMAT ]; then
		main_format
	else
		main_normal
	fi
}

# Just mount the filesystem.
function main_normal {
	DONE=`false`

	# Continuously try to mount the filesystem.
	until [ $DONE ]; do
		echo "Passphrase:"

		# Read the passphrase.
		read -s PASSPHRASE

		# Setup cryptsetup
		cryptsetup_init $PASSPHRASE

		# Mount the device.
		cryptsetup_mount
		if [ $? -ne 0 ]; then
			cryptsetup_free
			echo "Mount failed: Password incorrect, filesystem corrupted, or other issue."
			echo "Try again."
		else
			echo "Successfully mounted."
			DONE=true
		fi
	done
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
	cryptsetup_init $PASSPHRASE
	cryptsetup_format
	cryptsetup_mount
	if [ $? -ne 0 ]; then
		echo "Something terrible has happened."
	fi
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
