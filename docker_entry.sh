#!/usr/bin/env bash
# based of scripts in https://github.com/facebook/mcrouter/tree/master/mcrouter/scripts
set -ex

#dir=$(mktemp -d  -p /var/tmp)
dir=/var/tmp/tmp.AJvPCDTbXG
shared_dir="/build"
pkg_dir="${dir}/pkgs"
install_dir="${dir}/install"
mcrouter_version="v0.41.0-release"

export LDFLAGS="-L${install_dir}/lib -ldl -ljemalloc $LDFLAGS"
export CPPFLAGS="-I${install_dir}/include $CPPFLAGS"

apt-get update

# could create an image with these preloaded
apt-get install -y autoconf binutils-dev bison cmake flex g++ gcc git \
  libboost1.67-all-dev libbz2-dev libdouble-conversion-dev libevent-dev \
  libgflags-dev libgoogle-glog-dev libjemalloc-dev liblz4-dev liblzma-dev \
  liblzma5 libsnappy-dev libsodium-dev libssl-dev libtool libunwind8-dev \
  libfmt-dev zlib1g-dev libzstd-dev make pkg-config python-dev python-six \
  dpkg-dev debhelper ragel

function build_git {
  repo=$1
  checkout=$2
  cmake_extra=$3
  cmake_dir=${4:-.}
  build_dir=$5
  cxxflags=$6
  checkout_dir=$( sed s'/.git$//' <<<"${repo##*/}")
  [ -z "${build_dir}" ] && build_dir=${checkout_dir}
  cd "${pkg_dir}"
  [ -d "${checkout_dir}" ] || git clone "${repo}" 
  cd "${checkout_dir}"
  [ -n "${checkout}" ] && git checkout "${checkout}"
  mkdir -p "${pkg_dir}/${build_dir}"
  cd "${pkg_dir}/${build_dir}"
  cmake_args="${cmake_extra} -DCMAKE_INSTALL_PREFIX=${install_dir}"
  CXXFLAGS="$CXXFLAGS ${cxxflags}" \
    LD_LIBRARY_PATH="$install_dir/lib:$LD_LIBRARY_PATH" \
    LD_RUN_PATH="$install_dir/lib:$LD_RUN_PATH" \
    cmake ${cmake_args} "${cmake_dir}"
  make
  make install
}

function build_mcrouter {
  cd "${pkg_dir}"
  [ -d "${pkg_dir}/googletest" ] || git clone https://github.com/google/googletest.git
  mkdir -p ./lib/gtest
  cp -r -f -t ./lib/gtest "$pkg_dir/googletest/googletest"/*
  cd "${pkg_dir}/mcrouter/mcrouter"
  autoreconf --install
  LD_LIBRARY_PATH="${install_dir}/lib:$LD_LIBRARY_PATH" \
    LD_RUN_PATH="${install_dir}/lib:$LD_RUN_PATH" \
    LDFLAGS="-L${install_dir}/lib $LDFLAGS" \
    CPPFLAGS="-I${install_dir}/include $CPPFLAGS" \
    FBTHRIFT_BIN="${install_dir}/bin/" \
    ./configure --prefix="${shared_dir}/mcrouter"
  make
  make install
}

mkdir -p "${pkg_dir}" "${install_dir}"
cd "${pkg_dir}"
[ -d "${pkg_dir}/mcrouter" ] || git clone https://github.com/facebook/mcrouter.git
cd "${pkg_dir}/mcrouter"
[ -z "${mcrouter_version}" ] || git checkout "${mcrouter_version}"

mcrouter_base="${pkg_dir}/mcrouter/mcrouter"

build_git https://github.com/facebook/folly \
  "$(<${mcrouter_base}/FOLLY_COMMIT)" "" ".." "folly/folly" "-fPIC"

build_git https://github.com/facebookincubator/fizz \
  "$(<${mcrouter_base}/FIZZ_COMMIT)" "-DBUILD_TESTS=OFF" "." "fizz/fizz"

build_git https://github.com/facebook/wangle \
  "$(<${mcrouter_base}/WANGLE_COMMIT)" "-DBUILD_TESTS=OFF" "." "wangle/wangle"

build_git https://github.com/rsocket/rsocket-cpp \
  "" "-DBUILD_BENCHMARKS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_TESTS=OFF" ".." \
  "rsocket-cpp/build" "-fPIC"

build_git https://github.com/facebook/fbthrift \
  "$(<${mcrouter_base}/FBTHRIFT_COMMIT)" "" ".."  "fbthrift/build" "-fPIC"

build_mcrouter "${mcrouter_version}"

cd "${shared_dir}/mcrouter"
dpkg-buildpackage -us -uc
