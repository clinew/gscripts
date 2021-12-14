#!/bin/bash
#
# Copyright (C) 2013,2021 Wade T. Cline
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
# Keyfile for the specified device.
KEYFILE=`false`
# Name for the mapping of the device.
NAME="device"
# Passphrase for the device.
PASSPHRASE=""
# Salt for the key-stretching algorithm.
SALT=""

# Parse arguments.
# TODO: Use 'getopt'
arguments_parse() {
	# Validate argument count.
	if [ $# -lt 2 ]; then
		usage_print "Too few arguments"
	fi

	# Parse the command and its arguments.
	COMMAND=${1}
	shift
	case "${COMMAND}" in
	init)
		# Parse optional arguments.
		while [ $# -gt 3 ]; do
			case "${1}" in
			-n|--name)
				shift
				NAME=${1}
				shift
				;;
			-k|--key-file)
				shift
				KEYFILE=${1}
				if [ ! -f ${KEYFILE} ]; then
					usage_print "Keyfile does not exist"
				fi
				shift
				;;
			*)
				usage_print "Unrecognized option: ${1}"
			esac
		done

		# Parse the device.
		DEVICE=${1}
		if [ ! -b ${DEVICE} ]; then
			usage_print "Not a block device: ${DEVICE}"
		fi
		shift

		# Parse the passphrase.
		PASSPHRASE=${1}
		shift

		# Parse the base salt.
		SALT=${1}
		shift
		;;
	free)
		# Parse the mapping name.
		if [ $# -gt 0 ]; then
			NAME=${1}
			shift
		fi
		;;
	*)
		usage_print "Unrecognized command ${COMMAND}"
	esac

	# Check for additonal arguments.
	if [ $# -gt 0 ]; then
		usage_print "Additional argument: ${1}"
	fi
}

# Set up the specified hop.
# 1:	Cipher for the current hop.
# 2:	Mapping destination for the current hop.
# 3:	Block device source for the current hop.
# 4:	Keyfile destination for the current hop.
# 5:	Keyfile source for the current hop.
cryptsetup_init_hop() {
	echo -n "."

	# Stretch the key.
	KEY="$(cryptsetup_key_stretch "${SALT}" "${KEY}")"

	# Get the key from the keyfile.
	if [ ! -z ${KEYFILE} ]; then
		echo "${KEY}" | cryptsetup create --cipher ${1} --key-file=- "${4}" "${5}" 
		PASSPHRASE=${KEY}
		KEY=`cat /dev/mapper/${4}`
	fi

	# Set up the mapping.
	echo "${KEY}" | cryptsetup create --cipher ${1} --key-file=- ${2} ${3}

	# Reset the key.
	if [ ! -z ${KEYFILE} ]; then
		KEY=${PASSPHRASE}
	fi
}

# Setup cryptsetup. (almost redundant)
cryptsetup_init() {
	# Set the first value of the key.
	KEY=${PASSPHRASE}

	# Set up the keyfile.
	if [ ! -z ${KEYFILE} ]; then
		DEVICE_LOOP=`losetup -f`
		losetup "${DEVICE_LOOP}" "${KEYFILE}"
		if [ "$?" -ne 0 ]; then
			usage_print "Error setting up loop device: $?"
		fi
	fi

	# Set up the mappings.
	echo -n "Hashing/Setup of '${DEVICE}'"
	cryptsetup_init_hop "serpent-xts-essiv:sha256" ".${NAME}0" "${DEVICE}" ".${NAME}_key0" "${KEYFILE}"
	cryptsetup_init_hop "aes-xts-essiv:sha256" ".${NAME}1" "/dev/mapper/.${NAME}0" ".${NAME}_key1" "/dev/mapper/.${NAME}_key0"
	cryptsetup_init_hop "twofish-xts-essiv:sha256" ".${NAME}2" "/dev/mapper/.${NAME}1" ".${NAME}_key2" "/dev/mapper/.${NAME}_key1"
	cryptsetup_init_hop "serpent-xts-essiv:sha256" ".${NAME}3" "/dev/mapper/.${NAME}2" ".${NAME}_key3" "/dev/mapper/.${NAME}_key2"
	cryptsetup_init_hop "aes-xts-essiv:sha256" ".${NAME}4" "/dev/mapper/.${NAME}3" ".${NAME}_key4" "/dev/mapper/.${NAME}_key3"
	cryptsetup_init_hop "twofish-xts-essiv:sha256" "${NAME}" "/dev/mapper/.${NAME}4" "${NAME}_key" "/dev/mapper/.${NAME}_key4"
	echo ""

	# Free the keyfile.
	if [ ! -z ${KEYFILE} ]; then
		NAME="${NAME}_key"
		cryptsetup_free
		losetup -d "${DEVICE_LOOP}"
	fi
}

# Remove cryptsetup mappings.
cryptsetup_free() {
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

# Stretch the specified key by hashing it with a large number of rounds.
# 1: Salt for the key-derivation function.
# 2: Key to derive.
# 3(opt): Hash function to use.
# 4(opt): Number of rounds to use.
# stdout: Stretched key.
cryptsetup_key_stretch() {
	local salt="$1"
	local key="$2"
	local hash="${3:-sha-512}"
	local rounds=${4:-72853}

	# Execute the key derivation function.
	key="$(printf %s "${key}" | mkpasswd -m "${hash}" -R ${rounds} -s -S "${salt}" | cut -d '$' -f 5)"
	echo -n "${key}"
}

# Makes sure that the system can run the script.
system_validate() {
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
usage_print() {
	echo "ERROR: $1."
	echo ""
	echo "./cryptsetup.sh init [-n name] [-k keyfile] <device> <passphrase> <salt>"
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
