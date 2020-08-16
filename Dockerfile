ARG WORKDIR=/workspace
ARG SRCDIR=${WORKDIR}/src
ARG TARGETDIR=${WORKDIR}/target
ARG FINAL_BIN_PATH=${WORKDIR}/out/curl
ARG CURL_VERSION=7.71.1
ARG CURL_GPG_KEY_URL="https://daniel.haxx.se/mykey.asc"
ARG HEIMDAL_VERSION=master
ARG HEIMDAL_GITREPO_NAME=heimdal/heimdal
ARG HEIMDAL_GITREPO_URL=https://github.com/${HEIMDAL_GITREPO_NAME}.git
ARG HEIMDAL_GITREPO_PATH=${SRCDIR}/${HEIMDAL_GITREPO_NAME}

## Build Base Image ##
FROM alpine:edge as base-build
ARG WORKDIR
WORKDIR ${WORKDIR}
# Prepare System
RUN apk update && apk upgrade
RUN apk add wget git util-linux

## Build Heimdal ##
FROM base-build as heimdal-build
ARG HEIMDAL_VERSION
ARG HEIMDAL_GITREPO_URL
ARG HEIMDAL_GITREPO_PATH
ARG TARGETDIR
# Clone Repository
RUN git clone -q -b ${HEIMDAL_VERSION} ${HEIMDAL_GITREPO_URL} ${HEIMDAL_GITREPO_PATH}
# Installing build dependencies
RUN apk add gcc make gawk musl-dev autoconf automake libtool bison flex perl-json python3 openssl-dev openssl-libs-static ncurses-dev ncurses-static \
    && ln -sf /usr/bin/python3.8 /usr/bin/python
# Prepare configuration
RUN cd ${HEIMDAL_GITREPO_PATH} \
  && autoreconf -f -i \
  && mkdir build
# Configuring
RUN cd ${HEIMDAL_GITREPO_PATH}/build \
  && ../configure --disable-shared --prefix=${TARGETDIR} --with-openssl --with-pic=yes --without-berkeley-db --without-readline --without-openldap --without-hcrypto-fallback --disable-otp --disable-heimdal-documentation
# Making    
RUN cd ${HEIMDAL_GITREPO_PATH}/build \
    && LDFLAGS=-all-static make -j8
# Installing
RUN cd ${HEIMDAL_GITREPO_PATH}/build \
    && make install

## Build Curl ##
FROM base-build as curl-build
ARG SRCDIR
ARG TARGETDIR
ARG FINAL_BIN_PATH
ARG CURL_VERSION
ARG CURL_GPG_KEY_URL
ARG CURL_GPG_KEY_PATH=${SRCDIR}/curl-gpg.pub
ARG CURL_TARBALL_FILENAME=curl-${CURL_VERSION}.tar.xz
ARG CURL_TARBALL_URL=https://curl.haxx.se/download/${CURL_TARBALL_FILENAME}
ARG CURL_TARBALL_PATH=${SRCDIR}/${CURL_TARBALL_FILENAME}
# Copy and install built dependencies
COPY --from=heimdal-build ${TARGETDIR} ${TARGETDIR}
# Fetching
RUN mkdir -p ${SRCDIR} \
    && wget "${CURL_GPG_KEY_URL}" -qO "${CURL_GPG_KEY_PATH}" \
    && wget "${CURL_TARBALL_URL}.asc" -qO "${CURL_TARBALL_PATH}.asc" \
    && wget "${CURL_TARBALL_URL}" -qO "${CURL_TARBALL_PATH}"
# Validating source
RUN apk add gnupg \
    && gpg --import --always-trust ${CURL_GPG_KEY_PATH} \
    && gpg --verify ${CURL_TARBALL_PATH}.asc ${CURL_TARBALL_PATH}
# Unpacking source
RUN tar xfJ ${CURL_TARBALL_PATH} -C ${SRCDIR}
# Installing build dependencies
RUN apk add gcc make gawk musl-dev file zlib-dev zlib-static openssl-dev openssl-libs-static nss-dev nss-static bearssl-dev mbedtls-dev mbedtls-static libssh2-dev libssh2-static brotli-dev brotli-static rtmpdump-dev libidn2-dev openldap-dev nghttp2-dev libpsl-dev c-ares-dev c-ares-static perl
# Configuring
RUN cd ${SRCDIR}/curl-* \
    && LDFLAGS="-static -L${TARGETDIR}/lib/" CPPFLAGS="-I${TARGETDIR}/include/" LIBS="-lbrotlidec-static -lbrotlicommon-static" PKG_CONFIG="pkg-config --static" ./configure --disable-shared --with-ca-fallback --with-libssh2 --with-gssapi
# LDFLAGS="-static" PKG_CONFIG="pkg-config --static" ./configure --disable-shared --enable-static --host=x86_64-pc-linux-musl --with-libssh2 --with-gssapi --enable-ares --with-ca-fallback --enable-alt-svc --enable-mqtt --with-ssl --with-gnutls --with-mbedtls --with-nss --with-libmetalink
# Making
RUN cd ${SRCDIR}/curl-* \
    && make -j8 curl_LDFLAGS=-all-static
# Finishing up
RUN mkdir -p $(dirname ${FINAL_BIN_PATH}) \
    && cd ${SRCDIR}/curl-* \
    && cp src/curl ${FINAL_BIN_PATH} \
    && strip ${FINAL_BIN_PATH}