#!/bin/bash

set -e

rm -rf release
mkdir release

function do_build {
    version="$1"
    echo "=== Building ${version} ==="
    echo

    ./gradlew clean install -Pversion="${version}.0" -PpgVersion="${version}" -ParchName=amd64 -PpostgisVersion=3.4.4
    cp custom-debian-platform/build/tmp/buildCustomDebianBundle/bundle/postgres-linux-debian.txz "release/postgresql-${version}-linux-amd64.txz"
}

function do_release {
    version="$1"
    release_name="${version}-with-tools-$(date "+%Y%m%d")"
    sums=$(echo "sha256 sums:" && cd release && sha256sum postgresql-${version}-*)
    yes | gh release delete "${release_name}" || true
    gh release create "${release_name}" --notes "${sums}" --title "" release/postgresql-${version}-*
}

versions=("16.6")
for version in "${versions[@]}"; do
    do_build "$version"
    do_release "$version"
done
