#!/bin/bash
# I haven't figured out how to do cross compiling for macos yet, so this
# script must be run on an arm machine to make arm64 binaries, and on
# and intel machine to make the amd64 binaries.
#
# This script is not currently integrated with gradle, on account of my
# not really understanding it. Just run it direcly and it should make
# the .zip file for manual upload to github releases.

PG_VERSION=16.4
PGVECTOR_VERSION=0.8.0
ARCH=

# Parse options
while getopts "v:a:" opt; do
    case $opt in
    v) PG_VERSION=$OPTARG ;;
    a) ARCH=$OPTARG ;;
    \?) exit 1 ;;
    esac
done

mkdir -p bundle
cd bundle

WORK_DIR=$(pwd)

# Dynamically set environment variables for Homebrew dependencies using brew --prefix
export PATH="$(brew --prefix icu4c)/bin:$(brew --prefix icu4c)/sbin:$(brew --prefix python3)/bin:$(brew --prefix pcre)/bin:$(brew --prefix gettext)/bin:$PATH"
export LDFLAGS="-L$(brew --prefix icu4c)/lib -L$(brew --prefix openssl@3)/lib -L$(brew --prefix pcre)/lib -L$(brew --prefix boost)/lib -L$(brew --prefix gettext)/lib -L$INSTALL_DIR/lib"
export CPPFLAGS="-I$(brew --prefix icu4c)/include -I$(brew --prefix openssl@3)/include -I$(brew --prefix pcre)/include -I$(brew --prefix boost)/include -I$(brew --prefix gettext)/include -I$INSTALL_DIR/include"
export PKG_CONFIG_PATH="$(brew --prefix icu4c)/lib/pkgconfig:$(brew --prefix openssl@3)/lib/pkgconfig:$INSTALL_DIR/lib/pkgconfig"

# Set Python path dynamically
PYTHON_PATH="$(brew --prefix python3)/bin/python3"

# Additional ICU-specific environment variables
export ICU_CFLAGS="-I$(brew --prefix icu4c)/include"
export ICU_LIBS="-L$(brew --prefix icu4c)/lib -licuuc -licudata -licui18n"

# Postgres
curl https://ftp.postgresql.org/pub/source/v${PG_VERSION}/postgresql-${PG_VERSION}.tar.bz2 -o postgresql-${PG_VERSION}.tar.bz2
tar -xjf postgresql-${PG_VERSION}.tar.bz2
PREFIX=$(pwd)/install
cd postgresql-${PG_VERSION}
./configure --prefix=$PREFIX
echo $PREFIX
make
make install
cd contrib
make
make install
cd ${WORK_DIR}

# pgvector
wget -O pgvector.tar.gz "https://github.com/pgvector/pgvector/archive/v$PGVECTOR_VERSION.tar.gz"
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
tar --exclude='._*' -cJvf $WORK_DIR/embedded-postgres-binaries-darwin-${ARCH}-${PG_VERSION}.0.txz \
  share/* \
  include/* \
  lib/libpq*.dylib \
  lib/*.dylib \
  bin/initdb \
  bin/pg_ctl \
  bin/postgres \
  bin/pg_isready \
  bin/psql
