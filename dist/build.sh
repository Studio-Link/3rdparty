#!/bin/bash -ex
#
# Builds all static 3rdparty libraries for one target into build/3rdparty
# and packs them as build/$BUILD_TARGET.zip
#
# BUILD_TARGET: linux | linuxjack | linux_arm64 |
#               windows32 | windows64 | macos_x86_64 | macos_arm64
# BUILD_OS:     linux | mingw | macos
#

source dist/lib/versions.sh
source dist/lib/functions.sh

DIST="$(pwd)/dist"
JOBS="${JOBS:-4}"
make_opts="-j$JOBS"

# Prepare build
#-----------------------------------------------------------------------------
sl_prepare

_toolchain=""
_host=""
openssl_target=""
portaudio_opts=""

_target="$BUILD_TARGET"
if [ "$BUILD_TARGET" == "linux_arm64" ] && [ "$(uname -m)" == "aarch64" ]; then
    _target="linux_native"
fi

case "$_target" in
    linux|linuxjack|linux_native)
        openssl_target="linux-$(uname -m)"
        # libasound is loaded with dlopen at runtime, so the binary also starts
        # on systems without ALSA. PulseAudio (and JACK) are linked dynamically.
        portaudio_opts="-DPA_USE_ALSA=ON -DPA_ALSA_DYNAMIC=ON"
        portaudio_opts+=" -DPA_USE_PULSEAUDIO=ON -DPA_USE_OSS=OFF"
        portaudio_opts+=" -DPA_USE_SNDIO=OFF"
        if [ "$BUILD_TARGET" == "linuxjack" ]; then
            portaudio_opts+=" -DPA_USE_JACK=ON"
        else
            portaudio_opts+=" -DPA_USE_JACK=OFF"
        fi
        ;;
    linux_arm64)
        _host="aarch64-linux-gnu"
        _toolchain="$DIST/lib/aarch64.cmake"
        openssl_target="linux-aarch64"
        portaudio_opts="-DPA_USE_ALSA=ON -DPA_ALSA_DYNAMIC=ON"
        portaudio_opts+=" -DPA_USE_PULSEAUDIO=OFF -DPA_USE_JACK=OFF"
        portaudio_opts+=" -DPA_USE_OSS=OFF -DPA_USE_SNDIO=OFF"
        ;;
    windows32|windows64)
        if [ "$BUILD_TARGET" == "windows32" ]; then
            export MINGW_ARCH=32
            _host="i686-w64-mingw32"
            openssl_target="mingw"
        else
            export MINGW_ARCH=64
            _host="x86_64-w64-mingw32"
            openssl_target="mingw64"
        fi
        _toolchain="$DIST/lib/mingw.cmake"
        portaudio_opts="-DPA_USE_WASAPI=ON -DPA_USE_WDMKS=ON -DPA_USE_WMME=ON"
        portaudio_opts+=" -DPA_USE_DS=ON -DPA_USE_ASIO=OFF -DPA_USE_JACK=OFF"
        portaudio_opts+=" -DPA_DLL_LINK_WITH_STATIC_RUNTIME=OFF"
        unset CC CXX
        ;;
    macos_x86_64|macos_arm64)
        export MACOSX_DEPLOYMENT_TARGET=10.13
        if [ "$BUILD_TARGET" == "macos_arm64" ]; then
            _macos_arch="arm64"
            _host="aarch64-apple-darwin"
            openssl_target="darwin64-arm64-cc"
        else
            _macos_arch="x86_64"
            _host="x86_64-apple-darwin"
            openssl_target="darwin64-x86_64-cc"
        fi
        export CFLAGS="$CFLAGS -arch $_macos_arch"
        export CXXFLAGS="$CXXFLAGS -arch $_macos_arch"
        export LDFLAGS="$LDFLAGS -arch $_macos_arch"
        portaudio_opts="-DPA_USE_JACK=OFF"
        ;;
    *)
        echo "unknown BUILD_TARGET: $BUILD_TARGET"
        exit 1
        ;;
esac

cmake_args="$(sl_cmake_args)"

# PortAudio
#-----------------------------------------------------------------------------
if [ ! -f "$PREFIX/lib/libportaudio.a" ]; then
    sl_fetch "https://github.com/PortAudio/portaudio/archive/${portaudio}.tar.gz" \
        "portaudio-${portaudio}.tar.gz" "$portaudio_sha256"
    rm -rf portaudio && mkdir portaudio
    tar --no-same-owner -xzf "portaudio-${portaudio}.tar.gz" -C portaudio --strip-components=1
    patch -d portaudio -p1 < "$DIST/patches/portaudio_pulseaudio_optional.patch"

    cmake -S portaudio -B portaudio/build $cmake_args \
        -DPA_BUILD_SHARED_LIBS=OFF -DPA_BUILD_TESTS=OFF \
        -DPA_BUILD_EXAMPLES=OFF $portaudio_opts
    cmake --build portaudio/build -j "$JOBS"
    cmake --install portaudio/build

    # lock-free ring buffer (compiled into libportaudio.a, header is private)
    cp -a portaudio/src/common/pa_ringbuffer.h "$PREFIX/include/"
