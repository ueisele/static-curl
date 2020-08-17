#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(dirname $0)"

##Curl
#If you prefer the latest release you can set it specifically
CURL_VERSION=LATEST
#If you prefer a specific version you can set it specifically
#VERSION=7.71.1
##Heimdal
#If you prefer the latest version you can set it specifically
HEIMDAL_VERSION=master
#If you prefer the latest release you can set it specifically
#HEIMDAL_VERSION=LATEST
#If you prefer a specific version you can set it specifically
#HEIMDAL_VERSION=heimdal-7.7.0
HEIMDAL_GITREPO_NAME=heimdal/heimdal

BUILD=false
CLEAN=false

function usage () {
    echo "$0: $1" >&2
    echo
    echo "Usage: $0 build [--curl-version <LATEST,7.71.1,...>] [--heimdal-version <LATEST,master,heimdal-7.7.0,...>]"
    echo "Usage: $0 clean"
    echo
    return 1
}

function resolve_curl_version () {
    local curl_version=${1:?'Requires curl version as fist parameter!'}
    local actual_curl_version
    if [ "${curl_version}" = 'LATEST' ] || [ "${curl_version}" = 'latest' ] ; then
        actual_curl_version=$(wget "https://curl.haxx.se/download/?C=M;O=D" -qO - | grep -w -m 1 -o 'curl-.*\.tar\.xz"' | sed 's/^curl-\(.\+\).tar.xz"$/\1/')
    else
        actual_curl_version=${curl_version}
    fi
    echo ${actual_curl_version}
}

function resolve_github_repo_version () {
    local gitrepo_name=${1:?'Requires a name of the GitHub repository ad first parameter!'}
    local gitrepo_revision=${2:-LATEST}
    local actual_revision;
    if [ "${gitrepo_revision}" = 'LATEST' ] || [ "${gitrepo_revision}" = 'latest' ]; then
        actual_revision=$(wget https://api.github.com/repos/\${gitrepo_name}/releases/latest -qO - | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    else
        actual_revision=${gitrepo_revision}
    fi
    echo ${actual_revision}
}

function resolve_current_repo_name () {
    local name
    local git_remote=$(git config --get remote.origin.url)
    if [ $? == 0 ]; then
        name=${git_remote}
    else
        name=$(basename ${SCRIPT_DIR})
    fi
    echo ${name}
}

function resolve_image_label() {
    local image_name=${1:?"Missing image name as first parameter!"}
    local label=${2:?"Missing label name as second parameter!"}
    local value=$(docker inspect --format "{{ index .Config.Labels \"${label}\" }}" "${image_name}")
    echo ${value}
}

function build () {
    local curl_version=$(resolve_curl_version ${CURL_VERSION})
    local heimdal_version=$(resolve_github_repo_version ${HEIMDAL_GITREPO_NAME} ${HEIMDAL_VERSION})
    
    echo "Build Curl version '${curl_version}' with Heimdal '${heimdal_version}'."
    local image_name=curl-build:${curl_version}
    docker build --target curl-build \
        -t ${image_name} \
        --build-arg CREATOR=$(resolve_current_repo_name) \
        --build-arg CURL_VERSION=${curl_version} \
        --build-arg HEIMDAL_VERSION=${heimdal_version} \
        --build-arg HEIMDAL_GITREPO_NAME=${HEIMDAL_GITREPO_NAME} \
        ${SCRIPT_DIR}

    echo "Extract build artifacts to ${SCRIPT_DIR}"
    local curl_out_path="$(resolve_image_label ${image_name} 'curl.dir')"
    local tmp_container_name=curl-build-${curl_version}-$RANDOM
    docker create --name ${tmp_container_name} -l creator=$(resolve_current_repo_name) ${image_name}
    docker cp "${tmp_container_name}:${curl_out_path}" "${SCRIPT_DIR}"
    docker rm ${tmp_container_name}
}

function clean () {
    echo "Removing all temporary build images"
    docker container prune --force --filter "label=creator=$(resolve_current_repo_name)"
    docker image prune --force --all --filter "label=creator=$(resolve_current_repo_name)"
}

function parseCmdBuild () {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --curl-version)
                shift
                case "$1" in
                    ""|--*)
                        usage "Requires curl version"
                        return 1
                        ;;
                    *)
                        CURL_VERSION="$1"
                        shift
                        ;;
                esac
                ;;
            --heimdal-version)
                shift
                case "$1" in
                    ""|--*)
                        usage "Requires Heimdal version"
                        return 1
                        ;;
                    *)
                        HEIMDAL_VERSION="$1"
                        shift
                        ;;
                esac
                ;;
            *)
                usage "Unknown option: $1"
                return $?
                ;;
        esac
    done
    return 0
}

function parseCmd () {
    if [ $# -gt 0 ]; then
        case "$1" in
            build)
                BUILD=true
                shift
                parseCmdBuild "$@"
                local retval=$?
                if [ $retval != 0 ]; then
                    return $retval
                fi
                ;;
            clean)
                CLEAN=true
                shift
                ;;
            *)
                usage "Unknown option: $1"
                return $?
                ;;
        esac
    fi
    if [ "$BUILD" = false ] && [ "$CLEAN" = false ]; then
        usage "Missing option"
        return $?
    fi
    return 0
}

function main () {
    parseCmd "$@"
    local retval=$?
    if [ $retval != 0 ]; then
        exit $retval
    fi

    if [ "$BUILD" = true ]; then
        build
    fi
    if [ "$CLEAN" = true ]; then
        clean
    fi
}

main "$@"