#!/bin/bash

set -e

PACKAGE_NAME=$1
MANIFEST_PATH=$2
OUT_DIR=$3

if ! test -f "$MANIFEST_PATH"; then
    echo "$MANIFEST_PATH does not exist"
    exit 1
fi

mkdir -p "$OUT_DIR"

function build_rhel_7() {
    local packages=("$@")
    local outdir="${OUT_DIR}/rhel-7"

    mkdir -p "${outdir}"

    docker rm -f "rhel-7-${PACKAGE_NAME}" 2>/dev/null || true
    # Use the oldest OS minor version supported to ensure that updates required for outdated
    # packages are included.
    docker run \
        --name "rhel-7-${PACKAGE_NAME}" \
        centos:7.4.1708 \
        /bin/bash -c "\
            set -x
            yum update -y ca-certificates && \
            yum install -y epel-release && \
            mkdir -p /packages/archives && \
            yumdownloader --installroot=/tmp/empty-directory --releasever=/ --resolve --destdir=/packages/archives -y ${packages[*]}"
    sudo docker cp "rhel-7-${PACKAGE_NAME}":/packages/archives "${outdir}"
    sudo chown -R $UID "${outdir}"
}

function build_rhel_7_force() {
    local packages=("$@")
    local outdir="${OUT_DIR}/rhel-7-force"

    mkdir -p "${outdir}"

    docker rm -f "rhel-7-force-${PACKAGE_NAME}" 2>/dev/null || true
    # Use the oldest OS minor version supported to ensure that updates required for outdated
    # packages are included.
    docker run \
        --name "rhel-7-force-${PACKAGE_NAME}" \
        centos:7.4.1708 \
        /bin/bash -c "\
            set -x
            yum update -y ca-certificates && \
            yum install -y epel-release && \
            mkdir -p /packages/archives && \
            yumdownloader --resolve --destdir=/packages/archives -y ${packages[*]}"
    sudo docker cp "rhel-7-force-${PACKAGE_NAME}":/packages/archives "${outdir}"
    sudo chown -R $UID "${outdir}"
}

function createrepo_rhel_7() {
    local outdir=
    outdir="$(realpath "${OUT_DIR}")/rhel-7"

    docker rm -f "rhel-7-createrepo-${PACKAGE_NAME}" 2>/dev/null || true
    docker run \
        --name "rhel-7-createrepo-${PACKAGE_NAME}" \
        -v "${outdir}/archives":/packages/archives \
        centos:7.4.1708 \
        /bin/bash -c "\
            set -x
            yum install -y createrepo && \
            createrepo /packages/archives"
    sudo docker cp "rhel-7-createrepo-${PACKAGE_NAME}":/packages/archives "${outdir}"
    sudo chown -R $UID "${outdir}"
}

function build_rhel_8() {
    local packages=("$@")
    local outdir="${OUT_DIR}/rhel-8"

    mkdir -p "${outdir}"

    docker rm -f "rhel-8-${PACKAGE_NAME}" 2>/dev/null || true
    # Use the oldest OS minor version supported to ensure that updates required for outdated
    # packages are included.
    docker run \
        --name "rhel-8-${PACKAGE_NAME}" \
        rockylinux:8.5 \
        /bin/bash -c "\
            set -x
            echo -e \"fastestmirror=1\nmax_parallel_downloads=8\" >> /etc/dnf/dnf.conf && \
            yum install -y yum-utils epel-release && \
            mkdir -p /packages/archives && \
            yumdownloader --installroot=/tmp/empty-directory --releasever=/ --resolve --destdir=/packages/archives -y ${packages[*]}"
    sudo docker cp "rhel-8-${PACKAGE_NAME}":/packages/archives "${outdir}"
    sudo chown -R $UID "${outdir}"
}

function createrepo_rhel_8() {
    local outdir=
    outdir="$(realpath "${OUT_DIR}")/rhel-8"

    docker rm -f "rhel-8-createrepo-${PACKAGE_NAME}" 2>/dev/null || true
    docker run \
        --name "rhel-8-createrepo-${PACKAGE_NAME}" \
        -v "${outdir}/archives":/packages/archives \
        rockylinux:8.5 \
        /bin/bash -c "\
            set -x
            echo -e \"fastestmirror=1\nmax_parallel_downloads=8\" >> /etc/dnf/dnf.conf && \
            yum install -y yum-utils createrepo && \
            yum-config-manager --add-repo http://mirror.centos.org/centos/8-stream/AppStream/x86_64/os/ && \
            yum install -y modulemd-tools && \
            createrepo_c /packages/archives && \
            repo2module --module-name=kurl.local --module-stream=stable /packages/archives /tmp/modules.yaml && \
            modifyrepo_c --mdtype=modules /tmp/modules.yaml /packages/archives/repodata"
    sudo docker cp "rhel-8-createrepo-${PACKAGE_NAME}":/packages/archives "${outdir}"
    sudo chown -R $UID "${outdir}"
}

