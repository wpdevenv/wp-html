#!/usr/bin/env bash

set -eux

WP_CORE_DIR="${INSTALL_DIR:-html}"
TMPDIR="${TMPDIR:-/tmp}"
TMPDIR=$(echo $TMPDIR | sed -e "s/\/$//")
TYPE="$1"
SLUG="$2"
VERSION="$3"
PACKAGE="${SLUG}.${VERSION}.zip"

echo "Downloading $PACKAGE"

curl -o "$TMPDIR/$PACKAGE" -sL "https://downloads.wordpress.org/$TYPE/$PACKAGE"

unzip -o "$TMPDIR/$PACKAGE" -d "${WP_CORE_DIR}/wp-content/${TYPE}s"

rm "$TMPDIR/$PACKAGE"
