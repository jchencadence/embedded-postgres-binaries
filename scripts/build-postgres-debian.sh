#!/bin/bash
set -ex

DOCKER_OPTS=
PROJ_VERSION=8.2.1
GEOS_VERSION=3.8.3
GDAL_VERSION=3.4.3
POSTGIS_VERSION=
PGROUTING_VERSION=
LITE_OPT=false

while getopts "v:i:g:r:e:o:l" opt; do
    case $opt in
    v) PG_VERSION=$OPTARG ;;
    i) IMG_NAME=$OPTARG ;;
    g) POSTGIS_VERSION=$OPTARG ;;
    r) PGROUTING_VERSION=$OPTARG ;;
    o) DOCKER_OPTS=$OPTARG ;;
    l) LITE_OPT=true ;;
    \?) exit 1 ;;
    esac
done

if [ -z "$PG_VERSION" ] ; then
  echo "Postgres version parameter is required!" && exit 1;
fi
if [ -z "$IMG_NAME" ] ; then
  echo "Docker image parameter is required!" && exit 1;
fi
if echo "$PG_VERSION" | grep -q '^9\.' && [ "$LITE_OPT" = true ] ; then
  echo "Lite option is supported only for PostgreSQL 10 or later!" && exit 1;
fi

ICU_ENABLED=$(echo "$PG_VERSION" | grep -qv '^9\.' && [ "$LITE_OPT" != true ] && echo true || echo false);

TRG_DIR=$PWD/bundle
mkdir -p $TRG_DIR

SCRIPTS_DIR="$PWD/scripts"
echo "current path"
echo $PWD

