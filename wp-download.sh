#!/usr/bin/env bash

set -eux

TYPE="$1"
SLUG="$2"
VERSION="$3"
PACKAGE="${SLUG}.${VERSION}.zip"

echo "Downloading $PACKAGE"

curl -o "/tmp/$PACKAGE" -sL "https://downloads.wordpress.org/$TYPE/$PACKAGE"

unzip -o "/tmp/$PACKAGE" -d "wp-content/${TYPE}s"

rm "/tmp/$PACKAGE"