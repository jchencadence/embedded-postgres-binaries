#!/bin/bash
# I haven't figured out how to do cross compiling for macos yet, so this
# script must be run on an arm machine to make arm64 binaries, and on
# and intel machine to make the amd64 binaries.
#
# This script is not currently integrated with gradle, on account of my
# not really understanding it. Just run it direcly and it should make
# the .zip file for manual upload to github releases.

PG_VERSION=16.4
PKG_CONFIG_PATH=/opt/homebrew/Cellar/icu4c@77/77.1/lib/pkgconfig/

ARCH=$(uname -m)
if [ "$ARCH" == "x86_64" ]; then
    ARCH="amd64"
fi

mkdir cd darwin_build
cd darwin_build

WORK_DIR=$(pwd)

# Postgres
curl https://ftp.postgresql.org/pub/source/v${PG_VERSION}/postgresql-${PG_VERSION}.tar.bz2 -o postgresql-${PG_VERSION}.tar.bz2
tar -xjf postgresql-${PG_VERSION}.tar.bz2
PREFIX=$(pwd)/install
cd postgresql-${PG_VERSION}
./configure --prefix=$PREFIX
echo $PREFIX
export CGO_CFLAGS="-DHAVE_STRCHRNUL -mmacosx-version-min=15.4"
export MACOSX_DEPLOYMENT_TARGET="15.4"
make
make install
cd contrib
make
make install
cd ${WORK_DIR}

# pgvector
wget -O pgvector.tar.gz "https://github.com/pgvector/pgvector/archive/v0.8.0.tar.gz"
mkdir -p ${WORK_DIR}/pgvector
tar -xf pgvector.tar.gz -C pgvector --strip-components 1
cd pgvector
make USE_PGXS=1 PG_CONFIG=$PREFIX/bin/pg_config
make USE_PGXS=1 PG_CONFIG=$PREFIX/bin/pg_config install

# Make binaries point at libraries relative to executable
find $PREFIX/bin -type f | \
  xargs -L 1 install_name_tool -change \
  $PREFIX/lib/libpq.5.dylib \
  '@executable_path/../lib/libpq.5.dylib'

# Make libraries point at libraries relative to executable
find $PREFIX/lib -type f -name "*.so"  | \
  xargs -L 1 install_name_tool -change \
  $PREFIX/lib/libpq.5.dylib \
  '@executable_path/../lib/libpq.5.dylib'

cd $PREFIX

# Tar it up
tar --exclude='._*' -cJvf ./embedded-postgres-binaries-darwin-${ARCH}-${PG_VERSION}.0.txz \
  share/* \
  include/* \
  lib/libpq*.dylib \
  lib/*.dylib \
  bin/initdb \
  bin/pg_ctl \
  bin/postgres \
  bin/pg_isready \
  bin/psql

# # Zip the tars (who knows why)
#cd ..
#zip embedded-postgres-binaries-darwin-${ARCH}-${PG_VERSION}.0.zip embedded-postgres-binaries-darwin-${ARCH}-${PG_VERSION}.0.txz