docker run --platform=linux/amd64 -i --rm -v ${TRG_DIR}:/usr/local/pg-dist \
-v $PWD/../../../../share:/tmp/share \
-v $PWD/../../../../scripts:/scripts \
-e PG_VERSION=$PG_VERSION \
-e POSTGIS_VERSION=$POSTGIS_VERSION \
-e ICU_ENABLED=$ICU_ENABLED \
-e PROJ_VERSION=$PROJ_VERSION \
-e PROJ_DATUMGRID_VERSION=1.8 \
-e GEOS_VERSION=$GEOS_VERSION \
-e GDAL_VERSION=$GDAL_VERSION \
-e PGROUTING_VERSION=$PGROUTING_VERSION \
-e PGVECTOR_VERSION=0.8.0 \
$DOCKER_OPTS $IMG_NAME /bin/bash -ex -c 'echo "Starting building postgres binaries" \
    && sed "s@archive.ubuntu.com@us.archive.ubuntu.com@" -i /etc/apt/sources.list \
    && sed -i "/bionic-backports/d" /etc/apt/sources.list \
    && ln -snf /usr/share/zoneinfo/Etc/UTC /etc/localtime && echo "Etc/UTC" > /etc/timezone \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        wget \
        patchelf \
        rsync \
        bzip2 \
        xz-utils \
        gcc \
        g++ \
        make \
        pkg-config \
        libc-dev \
        libicu-dev \
        libossp-uuid-dev \
        libxml2-dev \
        libxslt1-dev \
        libssl-dev \
        libz-dev \
        libperl-dev \
        python3-dev \
        tcl-dev \
        \
    && mkdir -p /etc/ssl/certs \
    && wget --no-check-certificate -O /etc/ssl/certs/ca-certificates.crt https://curl.se/ca/cacert.pem \
    && export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    && wget -O patchelf.tar.gz "https://nixos.org/releases/patchelf/patchelf-0.9/patchelf-0.9.tar.gz" \
    && mkdir -p /usr/src/patchelf \
    && tar -xf patchelf.tar.gz -C /usr/src/patchelf --strip-components 1 \
    && ls /scripts/config \
    && echo "look here" \
    && cd /usr/src/patchelf \
    && mkdir -p config \
    && cp /scripts/config/config.guess config/config.guess \
    && cp /scripts/config/config.sub config/config.sub \
    && ./configure --prefix=/usr/local \
    && make -j$(nproc) \
    && make install \
    \
    && wget -O postgresql.tar.bz2 "https://ftp.postgresql.org/pub/source/v$PG_VERSION/postgresql-$PG_VERSION.tar.bz2" \
    && mkdir -p /usr/src/postgresql \
    && tar -xf postgresql.tar.bz2 -C /usr/src/postgresql --strip-components 1 \
    && cd /usr/src/postgresql \
    && wget -O config/config.guess "https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=b8ee5f79949d1d40e8820a774d813660e1be52d3" \
    && wget -O config/config.sub "https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=b8ee5f79949d1d40e8820a774d813660e1be52d3" \
    && ./configure \
        CFLAGS="-Os -DMAP_HUGETLB=0x40000" \
        PYTHON=/usr/bin/python3 \
        --prefix=/usr/local/pg-build \
        --enable-integer-datetimes \
        --enable-thread-safety \
        --with-ossp-uuid \
        $([ "$ICU_ENABLED" = true ] && echo "--with-icu") \
        --with-libxml \
        --with-libxslt \
        --with-openssl \
        --with-perl \
        --with-python \
        --with-tcl \
        --without-readline \
    && make -j2 \
    && make install \
    && make -C contrib install \
    \
    && if [ -n "$POSTGIS_VERSION" ]; then \
      apt-get install -y --no-install-recommends curl libjson-c-dev libsqlite3-0 libsqlite3-dev libtiff5-dev libcurl4-openssl-dev sqlite3 unzip \
      && mkdir -p /usr/src/proj \
        && curl -sL "https://download.osgeo.org/proj/proj-$PROJ_VERSION.tar.gz" | tar -xzf - -C /usr/src/proj --strip-components 1 \
        && cd /usr/src/proj \
        && curl -sL "https://download.osgeo.org/proj/proj-datumgrid-$PROJ_DATUMGRID_VERSION.zip" > proj-datumgrid.zip \
        && unzip -o proj-datumgrid.zip -d data\
        && curl -sL "https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=b8ee5f79949d1d40e8820a774d813660e1be52d3" > config.guess \
        && curl -sL "https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=b8ee5f79949d1d40e8820a774d813660e1be52d3" > config.sub \
        && ./configure --disable-static --prefix=/usr/local/pg-build \
        && make -j$(nproc) \
        && make install \
      && mkdir -p /usr/src/geos \
        && curl -sL "https://download.osgeo.org/geos/geos-$GEOS_VERSION.tar.bz2" | tar -xjf - -C /usr/src/geos --strip-components 1 \
        && cd /usr/src/geos \
        && curl -sL "https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=b8ee5f79949d1d40e8820a774d813660e1be52d3" > config.guess \
        && curl -sL "https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=b8ee5f79949d1d40e8820a774d813660e1be52d3" > config.sub \
        && ./configure --disable-static --prefix=/usr/local/pg-build \
        && make -j$(nproc) \
        && make install \
      && mkdir -p /usr/src/gdal \
        && curl -sL "https://download.osgeo.org/gdal/$GDAL_VERSION/gdal-$GDAL_VERSION.tar.xz" | tar -xJf - -C /usr/src/gdal --strip-components 1 \
        && cd /usr/src/gdal \
        && curl -sL "https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=b8ee5f79949d1d40e8820a774d813660e1be52d3" > config.guess \
        && curl -sL "https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=b8ee5f79949d1d40e8820a774d813660e1be52d3" > config.sub \
        && ./configure --disable-static --prefix=/usr/local/pg-build --with-proj=/usr/local/pg-build \
        && make -j$(nproc) \
        && make install \
      && mkdir -p /usr/src/postgis \
        && curl -sL "https://postgis.net/stuff/postgis-$POSTGIS_VERSION.tar.gz" | tar -xzf - -C /usr/src/postgis --strip-components 1 \
        && cd /usr/src/postgis \
        && curl -sL "https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=b8ee5f79949d1d40e8820a774d813660e1be52d3" > config.guess \
        && curl -sL "https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=b8ee5f79949d1d40e8820a774d813660e1be52d3" > config.sub \
        && ./configure \
            --prefix=/usr/local/pg-build \
            --with-pgconfig=/usr/local/pg-build/bin/pg_config \
            --with-geosconfig=/usr/local/pg-build/bin/geos-config \
            --with-projdir=/usr/local/pg-build \
            --with-gdalconfig=/usr/local/pg-build/bin/gdal-config \
            --without-protobuf \
        && make -j$(nproc) \
        && make install \
      && apt-get install -y --no-install-recommends cmake libboost-graph-dev \
        && mkdir -p /usr/src/pgrouting \
          && curl -sL "https://github.com/pgRouting/pgrouting/archive/v$PGROUTING_VERSION.tar.gz" | tar -xzf - -C /usr/src/pgrouting --strip-components 1 \
          && cd /usr/src/pgrouting && mkdir build && cd build \
          && cmake -DWITH_DOC=OFF -DCMAKE_INSTALL_PREFIX=/usr/local/pg-build .. \
          && make \
          && make install \
    ; fi \
    && if [ -n "$PGVECTOR_VERSION" ]; then \
      mkdir -p /usr/src/pgvector \
        && wget -qO- "https://github.com/pgvector/pgvector/archive/v$PGVECTOR_VERSION.tar.gz" | tar -xzf - -C /usr/src/pgvector --strip-components 1 \
        && cd /usr/src/pgvector \
        && make USE_PGXS=1 PG_CONFIG=/usr/local/pg-build/bin/pg_config \
        && make USE_PGXS=1 PG_CONFIG=/usr/local/pg-build/bin/pg_config install \
    ; fi \
    \
    && cd /usr/local/pg-build \
    && cp /usr/lib/x86_64-linux-gnu/libossp-uuid.so.16 ./lib \
    && cp /lib/*/libz.so.1 /lib/*/liblzma.so.5 /usr/lib/*/libxml2.so.2 /usr/lib/*/libxslt.so.1 ./lib \
    && cp /usr/lib/x86_64-linux-gnu/libssl.so.1.1 /usr/lib/x86_64-linux-gnu/libcrypto.so.1.1 ./lib \
    && if [ "$ICU_ENABLED" = true ]; then cp --no-dereference /usr/lib/*/libicudata.so* /usr/lib/*/libicuuc.so* /usr/lib/*/libicui18n.so* ./lib; fi \
    && if [ -n "$POSTGIS_VERSION" ]; then cp --no-dereference /lib/*/libjson-c.so* /usr/lib/*/libsqlite3.so* ./lib ; fi \
    && find ./bin -type f \( -name "initdb" -o -name "pg_ctl" -o -name "postgres" -o -name "pg_dump" -o -name "pg_dumpall" -o -name "pg_restore" -o -name "pg_isready" -o -name "psql" \) -print0 | xargs -0 -n1 patchelf --set-rpath "\$ORIGIN/../lib" \
    && find ./lib -maxdepth 1 -type f -name "*.so*" -print0 | xargs -0 -n1 patchelf --set-rpath "\$ORIGIN" \
    && find ./lib/postgresql -maxdepth 1 -type f -name "*.so*" -print0 | xargs -0 -n1 patchelf --set-rpath "\$ORIGIN/.." \
    && rsync -a /tmp/share/ /usr/local/pg-build/share \
    && tar -cJvf /usr/local/pg-dist/postgres-linux-debian.txz --hard-dereference \
        share/postgresql \
        lib \
        bin/initdb \
        bin/pg_ctl \
        bin/postgres \
        bin/pg_dump \
        bin/pg_dumpall \
        bin/pg_restore \
        bin/pg_isready \
        bin/psql'
