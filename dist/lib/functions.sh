sl_prepare() {
    echo "start build on $BUILD_TARGET ($BUILD_OS)"

    mkdir -p build
    pushd build
    PREFIX="$(pwd)/3rdparty"
    mkdir -p "$PREFIX/include" "$PREFIX/lib"

    if command -v sha256sum >/dev/null; then
        SHA256="sha256sum"
    else
        SHA256="shasum -a 256"
    fi
}

# sl_fetch <url> <file> <sha256>
sl_fetch() {
    if [ ! -f "$2" ]; then
        wget -q "$1" -O "$2.part"
        mv "$2.part" "$2"
    fi
    echo "$3  $2" | $SHA256 -c -
}

# Common cmake arguments: static, release, install into $PREFIX and the
# cross toolchain for the current target (if any).
sl_cmake_args() {
    local args="-DCMAKE_BUILD_TYPE=Release"
    args+=" -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_INSTALL_LIBDIR=lib"
    args+=" -DCMAKE_PREFIX_PATH=$PREFIX"
    # libsamplerate 0.2.2 still declares cmake_minimum_required < 3.5
    args+=" -DCMAKE_POLICY_VERSION_MINIMUM=3.5"
    args+=" -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON"
    if [ -n "$_toolchain" ]; then
        args+=" -DCMAKE_TOOLCHAIN_FILE=$_toolchain"
    fi
    if [ "$BUILD_OS" == "macos" ]; then
        args+=" -DCMAKE_OSX_ARCHITECTURES=$_macos_arch"
        args+=" -DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET"
    fi
    echo "$args"
}
