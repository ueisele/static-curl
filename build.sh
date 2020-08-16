#!/bin/sh
set -e

##Curl
VERSION=LATEST
#If you prefer a specific version you can set it specifically
#VERSION=7.71.1
GPG_KEY_URL="https://daniel.haxx.se/mykey.asc"
##Heimdal
HEIMDAL_VERSION=master
#If you prefer a specific version you can set it specifically
#HEIMDAL_VERSION=heimdal-7.7.0
#Do not escape the above variables in script below
#change last argument to -xeus for help with debugging
cat <<EOF | docker run -i --rm -v "$(pwd)":/out --tmpfs /tmp/build:exec -w /tmp/build alpine:edge /bin/sh -eus

#Print failure message we exit unexpectedly
trap 'RC="\$?"; echo "***FAILED! RC=\${RC}"; exit \${RC}' EXIT

#Clone a repository to a location unless it already exists
function conditional_clone () {
  local url=\$1
  local revision=\$2
  local output_path=\$3
  if [ -e \${output_path} ]; then
    echo "Found existing \${output_path}; reusing..."
  else
    echo "Cloning \${url} to \${output_path}..."
    git clone -q \${url} \${output_path}
  fi
  echo "Switching to revision \${revision}..."
  (cd \${output_path} && git checkout \${revision})
}

#Fetch a url to a location unless it already exists
function conditional_fetch () {
  local url=\$1
  local output_path=\$2
  if [ -e \${output_path} ]; then
    echo "Found existing \${output_path}; reusing..."
  else
    echo "Fetching \${url} to \${output_path}..."
    wget "\${url}" -qO "\${output_path}"
  fi
}

function prepare_system () {
  apk update
  apk upgrade
  apk add wget git util-linux
}

function build_static_heimdal () {
  #Save current stats
  local current_path=\$(pwd)

  #Determine repository and revision
  local gitrepo_name=heimdal/heimdal
  local gitrepo_url=https://github.com/\${gitrepo_name}.git
  local gitrepo_path=\$(pwd)/\${gitrepo_name}
  local heimdal_revision
  if [ "${HEIMDAL_VERSION}" = 'LATEST' ]; then
    heimdal_revision=\$(wget https://api.github.com/repos/\${gitrepo_name}/releases/latest -qO - | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
  else
    heimdal_revision=${HEIMDAL_VERSION}
  fi

  echo "***Fetching \${gitrepo_url} to \${gitrepo_path}..."
  conditional_clone \${gitrepo_url} \${heimdal_revision} \${gitrepo_path}
  cd \${gitrepo_path}

  echo "***Installing build dependencies..."
  apk add gcc make gawk musl-dev autoconf automake libtool bison flex perl-json python3 openssl-dev openssl-libs-static ncurses-dev ncurses-static
  ln -sf /usr/bin/python3.8 /usr/bin/python

  echo "***configuring..."
  autoreconf -f -i
  mkdir build
  cd build
  ../configure --disable-shared --prefix=/usr --with-openssl --with-pic=yes --without-berkeley-db --without-readline --without-openldap --without-hcrypto-fallback --disable-otp --disable-heimdal-documentation
  echo "making..."    
  LDFLAGS=-all-static make -j8
  echo "installing..."
  make install

  #Restrore current stats
  cd \${current_path}
}

function build_static_curl () {
  #Save current stats
  local current_path=\$(pwd)

  #Determine tarball filename
  local tarball_filename
  if [ "$VERSION" = 'LATEST' ]; then
    echo "Determining latest version..."
    tarball_filename=\$(wget "https://curl.haxx.se/download/?C=M;O=D" -q -O- | grep -w -m 1 -o 'curl-.*\.tar\.xz"' | sed 's/"$//')
  else
    tarball_filename=curl-${VERSION}.tar.xz
  fi

  #Set some variables (depends on tarball filename determined above)
  local gpg_key_path="\$(pwd)/curl-gpg.pub"
  local tarball_url=https://curl.haxx.se/download/\${tarball_filename}
  local tarball_path="\$(pwd)/\${tarball_filename}"
  local final_bin_path=/out/curl

  echo "***Fetching \${tarball_filename} and files to validate it..."
  conditional_fetch "${GPG_KEY_URL}" "\${gpg_key_path}"
  conditional_fetch "\${tarball_url}.asc" "\${tarball_path}.asc"
  conditional_fetch "\${tarball_url}" "\${tarball_path}"

  echo "***Validating source..."
  apk add gnupg
  gpg --import --always-trust \${gpg_key_path}
  gpg --verify \${tarball_path}.asc \${tarball_path}

  echo "***Unpacking source..."
  tar xfJ \${tarball_path}
  cd curl-*

  echo "***Installing build dependencies..."
  apk add gcc make gawk musl-dev file zlib-dev zlib-static openssl-dev openssl-libs-static nss-dev nss-static bearssl-dev mbedtls-dev mbedtls-static libssh2-dev libssh2-static brotli-dev brotli-static rtmpdump-dev libidn2-dev openldap-dev nghttp2-dev libpsl-dev c-ares-dev c-ares-static perl
  
  echo "***configuring..."
  LDFLAGS="-static" LIBS="-lbrotlidec-static -lbrotlicommon-static" PKG_CONFIG="pkg-config --static" ./configure --disable-shared --with-ca-fallback --with-libssh2 --with-gssapi
  # LDFLAGS="-static" PKG_CONFIG="pkg-config --static" ./configure --disable-shared --enable-static --host=x86_64-pc-linux-musl --with-libssh2 --with-gssapi --enable-ares --with-ca-fallback --enable-alt-svc --enable-mqtt --with-ssl --with-gnutls --with-mbedtls --with-nss --with-libmetalink
  echo "making..."
  make -j8 curl_LDFLAGS=-all-static

  echo "***Finishing up..."
  cp src/curl \${final_bin_path}
  strip \${final_bin_path}
  chown $(id -u):$(id -g) \${final_bin_path}
  echo SUCCESS
  ls -ld \${final_bin_path}
  du -h \${final_bin_path}

  #Restrore current stats
  cd \${current_path}
}

function build () {
  prepare_system
  build_static_heimdal
  build_static_curl
}

#Build
build

#Clear the trap so when we exit there is no failure message
trap - EXIT

EOF