ARG CREATOR=static-curl
ARG WORKDIR=/workspace
ARG SRCDIR=${WORKDIR}/src
ARG TARGETDIR=${WORKDIR}/target

## Build Base Image ##
FROM alpine:edge as base-build
ARG WORKDIR
WORKDIR ${WORKDIR}
# Prepare System
RUN apk update && apk upgrade
RUN apk add wget git gawk gcc make autoconf automake musl-dev
# Labels
ARG CREATOR
LABEL creator=${CREATOR}

## Build Heimdal ##
FROM base-build as heimdal-build
# Clone Repository
ARG SRCDIR
ARG HEIMDAL_VERSION=master
ARG HEIMDAL_GITREPO_NAME=heimdal/heimdal
ARG HEIMDAL_GITREPO_URL=https://github.com/${HEIMDAL_GITREPO_NAME}.git
ARG HEIMDAL_GITREPO_PATH=${SRCDIR}/${HEIMDAL_GITREPO_NAME}
RUN git clone -q -b ${HEIMDAL_VERSION} ${HEIMDAL_GITREPO_URL} ${HEIMDAL_GITREPO_PATH}
# Installing build dependencies
RUN apk add libtool bison flex perl-json python3 openssl-dev openssl-libs-static ncurses-dev ncurses-static \
    && ln -sf /usr/bin/python3.8 /usr/bin/python
# Prepare configuration
RUN cd ${HEIMDAL_GITREPO_PATH} \
  && autoreconf -f -i \
  && mkdir build
# Configuring
ARG TARGETDIR
RUN cd ${HEIMDAL_GITREPO_PATH}/build \
  && ../configure --disable-shared --prefix=${TARGETDIR} --with-openssl --with-pic=yes --without-berkeley-db --without-readline --without-openldap --without-hcrypto-fallback --disable-otp --disable-heimdal-documentation
# Making    
RUN cd ${HEIMDAL_GITREPO_PATH}/build \
    && LDFLAGS=-all-static make -j8
# Installing
RUN cd ${HEIMDAL_GITREPO_PATH}/build \
    && make install
# Labels
ARG CREATOR
LABEL creator=${CREATOR}
LABEL heimdal.version=${HEIMDAL_VERSION}
LABEL heimdal.dir=${TARGETDIR}

## Build Curl ##
FROM base-build as curl-build
# Fetching Curl source
ARG SRCDIR
ARG CURL_VERSION=7.71.1
ARG CURL_GPG_KEY_URL="https://daniel.haxx.se/mykey.asc"
ARG CURL_GPG_KEY_PATH=${SRCDIR}/curl-gpg.pub
ARG CURL_TARBALL_FILENAME=curl-${CURL_VERSION}.tar.xz
ARG CURL_TARBALL_URL=https://curl.haxx.se/download/${CURL_TARBALL_FILENAME}
ARG CURL_TARBALL_PATH=${SRCDIR}/${CURL_TARBALL_FILENAME}
RUN mkdir -p ${SRCDIR} \
    && wget "${CURL_GPG_KEY_URL}" -qO "${CURL_GPG_KEY_PATH}" \
    && wget "${CURL_TARBALL_URL}.asc" -qO "${CURL_TARBALL_PATH}.asc" \
    && wget "${CURL_TARBALL_URL}" -qO "${CURL_TARBALL_PATH}"
# Validating curl source
RUN apk add gnupg \
    && gpg --import --always-trust ${CURL_GPG_KEY_PATH} \
    && gpg --verify ${CURL_TARBALL_PATH}.asc ${CURL_TARBALL_PATH}
# Unpacking curl source
RUN tar xfJ ${CURL_TARBALL_PATH} -C ${SRCDIR}
# Installing curl build dependencies
RUN apk add file zlib-dev zlib-static openssl-dev openssl-libs-static nss-dev nss-static bearssl-dev mbedtls-dev mbedtls-static libssh2-dev libssh2-static brotli-dev brotli-static rtmpdump-dev libidn2-dev openldap-dev nghttp2-dev libpsl-dev c-ares-dev c-ares-static perl
# Copy manually built curl dependencies
ARG TARGETDIR
COPY --from=heimdal-build ${TARGETDIR} ${TARGETDIR}
# Configuring curl
RUN cd ${SRCDIR}/curl-* \
    && LDFLAGS="-static -L${TARGETDIR}/lib/" CPPFLAGS="-I${TARGETDIR}/include/" LIBS="-lbrotlidec-static -lbrotlicommon-static" PKG_CONFIG="pkg-config --static" ./configure --disable-shared --enable-ares --enable-alt-svc --enable-mqtt --with-ca-fallback --with-libssh2 --with-gssapi --with-mbedtls
# --with-ssl --with-gnutls --with-nss --with-libmetalink
# Making curl
RUN cd ${SRCDIR}/curl-* \
    && make -j8 curl_LDFLAGS=-all-static
# Finishing up
ARG OUTDIR=${WORKDIR}/out
ARG CURL_FINAL_BIN_PATH=${OUTDIR}/curl
RUN mkdir -p $(dirname ${CURL_FINAL_BIN_PATH}) \
    && cd ${SRCDIR}/curl-* \
    && cp src/curl ${CURL_FINAL_BIN_PATH} \
    && strip ${CURL_FINAL_BIN_PATH} \
    && cp ${CURL_FINAL_BIN_PATH} ${CURL_FINAL_BIN_PATH}-${CURL_VERSION}-$(uname -m)
# Labels
ARG CREATOR
LABEL creator=${CREATOR}
LABEL curl.version=${CURL_VERSION}
LABEL curl.dir=${OUTDIR}