fi

# libsamplerate
#-----------------------------------------------------------------------------
if [ ! -f "$PREFIX/lib/libsamplerate.a" ]; then
    sl_fetch "https://github.com/libsndfile/libsamplerate/releases/download/${libsamplerate}/libsamplerate-${libsamplerate}.tar.xz" \
        "libsamplerate-${libsamplerate}.tar.xz" "$libsamplerate_sha256"
    rm -rf libsamplerate-${libsamplerate}
    tar --no-same-owner -xf libsamplerate-${libsamplerate}.tar.xz

    cmake -S libsamplerate-${libsamplerate} \
        -B libsamplerate-${libsamplerate}/build $cmake_args \
        -DBUILD_TESTING=OFF -DLIBSAMPLERATE_EXAMPLES=OFF \
        -DLIBSAMPLERATE_INSTALL=ON
    cmake --build libsamplerate-${libsamplerate}/build -j "$JOBS"
    cmake --install libsamplerate-${libsamplerate}/build
fi

# OpenSSL
#-----------------------------------------------------------------------------
if [ ! -f "$PREFIX/lib/libssl.a" ]; then
    sl_fetch "https://github.com/openssl/openssl/releases/download/openssl-${openssl}/openssl-${openssl}.tar.gz" \
        "openssl-${openssl}.tar.gz" "$openssl_sha256"
    rm -rf openssl-${openssl}
    tar --no-same-owner -xzf openssl-${openssl}.tar.gz
    pushd openssl-${openssl}

    openssl_opts="no-shared no-tests no-docs no-apps --prefix=$PREFIX"
    openssl_opts+=" --libdir=lib"
    if [ -n "$_host" ] && [ "$BUILD_OS" != "macos" ]; then
        openssl_opts+=" --cross-compile-prefix=${_host}-"
    fi
    if [ "$BUILD_OS" == "mingw" ]; then
        openssl_opts+=" no-threads"
    fi

    # Debian/Ubuntu mingw-w64: posix thread variant (see dist/lib/mingw.cmake)
    # (Configure stores CC in the Makefile, so it is only needed here)
    openssl_cc=""
    if [ "$BUILD_OS" == "mingw" ] && command -v ${_host}-gcc-posix > /dev/null; then
        openssl_cc="CC=gcc-posix CXX=g++-posix"
    fi

    env $openssl_cc ./Configure $openssl_target $openssl_opts
    make $make_opts build_libs
    make install_dev
    popd
fi

# FLAC
#-----------------------------------------------------------------------------
if [ ! -f "$PREFIX/lib/libFLAC.a" ]; then
    sl_fetch "https://github.com/xiph/flac/releases/download/${flac}/flac-${flac}.tar.xz" \
        "flac-${flac}.tar.xz" "$flac_sha256"
    rm -rf flac-${flac}
    tar --no-same-owner -xf flac-${flac}.tar.xz

    cmake -S flac-${flac} -B flac-${flac}/build $cmake_args \
        -DWITH_OGG=OFF -DBUILD_CXXLIBS=OFF -DBUILD_PROGRAMS=OFF \
        -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF -DBUILD_DOCS=OFF \
        -DINSTALL_MANPAGES=OFF -DINSTALL_PKGCONFIG_MODULES=ON
    cmake --build flac-${flac}/build -j "$JOBS"
    cmake --install flac-${flac}/build
fi

# Opus
#-----------------------------------------------------------------------------
if [ ! -f "$PREFIX/lib/libopus.a" ]; then
    sl_fetch "https://downloads.xiph.org/releases/opus/opus-${opus}.tar.gz" \
        "opus-${opus}.tar.gz" "$opus_sha256"
    rm -rf opus-${opus}
    tar --no-same-owner -xzf opus-${opus}.tar.gz

    opus_opts="-DOPUS_BUILD_PROGRAMS=OFF -DOPUS_BUILD_TESTING=OFF"
    opus_opts+=" -DOPUS_CUSTOM_MODES=ON -DOPUS_INSTALL_PKG_CONFIG_MODULE=ON"
    opus_opts+=" -DOPUS_INSTALL_CMAKE_CONFIG_MODULE=ON"
    if [ "$BUILD_OS" == "macos" ] || [ "$BUILD_OS" == "mingw" ]; then
        # avoid stack protector and fortify issues with older SDKs/runtimes
        opus_opts+=" -DOPUS_FORTIFY_SOURCE=OFF -DOPUS_STACK_PROTECTOR=OFF"
    fi

    cmake -S opus-${opus} -B opus-${opus}/build $cmake_args $opus_opts
    cmake --build opus-${opus}/build -j "$JOBS"
    cmake --install opus-${opus}/build
fi

# Prepare release upload
#-----------------------------------------------------------------------------
# Only static libs and headers are shipped
rm -rf 3rdparty/bin 3rdparty/share 3rdparty/lib/*.so* 3rdparty/lib/*.dylib \
    3rdparty/lib/*.dll.a
rm -f $BUILD_TARGET.zip
zip -qr $BUILD_TARGET.zip 3rdparty
