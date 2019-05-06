#! /usr/bin/env bash

# Entrypoint that runs Skopeo Copy

[ "$DEBUG" = "1" ] && set -x
set -e

# sanitize env
[ "$GITHUB_SHA" = "" ] && \
  echo "GITHUB_SHA must be configured!" && exit 1

registry="docker://thoughtpolice/foundationdb"

# flags, only archive and registry are required. all remaining arguments
# are passed as flags, below
release="$1"
[ "$release" = "" ] && echo "No release name specified!" && exit 1

# get required tags
nixtag=$(nix eval --raw -f default.nix "docker.$release.imageTag")
sharaw=$(echo "$GITHUB_SHA" | cut -c 1-10)
shatag="$sharaw-$nixtag"
alltags=("$nixtag" "$shatag")

if [ ! "$GITHUB_REF" = "" ]; then
  reftag="${GITHUB_REF##*/}"
  alltags+=("$reftag-$nixtag")
  echo using GITHUB_REF tag "$reftag-$nixtag"
fi

# parse arguments
latest=0
for x in "$@"; do
  case "$x" in
    --latest)
        echo "tagging image with 'latest'"
        latest=1
        ;;
    *)
        ;;
  esac
done

# add 'latest' tag unless told not to
[ "$latest" = "1" ] && alltags+=("latest")

# do the business
echo using "$(skopeo --version)"
echo using tags: "$(for x in "${alltags[@]}"; do echo -n "$x "; done)"

for t in "${alltags[@]}"; do
  skopeo copy "docker-archive:foundationdb-$nixtag.tar.gz" "${registry}:${t}"
done