function build_ol_7() {
    local packages=("$@")
    local outdir="${OUT_DIR}/ol-7"

    mkdir -p "${outdir}"

    docker rm -f "ol-7-${PACKAGE_NAME}" 2>/dev/null || true
    # Use the oldest OS minor version supported to ensure that updates required for outdated
    # packages are included.
    docker run \
        --name "ol-7-${PACKAGE_NAME}" \
        centos:7.4.1708 \
        /bin/bash -c "\
            set -x && \
            yum-config-manager --add-repo=http://public-yum.oracle.com/repo/OracleLinux/OL7/latest/x86_64/ && \
            mkdir -p /packages/archives && \
            yumdownloader --disablerepo=* --enablerepo=public-yum.oracle.com_repo_OracleLinux_OL7_latest_x86_64_ --installroot=/tmp/empty-directory --releasever=/ --resolve --destdir=/packages/archives -y ${packages[*]}"
    sudo docker cp "ol-7-${PACKAGE_NAME}":/packages/archives "${outdir}"
    sudo chown -R $UID "${outdir}"
}

function createrepo_ol_7() {
    local outdir=
    outdir="$(realpath "${OUT_DIR}")/ol-7"

    docker rm -f "ol-7-createrepo-${PACKAGE_NAME}" 2>/dev/null || true
    docker run \
        --name "ol-7-createrepo-${PACKAGE_NAME}" \
        -v "${outdir}/archives":/packages/archives \
        centos:7.4.1708 \
        /bin/bash -c "\
            set -x
            yum install -y createrepo && \
            createrepo /packages/archives"
    sudo docker cp "ol-7-createrepo-${PACKAGE_NAME}":/packages/archives "${outdir}"
    sudo chown -R $UID "${outdir}"
}

function try_5_times() {
    local fn="$1"
    local args=("${@:2}")

    n=0
    while ! $fn "${args[@]}" ; do
        n="$(( n + 1 ))"
        if [ "$n" = "5" ]; then
            return 1
        fi
        sleep 2
    done
}

pkgs_rhel7=()
pkgs_rhel8=()
pkgs_ol7=()

