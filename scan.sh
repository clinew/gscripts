#!/bin/bash

# Global defaults.
DEFAULT_MODE="Gray"
DEFAULT_SIZEX="8.5in"
DEFAULT_SIZEY="11in"

# Assign defaults.
MODE="${DEFAULT_MODE}"
SIZEX="${DEFAULT_SIZEX}"
SIZEY="${DEFAULT_SIZEY}"

# Print usage message and exit the program.
usage_print() {
	# Print error message.
	if [ $# -gt 0 ]; then
		echo "ERROR: $1"
		echo ""
	fi

	# Print usage message.
	echo "USAGE: $0 [-h] [-m MODE] [-x SIZE] [-y SIZE] OUTPUT"
	echo -e "\t-e MODE: Select color mode (default: '${DEFAULT_MODE}')"
	echo -e "\t-x SIZE: Set x-dimension size (default: '${DEFAULT_SIZEX}')"
	echo -e "\t-y SIZE: Set y-dimension size (default: '${DEFAULT_SIZEY}')"

	# Exit the program.
	if [ $# -gt 0 ]; then
		exit 1
	fi
	exit 0
}

# Parse arguments.
while getopts "hm:x:y:" opt; do
	case "${opt}" in
	h)
		usage_print
		;;
	m)
		MODE="${OPTARG}"
		;;
	x)
		SIZEX="${OPTARG}"
		;;
	y)
		SIZEY="${OPTARG}"
		;;
	*)
		usage_print "Unknow argument '${opt}'"
		;;
	esac
done
shift $((OPTIND - 1))
if [ $# -eq 0 ]; then
	usage_print "Expected output filename argument"
fi
DOCUMENT="$1"

# Scan images.
set -ex
COUNT=1
MORE="y"
while [ ! -z "${MORE}" ]; do
	DEST="__$(printf "%03d" ${COUNT})"
	DEST_PNM="${DEST}.pnm"
	DEST_PNG="${DEST}.png"
	echo "Scaning page '${COUNT}'"
	scanimage --resolution 300 -x "${SIZEX}" -y "${SIZEY}" --mode "${MODE}" > "${DEST_PNM}"
	echo "Converting to PNG (flip page now)"
	convert "${DEST_PNM}" "${DEST_PNG}"
	rm "${DEST_PNM}"
	echo "More pages?  (any input for more pages, none for no more pages)"
	COUNT=$((${COUNT} + 1))
	read MORE
done
echo "Converting PNGs to PDF '$DOCUMENT'"
convert __*.png "${DOCUMENT}"
rm __*.png

# Preview.
echo "Preview document"
mupdf "${DOCUMENT}"
echo "Is the document acceptable?  (any input for NO, none for YES)"
read MORE
if [ ! -z "${MORE}" ]; then
	echo "Removing '${DOCUMENT}'"
	rm "${DOCUMENT}"
fi
echo "Done"
