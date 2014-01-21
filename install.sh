#!/bin/bash

# Script to assist in a Gentoo install.
# This script is based off of the Gentoo Installation handbook, and will need
# to change as the handbook changes.
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

# Computer architecture to target.
ARCHITECTURE="x86_64"
# Architecture name according to the Gentoo folder.
ARCHITECTURE_GENTOO_FOLDER=""
# Architecture name according to the Gentoo file.
ARCHITECTURE_GENTOO_FILE=""
# Architecture name according to the Linux Kernel.
ARCHITECTURE_LINUX=""
# Mirror for downloading the strage3 tarball and Portage.
DOWNLOAD_MIRROR="http://gentoo.osuosl.org"
# Version number of the kernel to download.
KERNEL_VERSION=""
# Mountpoint for the Gentoo root filesystem.
MOUNTPOINT="/mnt/gentoo"
# Name of the downloadable Portage file.
PORTAGE="portage-latest.tar.bz2"
# Generic temporary variable. It's unfortunate how often these nameless horrors
# are needed.
TEMP=`false`
# File that contains timezone information.
TIMEZONE=
# Generic user to log into for downloading tarballs and visiting website in
# 'links' during an install.
USERNAME="userface"

# Parse the user-specified arguments.
arguments_parse() {
	# Parse the command.
	if [ $# -lt 1 ]; then
		usage_print "Must specify a command"
	fi
	COMMAND=${1}
	shift

	# Parse devices.
	DEVICES=($@)
	for DEVICE in ${DEVICES[@]}; do
		# Check for block device.
		if [ ! -b ${DEVICE} ]; then
			usage_print "Not a block device: ${DEVICE}"
		fi
	done
}

# Check that the script will run with the specified system configuration.
system_validate() {
	if ! command -v mkpasswd > /dev/null; then
		usage_print "Unable to find 'mkpasswd'"
	fi
}

# Check if something is working and, if not, have the user fix it.
# 1:	The thing that should be working.
# 2:	The command to help show whether there is a problem or not.
# 3:	A hint to help the user fix the issue (optional).
user_fix() {
	local TEMP

	# Check if the thing is working.
	echo "Is ${1} working? [y/N]"
	${2}
	read TEMP

	# Get the user to fix the thing.
	while [ "${TEMP:0:1}" != "y" -a "${TEMP:0:1}" != "Y" ]; do
		# Drop the user to a shell.
		echo "Dropping to shell."
		echo "Please fix ${1} and then exit to shell."
		if [ $# -gt 2 ]; then
			echo "HINT: ${3}."
		fi
		bash

		# Check if the thing is working now.
		echo "Is ${1} fixed? [y/N]"
		${2}
		read TEMP
	done
}

# Prints the usage message and then exits the program.
# 1:	An error message (optional).
usage_print() {
	# Print the error message.
	if [ $# -gt 0 ]; then
		echo "ERROR: $1."
		echo ""
	fi

	# Print the usage message.
	echo "USAGE:"
	echo "./install.sh <command> <device>..."
	echo ""
	echo "Available commands:"
	echo "  raid5	Install over a RAID-5 device."

	# Exit failure.
	exit 1
}

# Parse the arguments.
arguments_parse ${@}

# Check for required system utilities.
system_validate

# Copy everything to the home directory and begin work from there.
echo "Setting up home directory."
cp -rv . ${HOME}
cd

# Set machine architecture.
TEMP="n"
while [ "${TEMP}" != "Y" -a "${TEMP}" != "y" ]; do
	echo "Current machine architecture is '${ARCHITECTURE}'. Is this correct? [y/N]"
	read TEMP
	if [ "${TEMP}" != "Y" -a "${TEMP}" != "y" ]; then
		echo "Set the machine architecture:"
		read ARCHITECTURE
	fi

	# Set architecture variables.
	case "${ARCHITECTURE}" in
		x86)
			ARCHITECTURE_GENTOO_FOLDER="x86"
			ARCHITECTURE_GENTOO_FILE="i686"
			ARCHITECTURE_LINUX="x86"
			;;
		x86_64)
			ARCHITECTURE_GENTOO_FOLDER="amd64"
			ARCHITECTURE_GENTOO_FILE="amd64"
			ARCHITECTURE_LINUX="ia64"
			;;
		*)
			echo "Unrecognized architecture: ${ARCHITECTURE}."
			ARCHITECTURE="x86_64"
			TEMP="n"
			;;
	esac

done

###### Section A: Installing Gentoo ######

### Chapter 1: About the Gentoo Linux Installation ###

# Nothing to do here...

### Chapter 2: Choosing the Right Installation Medium ###
# ...should be done before this script is run.

# I usually have no issue with the Live CD loading kernel modules.
echo "Skipping loading kernel modules."

# No need to change the root password.
echo "Leaving root password scrambled."

# Add user 'userface' for Internet download of tarballs.
useradd -m -G users ${USERNAME}
TEMP=1
while [ ${TEMP} != 0 ]; do
	echo "Set password for temporary, generic user '${USERNAME}'."
	passwd ${USERNAME}
	TEMP=$?
done

# I don't use ssh for remote installation, so don't start it.