while read -r line || [ -n "$line" ]; do
    if [ -z "$line" ]; then
        continue
    fi
    # support for comments in manifest files
    if [ "$(echo $line | cut -c1-1)" = "#" ]; then
        continue
    fi
    kind=$(echo $line | awk '{ print $1 }')

    echo "LINE $line"

    case "$kind" in
        image)
            mkdir -p "$OUT_DIR/images"
            filename=$(echo "$line" | awk '{ print $2 }')
            image=$(echo "$line" | awk '{ print $3 }')
            # we support both remote images and tar archives
            if echo "$image" | grep -q '\.tar$' ; then
                gzip -c "$image" > "$OUT_DIR/images/${filename}.tar.gz"
            else
                try_5_times docker pull "$image"
                docker save "$image" | gzip > "$OUT_DIR/images/${filename}.tar.gz"
            fi
            ;;

        asset)
            mkdir -p "$OUT_DIR/assets"
            filename=$(echo "$line" | awk '{ print $2 }')
            asset=$(echo "$line" | awk '{ print $3 }')
            # we support both http and local assets
            if echo "$asset" | grep -q '^https://' ; then
                curl -fL -o "$OUT_DIR/assets/$filename" "$asset"
            else
                cp "$asset" "$OUT_DIR/assets/$filename"
            fi
            ;;

        apt)
            mkdir -p $OUT_DIR/ubuntu-22.04 $OUT_DIR/ubuntu-20.04 $OUT_DIR/ubuntu-18.04 $OUT_DIR/ubuntu-16.04
            package=$(echo $line | awk '{ print $2 }')

            docker rm -f ubuntu-2204-${package} 2>/dev/null || true
            docker run \
                --name ubuntu-2204-${package} \
                ubuntu:22.04 \
                /bin/bash -c "\
                    mkdir -p /packages/archives && \
                    apt update -y \
                    && apt install -d --no-install-recommends -y $package \
                    -oDebug::NoLocking=1 -o=dir::cache=/packages/"
            docker cp ubuntu-2204-${package}:/packages/archives $OUT_DIR/ubuntu-22.04
            sudo chown -R $UID $OUT_DIR/ubuntu-22.04

            docker rm -f ubuntu-2004-${package} 2>/dev/null || true
            docker run \
                --name ubuntu-2004-${package} \
                ubuntu:20.04 \
                /bin/bash -c "\
                    mkdir -p /packages/archives && \
                    apt update -y \
                    && apt install -d --no-install-recommends -y $package \
                    -oDebug::NoLocking=1 -o=dir::cache=/packages/"
            docker cp ubuntu-2004-${package}:/packages/archives $OUT_DIR/ubuntu-20.04
            sudo chown -R $UID $OUT_DIR/ubuntu-20.04

            docker rm -f ubuntu-1804-${package} 2>/dev/null || true
            docker run \
                --name ubuntu-1804-${package} \
                ubuntu:18.04 \
                /bin/bash -c "\
                    mkdir -p /packages/archives && \
                    apt update -y \
                    && apt install -d --no-install-recommends -y $package \
                    -oDebug::NoLocking=1 -o=dir::cache=/packages/"
            docker cp ubuntu-1804-${package}:/packages/archives $OUT_DIR/ubuntu-18.04
            sudo chown -R $UID $OUT_DIR/ubuntu-18.04

            docker rm -f ubuntu-1604-${package} 2>/dev/null || true
            docker run \
                --name ubuntu-1604-${package} \
                ubuntu:16.04 \
                /bin/bash -c "\
                    mkdir -p /packages/archives && \
                    apt update -y \
                    && apt install -d --no-install-recommends -y $package \
                    -oDebug::NoLocking=1 -o=dir::cache=/packages/"
            docker cp ubuntu-1604-${package}:/packages/archives $OUT_DIR/ubuntu-16.04
            sudo chown -R $UID $OUT_DIR/ubuntu-16.04
            ;;

        yum)
            package=$(echo "${line}" | awk '{ print $2 }')
            pkgs_rhel7+=("${package}")
            pkgs_rhel8+=("${package}")
            ;;

        yum8)
            package=$(echo "${line}" | awk '{ print $2 }')
            pkgs_rhel8+=("${package}")
            ;;

        yumol)
            package=$(echo "${line}" | awk '{ print $2 }')
            pkgs_ol7+=("${package}")
            ;;

        dockerout)
            dstdir=$(echo $line | awk '{ print $2 }')
            dockerfile=$(echo $line | awk '{ print $3 }')
            version=$(echo $line | awk '{ print $4 }')

            outdir="$OUT_DIR/$dstdir"
            name=$(< /dev/urandom tr -dc a-z | head -c8)

            mkdir -p $outdir

            docker build --build-arg VERSION=$version -t "$name" - < "$dockerfile"
            docker run --rm -v $outdir:/out $name
            sudo chown -R $UID $outdir
            ;;

        *)
            echo "Unknown kind $kind in line: $line"
            exit 1
            ;;
    esac
done < "${MANIFEST_PATH}"

if [ "${#pkgs_rhel7[@]}" -gt "0" ]; then
    build_rhel_7 "${pkgs_rhel7[@]}"
fi
if [ -d "${OUT_DIR}/rhel-7" ] && [ "$(ls -A "${OUT_DIR}/rhel-7")" ]; then
    createrepo_rhel_7
fi
if [ "${#pkgs_rhel7[@]}" -gt "0" ]; then
    build_rhel_7_force "${pkgs_rhel7[@]}"
fi
if [ "${#pkgs_rhel8[@]}" -gt "0" ]; then
    build_rhel_8 "${pkgs_rhel8[@]}"
fi
if [ -d "${OUT_DIR}/rhel-8" ] && [ "$(ls -A "${OUT_DIR}/rhel-8")" ]; then
    createrepo_rhel_8
fi
if [ "${#pkgs_ol7[@]}" -gt "0" ]; then
    build_ol_7 "${pkgs_ol7[@]}"
fi
if [ -d "${OUT_DIR}/ol-7" ] && [ "$(ls -A "${OUT_DIR}/ol-7")" ]; then
    createrepo_ol_7
fi
