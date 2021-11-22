sl_prepare_version() {
    vminor_t=$(printf "%02d" $vminor)
    version_t="v$vmajor.$vminor_t.$vpatch"
    version_n="$vmajor.$vminor.$vpatch"
}

sl_prepare() {
    echo "start build on $BUILD_TARGET ($BUILD_OS)"
    sl_prepare_version

    mkdir -p build;
    pushd build
    mkdir -p 3rdparty/include
    mkdir -p 3rdparty/lib

    SHASUM=$(which shasum)
}

sl_get_openssl() {
    wget https://www.openssl.org/source/openssl-${openssl}.tar.gz
    echo "$openssl_sha256  openssl-${openssl}.tar.gz" | \
        ${SHASUM} -a 256 -c -
    tar -xzf openssl-${openssl}.tar.gz
    ln -s openssl-${openssl} openssl
}

sl_get_flac() {
    wget https://ftp.osuosl.org/pub/xiph/releases/flac/flac-${flac}.tar.xz
    tar -xf flac-${flac}.tar.xz
    ln -s flac-${flac} flac
}

sl_get_soundio() {
    wget https://github.com/studio-link-3rdparty/libsoundio/archive/master.tar.gz -O soundio.tar.gz
    tar -xzf soundio.tar.gz
    wget https://github.com/studio-link-3rdparty/libsoundio/compare/master...wasapi_patches.diff
    wget https://github.com/studio-link-3rdparty/libsoundio/compare/master...pulseaudio_patches.diff
    wget https://github.com/studio-link-3rdparty/libsoundio/compare/master...coreaudio_patches.diff
    pushd libsoundio-master
    if [ "$BUILD_OS" == "macos" ]; then
        patch --ignore-whitespace -p1 < ../master...coreaudio_patches.diff
    else
        patch --ignore-whitespace -p1 < ../master...wasapi_patches.diff
        patch --ignore-whitespace -p1 < ../master...pulseaudio_patches.diff
    fi
    popd
    ln -s libsoundio-master soundio
    cp -a libsoundio-master/soundio 3rdparty/include/
    cp -a ../dist/windows/soundio/toolchain.cmake soundio/
    cp -a ../dist/lib/arm.cmake soundio/
    cp -a ../dist/lib/aarch64.cmake soundio/
    rm soundio.tar.gz
}