### Chapter 3: Configuring your Network ###
# I usually just use ethernet which, thankfully, tends to "just work".

# I don't know how to check whether Internet is up, so I'll just dump
# information and ask the user to fix it if it's broken.
user_fix "The Internet" "ifconfig -a"

### Chapter 4: Prepating the Disks ###

# Set up disk encryption mappings.
echo "Preparing disks."
./setup.sh ${COMMAND} -f -m ${MOUNTPOINT} ${DEVICES[@]}

# I don't bother to partition the disks with my current setup.
echo "Skipping partitioning."

# I'm not using swap right now, either.
echo "Skipping swap activation."

### Chapter 5: Installing the Gentoo Installation Files ###

# Verify the date and time.
user_fix "The Time" "date" "As an example, the date can be set to March 29th, 16:21 in the year 2005 by typing 'date 032916212005'"

# Skip setting up a proxy.
echo "Skipping proxy setup."

# Confirm download mirror.
echo "Using '${DOWNLOAD_MIRROR}' for downloads. Is this okay? [Y/n]"
read TEMP
while [ "${TEMP:0:1}" == "n" -o "${TEMP:0:1}" == "N" ]; do
	# Get a new mirror.
	echo "Please enter a new mirror:"
	read DONWLOAD_MIRROR

	# Check the user's entry.
	echo "Is the mirror '${DOWNLOAD_MIRROR}' okay?"
	read TEMP
done

# Download the strage3 tarball as a normal user. Stupid, changing tarball names.
# *grumbles*
cd "${MOUNTPOINT}"
wget "${DOWNLOAD_MIRROR}/releases/${ARCHITECTURE_GENTOO_FOLDER}/autobuilds/latest-stage3-${ARCHITECTURE_GENTOO_FILE}-hardened.txt"
STAGE3=$(tail -n 1 "latest-stage3-${ARCHITECTURE_GENTOO_FILE}-hardened.txt" | cut -d'/' -f3)
wget "${DOWNLOAD_MIRROR}/releases/${ARCHITECTURE_GENTOO_FOLDER}/autobuilds/current-stage3-${ARCHITECTURE_GENTOO_FILE}-hardened/${STAGE3}"
wget "${DOWNLOAD_MIRROR}/releases/${ARCHITECTURE_GENTOO_FOLDER}/autobuilds/current-stage3-${ARCHITECTURE_GENTOO_FILE}-hardened/${STAGE3}.DIGESTS.asc"
sha512sum -c "${DOWNLOAD_MIRROR}/release/${ARCHITECTURE_GENTOO_FOLDER}/autobuilds/current-stage3-${ARCHITECTURE_GENTOO_FILE}-hardened/${STAGE3}.DIGESTS.asc"

# Unpack the stage3 tarball.
echo "Unpacking stage3 tarball."
tar -xvjpf "${STAGE3}"

# Download Portage as a normal user.
wget "${DOWNLOAD_MIRROR}/snapshots/${PORTAGE}"
wget "${DOWNLOAD_MIRROR}/snapshots/${PORTAGE}.md5sum"
md5sum -c "${PORTAGE}.md5sum"
if [ $? -ne 0 ]; then
	user_fix "Portage" "md5sum -c ${DOWNLOAD_MIRROR}/snapshots/${PORTAGE}.md5sum"
fi

# Unpack Portage.
echo "Unpacking Portage."
tar xvjf "${MOUNTPOINT}/${PORTAGE}" -C "${MOUNTPOINT}/usr"

# Edit the 'make.conf' file.
echo "Add CFLAGS, CXXFLAGS, and MAKEOPTS to Portage's 'make.conf' file."
read
nano "${MOUNTPOINT}/etc/portage/make.conf"

### Chapter 6: Installing the Gentoo Base System ###

# Select mirrors.
echo "Select a mirror for package downloads."
read
mirrorselect -i -o >> "${MOUNTPOINT}/etc/portage/make.conf"
echo "Select a rsync mirror."
read
mirrorselect -i -r -o >> "${MOUNTPOINT}/etc/portage/make.conf"

# Copy DNS information.
echo "Copying DNS information."
cp -L "/etc/resolv.conf" "/mnt/gentoo/etc"

# Mount filesystems.
echo "Mounting auxillary filesystems."
mount -t proc none "${MOUNTPOINT}/proc"
mount --rbind "/dev" "${MOUNTPOINT}/dev"

# Continue installing in the new environment.
echo "Entering new environemnt."
chroot "${MOUNTPOINT}" "~/install_chroot.sh"

### Chapter 10: Configuring the Bootloader (cont.) ###

# Start assembling initramfs.
cd
mkdir initramfs
cp "${MOUNTPOINT}/usr/src/linux/arch/${ARCHITECTURE_LINUX}/boot/bzImage" "initramfs/kernel-${KERNEL_VERSION}"
cp *.key "initramfs/"

# Unmount filesystems.
umount -l "/mnt/gentoo/dev{/shm,/pts,}"
umount -l "/mnt/gentoo/{/boot,/proc,}"

# Have the user save their 'initramfs' files before quitting.
echo "Dropping to shell; save your 'initramfs' files and then exit to reboot."
/bin/bash

# Reboot the computer.
init 6
