#!/usr/bin/env bash
set -euo pipefail
app_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
repo_dir=$(cd "$app_dir/../.." && pwd)
abi=${CARDWEAVE_ABI:-x86_64}
mode=${CARDWEAVE_BUILD_MODE:-debug}
case "$mode" in
  debug) cargo_args=(); rust_profile=debug ;;
  release) cargo_args=(--release); rust_profile=release ;;
  *) echo 'Set CARDWEAVE_BUILD_MODE to debug or release' >&2; exit 2 ;;
esac
export CARDWEAVE_ABI="$abi"
for arg in "$@"; do
  case "$arg" in
    --debug|--profile|--release|--target-platform|--target-platform=*|--split-per-abi)
      echo 'Select mode and ABI with CARDWEAVE_BUILD_MODE and CARDWEAVE_ABI; this script builds one ABI per APK' >&2
      exit 2 ;;
  esac
done
case "$abi" in
  x86_64) rust_target=x86_64-linux-android; ndk_target=x86_64-linux-android; flutter_target=android-x64 ;;
  arm64-v8a) rust_target=aarch64-linux-android; ndk_target=aarch64-linux-android; flutter_target=android-arm64 ;;
  *) echo 'Set CARDWEAVE_ABI to x86_64 or arm64-v8a' >&2; exit 2 ;;
esac
: "${ANDROID_HOME:?Set ANDROID_HOME to Android SDK}"
ndk=${ANDROID_NDK_HOME:-$ANDROID_HOME/ndk/28.2.13676358}
host_tag=${ANDROID_NDK_HOST_TAG:-linux-x86_64}
llvm="$ndk/toolchains/llvm/prebuilt/$host_tag"
target_env=${rust_target//-/_}
linker_env=$(printf '%s' "$target_env" | tr '[:lower:]' '[:upper:]')
export "CC_$target_env=$llvm/bin/${ndk_target}24-clang"
export "AR_$target_env=$llvm/bin/llvm-ar"
export "CARGO_TARGET_${linker_env}_LINKER=$llvm/bin/${ndk_target}24-clang"
export BINDGEN_EXTRA_CLANG_ARGS="--target=${ndk_target}24 --sysroot=$llvm/sysroot ${CARDWEAVE_BINDGEN_EXTRA_ARGS:-}"
cargo build --locked --manifest-path "$app_dir/rust/Cargo.toml" --target "$rust_target" "${cargo_args[@]}"
mkdir -p "$app_dir/android/app/src/main/jniLibs/$abi"
cp "$app_dir/rust/target/$rust_target/$rust_profile/libcard_weave_mobile.so" "$app_dir/android/app/src/main/jniLibs/$abi/"
cd "$app_dir"
flutter build apk "--$mode" --target-platform "$flutter_target" -t "${CARDWEAVE_ENTRYPOINT:-lib/main.dart}" "$@"
