#!/bin/sh

# Download a Sabayon package to the current directory.
# Arguments: package_argument [parameters to querypkg]

# example:
# download_entropy_packages.sh libbz2.so --type lib

# This file belongs to querypkg.

# (C) 2014 by Enlik <poczta-sn at gazeta . pl>
# license: MIT

download() {
	local calculated_digest
	local pkgfilename

	wget --no-clobber -- "$URL_start/$URL_part"
	pkgfilename=${URL_part##*/}
	calculated_digest=$(md5sum "$pkgfilename" | awk '{print $1}')

	if [ $? -ne 0 ]; then
		echo "calculated_digestsum on '$pkgfilename' failed"
		exit 1
	fi

	if [ "$calculated_digest" != "$digest" ]; then
		echo "Digest verification: failure!" >&2
		echo "expected: '$digest'" >&2
		echo "got:      '$calculated_digest'" >&2
		exit 1
	fi

	echo "Digest OK."
}

prompt_download() {
	local line
	line=$1
	set -f
	set -- $line
	set +f
	if [ $# -ne 3 ]; then
		echo "Invalid format!" >&2
		echo "'$line'" >&2
		exit 1
	fi

	local package
	local digest
	local URL_part

	package=$1
	digest=$2
	URL_part=$3

	# The server can return results that don't match exactly the provided
	# package or can return more results from more repositories, so process
	# the list, asking the user one by one.
	local inp
	read -p "Download '$package' ($URL_part)? [yNq] " inp <&6
	if [ "$inp" = y ]; then
		download
	elif [ "$inp" = q ]; then
		exit 0
	else
		echo "Skipped."
	fi
}

if [ $# -lt 1 ]; then
	echo "No arguments." >&2
	exit 1
fi

URL_start="http://dl.sabayon.org/entropy/standard/sabayonlinux.org/"

output=$(querypkg -D "$@")

if [ $? -ne 0 ]; then
	echo "Command failed." >&2
	exit 1
fi

exec 6<&0
echo "$output" | while read -r line; do
	prompt_download "$line"
done
exec 6<&-
