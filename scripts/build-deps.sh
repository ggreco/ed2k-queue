#!/usr/bin/env bash
#
# Builds the static, universal (arm64 + x86_64) dependencies needed by
# ed2k-Queue: OpenSSL (libcrypto) and libssh2 (from the git submodule).
#
# Output:
#   build/deps/lib/libcrypto.a
#   build/deps/lib/libssh2.a
#   build/deps/include/...
#
# Usage: scripts/build-deps.sh            (incremental, skips what exists)
#        CLEAN=1 scripts/build-deps.sh    (rebuild everything)
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPS="$ROOT/build/deps"
WORK="$ROOT/build/deps-work"

MIN_MACOS="${MIN_MACOS:-15.0}"
ARCHS=(${ARCHS:-arm64 x86_64})
OPENSSL_VERSION="${OPENSSL_VERSION:-3.5.9}" # LTS branch
OPENSSL_URL="https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz"
JOBS="$(sysctl -n hw.ncpu)"

export MACOSX_DEPLOYMENT_TARGET="$MIN_MACOS"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
export SDKROOT

if [[ "${CLEAN:-0}" == "1" ]]; then
    rm -rf "$DEPS" "$WORK"
fi
mkdir -p "$DEPS/lib" "$DEPS/include" "$WORK"

command -v cmake >/dev/null || { echo "cmake is required (brew install cmake)"; exit 1; }

# ---------------------------------------------------------------- OpenSSL
build_openssl() {
    local tarball="$WORK/openssl-${OPENSSL_VERSION}.tar.gz"
    [[ -f "$tarball" ]] || curl -fL -o "$tarball" "$OPENSSL_URL"

    local libs=()
    for arch in "${ARCHS[@]}"; do
        local src="$WORK/openssl-$arch"
        local prefix="$WORK/openssl-install-$arch"
        if [[ ! -f "$prefix/lib/libcrypto.a" ]]; then
            rm -rf "$src" && mkdir -p "$src"
            tar -xzf "$tarball" -C "$src" --strip-components=1
            local target
            case "$arch" in
                arm64) target=darwin64-arm64-cc ;;
                x86_64) target=darwin64-x86_64-cc ;;
                *) echo "Unsupported arch $arch"; exit 1 ;;
            esac
            (
                cd "$src"
                ./Configure "$target" no-shared no-tests no-docs no-apps no-module \
                    --prefix="$prefix" --libdir=lib \
                    -mmacosx-version-min="$MIN_MACOS"
                make -j"$JOBS" build_libs
                make install_dev
            )
        fi
        libs+=("$prefix/lib/libcrypto.a")
    done

    lipo -create "${libs[@]}" -output "$DEPS/lib/libcrypto.a"
    rm -rf "$DEPS/include/openssl"
    cp -R "$WORK/openssl-install-${ARCHS[0]}/include/openssl" "$DEPS/include/"
}

# ---------------------------------------------------------------- libssh2
build_libssh2() {
    local archs_joined
    archs_joined="$(IFS=';'; echo "${ARCHS[*]}")"
    local bdir="$WORK/libssh2-build"
    rm -rf "$bdir"

    # OpenSSL headers are identical across archs (no arch specific
    # configuration.h differences that matter to libssh2).
    cmake -S "$ROOT/libssh2" -B "$bdir" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES="$archs_joined" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_MACOS" \
        -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_STATIC_LIBS=ON \
        -DBUILD_EXAMPLES=OFF \
        -DBUILD_TESTING=OFF \
        -DCRYPTO_BACKEND=OpenSSL \
        -DENABLE_ZLIB_COMPRESSION=OFF \
        -DOPENSSL_USE_STATIC_LIBS=ON \
        -DOPENSSL_ROOT_DIR="$DEPS" \
        -DOPENSSL_INCLUDE_DIR="$DEPS/include" \
        -DOPENSSL_CRYPTO_LIBRARY="$DEPS/lib/libcrypto.a" \
        -DOPENSSL_SSL_LIBRARY="$DEPS/lib/libcrypto.a"
    cmake --build "$bdir" --target libssh2_static -j"$JOBS"

    cp "$bdir/src/libssh2.a" "$DEPS/lib/libssh2.a"
    cp "$ROOT/libssh2/include/"*.h "$DEPS/include/"
}

if [[ ! -f "$ROOT/libssh2/CMakeLists.txt" ]]; then
    git -C "$ROOT" submodule update --init libssh2
fi

[[ -f "$DEPS/lib/libcrypto.a" ]] || build_openssl
build_libssh2

echo
echo "Dependencies ready in $DEPS:"
lipo -info "$DEPS/lib/libcrypto.a" "$DEPS/lib/libssh2.a"
