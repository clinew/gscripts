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

# The user's command.
COMMAND=""
# The device to mount.
DEVICE=""
# Name for the mapping of the device.
NAME="device"
# Passphrase for the device.
PASSPHRASE=""
# Salt for the key-stretching algorithm.
SALT=""
SALT_BASE="1i8f0wjQpvtFbCRP"

# Parse arguments.
function arguments_parse {
	# Validate argument count.
	if [ $# -lt 2 ]; then
		usage_print "Too few arguments"
	fi

	# Parse the command and its arguments.
	COMMAND=${1}
	shift
	case "${COMMAND}" in
	init)
		# Check for remaining arguments.
		if [ $# -lt 3 ]; then
			usage_print "Too few arguments for command '${COMMAND}'."
		fi

		# Parse the device.
		DEVICE=${1}
		if [ ! -b ${DEVICE} ]; then
			usage_print "Not a block device file: ${DEVICE}"
		fi
		shift

		# Parse the passphrase.
		PASSPHRASE=${1}
		shift

		# Parse the base salt.
		SALT_BASE=${1}
		shift
		;;
	free)
		# Do nothing.
		;;
	*)
		usage_print "Unrecognized command ${COMMAND}"
	esac

	# Parse the mapping name.
	if [ $# -gt 0 ]; then
		NAME=${1}
	fi
	shift

	# Check for additonal arguments.
	if [ $# -gt 0 ]; then
		usage_print "Additional argument: ${1}"
	fi
}

# Setup cryptsetup. (almost redundant)
function cryptsetup_init {
	# Set up the decrypted device (paranoid much?).
	echo -n "Hashing/Setup of '${DEVICE}'."
	cryptsetup_key_init ${PASSPHRASE}
	echo "$KEY" | cryptsetup create --cipher serpent-xts-essiv:sha256 --hash sha512 ".${NAME}0" ${DEVICE}
	echo -n "."
	cryptsetup_key_init $KEY $KEY
	echo "$KEY" | cryptsetup create --cipher aes-xts-essiv:sha256 --hash sha512 ".${NAME}1" /dev/mapper/".${NAME}0"
	echo -n "."
	cryptsetup_key_init $KEY $KEY
	echo "$KEY" | cryptsetup create --cipher twofish-xts-essiv:sha256 --hash sha512 ".${NAME}2" /dev/mapper/".${NAME}1"
	echo -n "."
	cryptsetup_key_init $KEY $KEY
	echo "$KEY" | cryptsetup create --cipher serpent-cbc-essiv:sha256 --hash sha512 ".${NAME}3" /dev/mapper/".${NAME}2"
	echo -n "."
	cryptsetup_key_init $KEY $KEY
	echo "$KEY" | cryptsetup create --cipher aes-cbc-essiv:sha256 --hash sha512 ".${NAME}4" /dev/mapper/".${NAME}3"
	echo "."
	cryptsetup_key_init $KEY $KEY
	echo "$KEY" | cryptsetup create --cipher twofish-cbc-essiv:sha256 --hash sha512 "${NAME}" /dev/mapper/".${NAME}4"
}

# Remove cryptsetup mappings.
function cryptsetup_free {
	# Validate arguments.
	if [ $# -ne 0 ]; then
		usage_print "cryptsetup_free(); invalid argument count: $#."
	fi

	# Remove cryptsetup mappings.
	cryptsetup remove "${NAME}"
	cryptsetup remove ".${NAME}4"
	cryptsetup remove ".${NAME}3"
	cryptsetup remove ".${NAME}2"
	cryptsetup remove ".${NAME}1"
	cryptsetup remove ".${NAME}0"
}

# Initialize the key through a deliberately-slow Key Derivation Function (KDF).
# 1:	The specified passphrase to initialize the key with.
# 2:	(optional); Use part of the previous output as the salt.
function cryptsetup_key_init {
	# Validate arguments.
	if [ $# -lt 1 ]; then
		usage_print "cryptsetup_key_init() invalid argument count: $#."
	fi

	# Get the salt.
	if [ $# -eq 2 ]; then
		# Use the first 16 characters of the second argument.
		SALT=$(echo ${2} | cut -c 1-16)
	else
		# Use the global salt.
		SALT=${SALT_BASE}
	fi

	# Execute the key derivation function.
	# The extra shenanegains with 'sed' is to prevent a corner-case where
	# both 'mkpasswd' and 'echo' would fail if the first line of the
	# passphrase is a '-'. What an ugly pain!
	KEY=$(echo -n "C${1}" | sed "s/^.//" | mkpasswd -m sha-256 -R 72853 -s -S $SALT | cut -d '$' -f 5)
}

# Makes sure that the system can run the script.
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

# Print the usage message.
# 1:	An error message (optional).
function usage_print {
	echo "ERROR: $1."
	echo ""
	echo "./cryptsetup.sh init <device> <passphrase> <salt> [name]"
	echo "./cryptsetup.sh free [name]"
	echo ""
	echo "  init:	Initialize mappings."
	echo "  free:	Remove mappings."
	echo ""
	echo "  device:	The block device to create mappings for."
	echo "  name:	The name for the mapping of the specified device."
	echo "		(default: \"device\")."
	echo "  passphrase:	The passphrase for the specified device."
	exit 1
}

# Validate system pre-requirements.
system_validate

# Parse arguments.
arguments_parse $@

# Call the correct command.
case "${COMMAND}" in
init)
	cryptsetup_init
	;;
free)
	cryptsetup_free
	;;
*)
	usage_print "Unrecognized command ${COMMAND}"
esac
