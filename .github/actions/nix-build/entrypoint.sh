#! /usr/bin/env bash

# Entrypoint that runs nix-build and, optionally, copies Docker image tarballs
# to real files. The reason this is necessary is because once a Nix container
# exits, you must copy out the artifacts to the working directory before exit.

[ "$DEBUG" = "1" ] && set -x
[ "$QUIET" = "1" ] && QUIET_ARG="-Q"

set -e

# file to build (e.g. release.nix)
release="$1"
[ "$release" = "" ] && echo "No release name specified!" && exit 1

echo "Building docker image..."
docker=$(nix-build --no-link ${QUIET_ARG} default.nix -A "docker.$release")
version=$(nix eval --raw -f default.nix "docker.$release.imageTag")
echo "Copying Docker Tarball"
echo "  to:      foundationdb-$version.tar.gz"
echo "  from:    $docker"
echo "  version: $version"
cp -fL "$docker" "foundationdb-$version.tar.gz"
