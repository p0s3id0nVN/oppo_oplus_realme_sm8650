#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"; cd "$SCRIPT_DIR"

echo "=============================================================================="
echo "🚀 Script Build Kernel OKI 6.1.141 A15 cho SM8650 (OPPO/OnePlus/Realme) 🚀"
echo "=============================================================================="
read -p "🏷️ Nhập hậu tố Kernel (Mặc định: android14-11-o-gca13bffobf09): " CUSTOM_SUFFIX
read -p "👻 Bật SUSFS? (y/n, Mặc định: y): " APPLY_SUSFS
read -p "📦 Bật KPM? (b: KPM Built-in, k: KSU Next, n: Tắt, Mặc định: n): " USE_PATCH_LINUX
read -p "🧬 Chọn nhánh KSU (r: ReSukiSU, y: SukiSU, n: KSU Next, k: KSU, l: Không có, Mặc định: r): " KSU_BRANCH
read -p "🗜️ Áp dụng patch LZ4 1.10.0 & ZSTD 1.5.7? (y/n, Mặc định: y): " APPLY_LZ4
read -p "🗜️ Áp dụng patch LZ4KD? (y/n, Mặc định: n): " APPLY_LZ4KD
read -p "🌐 Bật cấu hình tối ưu mạng IPSet? (y/n, Mặc định: y): " APPLY_BETTERNET
read -p "🚀 Bật thuật toán mạng BBR? (y: Bật, d: Mặc định, n: Tắt, Mặc định: n): " APPLY_BBR
read -p "💾 Bật Samsung SSG IO? (y/n, Mặc định: y): " APPLY_SSG
read -p "❄️ Bật Re-Kernel (Freezer)? (y/n, Mặc định: n): " APPLY_REKERNEL
read -p "🛡️ Bật bảo vệ Baseband (BBG)? (y/n, Mặc định: y): " APPLY_BBG

CUSTOM_SUFFIX=${CUSTOM_SUFFIX:-android14-11-o-gca13bffobf09}
KSU_BRANCH=${KSU_BRANCH:-r}; APPLY_SUSFS=${APPLY_SUSFS:-y}; USE_PATCH_LINUX=${USE_PATCH_LINUX:-n}
APPLY_LZ4=${APPLY_LZ4:-y}; APPLY_LZ4KD=${APPLY_LZ4KD:-n}; APPLY_BETTERNET=${APPLY_BETTERNET:-y}
APPLY_BBR=${APPLY_BBR:-n}; APPLY_SSG=${APPLY_SSG:-y}; APPLY_REKERNEL=${APPLY_REKERNEL:-n}; APPLY_BBG=${APPLY_BBG:-y}

echo ">>> Đang chuẩn bị môi trường biên dịch..."
SU() { [ "$(id -u)" -eq 0 ] && "$@" || sudo "$@"; }
SU apt-mark hold firefox libc-bin man-db && SU rm -rf /var/lib/man-db/auto-update && SU apt-get update
SU apt-get install --no-install-recommends -y curl bison flex clang binutils dwarves git lld pahole zip perl make gcc python3 python-is-python3 bc libssl-dev libelf-dev cpio xz-utils tar unzip
SU rm -rf ./llvm.sh && wget -q https://apt.llvm.org/llvm.sh && chmod +x llvm.sh && SU ./llvm.sh 20 all

echo ">>> Đang khởi tạo mã nguồn (Branch: 6.1.141)..."
rm -rf kernel_workspace; mkdir kernel_workspace; cd kernel_workspace
git clone --depth=1 https://github.com/cctv18/android_kernel_common_oneplus_sm8650 -b oneplus/sm8650_b_16.0.0_oneplus12_6.1.141 common
rm common/android/abi_gki_protected_exports_* || true
for f in common/scripts/setlocalversion; do sed -i 's/ -dirty//g' "$f"; sed -i '$i res=$(echo "$res" | sed '\''s/-dirty//g'\'')' "$f"; sed -i "\$s|echo \"\\\$res\"|echo \"-${CUSTOM_SUFFIX}\"|" "$f"; done

echo ">>> Đang thiết lập nhánh KernelSU..."
case "$KSU_BRANCH" in
  [yY]) curl -LSs "https://raw.githubusercontent.com/ShirkNeko/SukiSU-Ultra/main/kernel/setup.sh" | bash -s builtin
        COMMIT=$(cd KernelSU && git rev-parse --short=8 HEAD)
        API=$(curl -s "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/builtin/kernel/Kbuild" | grep -m1 "KSU_VERSION_API :=" | awk -F'= ' '{print $2}') || API="3.1.7"
        DEF=$'define get_ksu_version_full\nv\\$1-'"$COMMIT"'@cctv18\nendef\n\nKSU_VERSION_API := '"$API"'\nKSU_VERSION_FULL := v'"$API"'-'"$COMMIT"'@cctv18'
        sed -i '/define get_ksu_version_full/,/endef/d; /KSU_VERSION_API :=/d; /KSU_VERSION_FULL :=/d' KernelSU/kernel/Kbuild
        awk -v def="$DEF" '/REPO_OWNER :=/ {print; print def; i=1; next} 1 END {if(!i) print def}' KernelSU/kernel/Kbuild > tmp && mv tmp KernelSU/kernel/Kbuild ;;
  [rR]) curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash -s main
        echo 'CONFIG_KSU_FULL_NAME_FORMAT="%TAG_NAME%-%COMMIT_SHA%@cctv18"' >> ./common/arch/arm64/configs/gki_defconfig ;;
  [nN]) curl -LSs "https://raw.githubusercontent.com/pershoot/KernelSU-Next/refs/heads/dev-susfs/kernel/setup.sh" | bash -s dev-susfs; rm -rf KernelSU-Next/.git
        VER=$(expr $(curl -sI "https://api.github.com/repos/pershoot/KernelSU-Next/commits?sha=dev&per_page=1" | sed -n 's/.*page=\([0-9]*\)>; rel="last".*/\1/p') "+" 30000)
        TAG=$(curl -sL "https://api.github.com/repos/KernelSU-Next/KernelSU-Next/tags" | grep -o '"name": *"[^"]*"' | head -n 1 | sed 's/"name": "//;s/"//')
        sed -i "s/KSU_VERSION_FALLBACK := 1/KSU_VERSION_FALLBACK := $VER/g; s/KSU_VERSION_TAG_FALLBACK := v0.0.1/KSU_VERSION_TAG_FALLBACK := $TAG/g" KernelSU-Next/kernel/Kbuild
        wget -q https://github.com/cctv18/oppo_oplus_realme_sm8650/raw/refs/heads/main/other_patch/apk_sign.patch && patch -d common/drivers/kernelsu -p2 -N -F 3 < apk_sign.patch || true ;;
  [kK]) curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/refs/heads/main/kernel/setup.sh" | bash -s main
        VER=$(expr $(curl -sI "https://api.github.com/repos/tiann/KernelSU/commits?sha=main&per_page=1" | sed -n 's/.*page=\([0-9]*\)>; rel="last".*/\1/p') "+" 30000)
        sed -i "s/DKSU_VERSION=16/DKSU_VERSION=${VER}/" KernelSU/kernel/Kbuild ;;
esac

echo ">>> Đang áp dụng các bản vá (Patches)..."
[[ "$APPLY_SUSFS" == [yY] ]] && git clone --depth=1 https://github.com/cctv18/susfs4oki.git susfs4ksu -b oki-android14-6.1 && cp susfs4ksu/kernel_patches/50_add_susfs_in_gki-android14-6.1.patch common/ && cp -r susfs4ksu/kernel_patches/fs/* common/fs/ && cp -r susfs4ksu/kernel_patches/include/linux/* common/include/linux/ && wget -qO common/69_hide_stuff.patch https://github.com/cctv18/oppo_oplus_realme_sm8650/raw/refs/heads/main/other_patch/69_hide_stuff.patch && cd common && patch -p1 < 50_add_susfs*.patch && patch -p1 -F 3 < 69_hide_stuff.patch && cd .. && [[ "$KSU_BRANCH" == [kK] ]] && patch -d KernelSU -p1 < susfs4ksu/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch || true
[[ "$APPLY_LZ4" == [yY] ]] && git clone --depth=1 https://github.com/cctv18/oppo_oplus_realme_sm8650.git repo_tmp && cp repo_tmp/zram_patch/001-lz4.patch repo_tmp/zram_patch/002-zstd.patch common/ && cp repo_tmp/zram_patch/lz4armv8.S common/lib/ && cd common && git apply -p1 < 001-lz4.patch && patch -p1 < 002-zstd.patch && cd ..
[[ "$APPLY_LZ4KD" == [yY] ]] && git clone --depth=1 https://github.com/ShirkNeko/SukiSU_patch.git && cp -r SukiSU_patch/other/zram/lz4k/include/linux/* common/include/linux/ && cp -r SukiSU_patch/other/zram/lz4k/lib/* common/lib/ && cp -r SukiSU_patch/other/zram/lz4k/crypto/* common/crypto/ && cp SukiSU_patch/other/zram/zram_patch/6.1/lz4kd.patch common/ && cd common && patch -p1 -F 3 < lz4kd.patch && cd ..

echo ">>> Đang thiết lập cấu hình Defconfig..."
DEF=common/arch/arm64/configs/gki_defconfig
{
  echo "CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE=y"; echo "CONFIG_HEADERS_INSTALL=n"
  echo "CONFIG_TMPFS_XATTR=y"; echo "CONFIG_TMPFS_POSIX_ACL=y"
  [[ "$KSU_BRANCH" != [lL] ]] && echo "CONFIG_KSU=y"
  [[ "$APPLY_SUSFS" == [yY] ]] && cat <<EOF
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_TRY_UMOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
EOF
  [[ "$USE_PATCH_LINUX" == [bB] && "$KSU_BRANCH" == [yYrR] ]] && echo "CONFIG_KPM=y"
  [[ "$APPLY_LZ4KD" == [yY] ]] && echo "CONFIG_ZSMALLOC=y" && echo "CONFIG_CRYPTO_LZ4HC=y" && echo "CONFIG_CRYPTO_LZ4K=y" && echo "CONFIG_CRYPTO_LZ4KD=y" && echo "CONFIG_CRYPTO_842=y"
  if [[ "$APPLY_BETTERNET" == [yY] ]]; then
    cat <<EOF
CONFIG_BPF_STREAM_PARSER=y
CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y
CONFIG_NETFILTER_XT_SET=y
CONFIG_IP_SET=y
CONFIG_IP_SET_MAX=65534
CONFIG_IP_SET_BITMAP_IP=y
CONFIG_IP_SET_BITMAP_IPMAC=y
CONFIG_IP_SET_BITMAP_PORT=y
CONFIG_IP_SET_HASH_IP=y
CONFIG_IP_SET_HASH_IPMARK=y
CONFIG_IP_SET_HASH_IPPORT=y
CONFIG_IP_SET_HASH_IPPORTIP=y
CONFIG_IP_SET_HASH_IPPORTNET=y
CONFIG_IP_SET_HASH_IPMAC=y
CONFIG_IP_SET_HASH_MAC=y
CONFIG_IP_SET_HASH_NETPORTNET=y
CONFIG_IP_SET_HASH_NET=y
CONFIG_IP_SET_HASH_NETNET=y
CONFIG_IP_SET_HASH_NETPORT=y
CONFIG_IP_SET_HASH_NETIFACE=y
CONFIG_IP_SET_LIST_SET=y
CONFIG_IP6_NF_NAT=y
CONFIG_IP6_NF_TARGET_MASQUERADE=y
EOF
    wget -q https://github.com/cctv18/oppo_oplus_realme_sm8650/raw/refs/heads/main/other_patch/config.patch && patch -d common -p1 -F 3 < config.patch || true
  fi
  if [[ "$APPLY_BBR" == [yYdD] ]]; then
    cat <<EOF
CONFIG_TCP_CONG_ADVANCED=y
CONFIG_TCP_CONG_BBR=y
CONFIG_TCP_CONG_CUBIC=y
CONFIG_TCP_CONG_VEGAS=y
CONFIG_TCP_CONG_NV=y
CONFIG_TCP_CONG_WESTWOOD=y
CONFIG_TCP_CONG_HTCP=y
CONFIG_TCP_CONG_BRUTAL=y
EOF
    [[ "$APPLY_BBR" == [dD] ]] && echo "CONFIG_DEFAULT_TCP_CONG=bbr" || echo "CONFIG_DEFAULT_TCP_CONG=cubic"
  fi
  [[ "$APPLY_SSG" == [yY] ]] && echo "CONFIG_MQ_IOSCHED_SSG=y" && echo "CONFIG_MQ_IOSCHED_SSG_CGROUP=y"
  [[ "$APPLY_REKERNEL" == [yY] ]] && echo "CONFIG_REKERNEL=y"
  [[ "$APPLY_BBG" == [yY] ]] && echo "CONFIG_BBG=y"
} >> $DEF

[[ "$APPLY_BBG" == [yY] ]] && curl -sSL https://github.com/cctv18/Baseband-guard/raw/master/setup.sh | bash -s -- common && sed -i '/^config LSM$/,/^help$/{ /^[[:space:]]*default/ { /baseband_guard/! s/selinux/selinux,baseband_guard/ } }' common/security/Kconfig
sed -i 's/check_defconfig//' common/build.config.gki

echo ">>> Bắt đầu tiến trình Compile Kernel..."
cd common
make -j$(nproc --all) LLVM=-20 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnuabeihf- CC=clang LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=out KCFLAGS="-O2 -Wno-error" gki_defconfig all
cd ..

echo ">>> Đang đóng gói Kernel (AnyKernel3)..."
OUT_DIR="$WORKDIR/kernel_workspace/common/out/arch/arm64/boot"
if [[ "$USE_PATCH_LINUX" == [bB] && "$KSU_BRANCH" == [yYrR] ]]; then
  cd "$OUT_DIR"; wget -q https://github.com/SukiSU-Ultra/SukiSU_KernelPatch_patch/releases/latest/download/patch_linux; chmod +x patch_linux; ./patch_linux && mv oImage Image
elif [[ "$USE_PATCH_LINUX" == [kK] ]]; then
  cd "$OUT_DIR"; wget -q https://github.com/KernelSU-Next/KPatch-Next/releases/latest/download/kptools-linux https://github.com/KernelSU-Next/KPatch-Next/releases/latest/download/kpimg-linux; chmod +x kptools-linux; ./kptools-linux -p -i ./Image -k ./kpimg-linux -o ./oImage && mv oImage Image
fi

cd "$WORKDIR/kernel_workspace"; git clone --depth=1 https://github.com/cctv18/AnyKernel3; rm -rf AnyKernel3/.git; cp "$OUT_DIR/Image" ./AnyKernel3/
cd AnyKernel3
[[ "$APPLY_LZ4KD" == [yY] ]] && wget -q https://raw.githubusercontent.com/cctv18/oppo_oplus_realme_sm8650/refs/heads/main/zram.zip
[[ "$USE_PATCH_LINUX" == [kK] ]] && wget -q https://github.com/cctv18/KPatch-Next/releases/latest/download/kpn.zip

ZIP="Anykernel3-${MANIFEST:-oppo+oplus+realme}"
[[ "$APPLY_SUSFS" == [yY] ]] && ZIP="${ZIP}-susfs"
[[ "$APPLY_LZ4KD" == [yY] ]] && ZIP="${ZIP}-lz4kd"
[[ "$APPLY_LZ4" == [yY] ]] && ZIP="${ZIP}-lz4-zstd"
[[ "$USE_PATCH_LINUX" == [bBkK] ]] && ZIP="${ZIP}-kpm"
[[ "$APPLY_BBR" == [yY] ]] && ZIP="${ZIP}-bbr"
[[ "$APPLY_SSG" == [yY] ]] && ZIP="${ZIP}-ssg"
[[ "$APPLY_REKERNEL" == [yY] ]] && ZIP="${ZIP}-rek"
[[ "$APPLY_BBG" == [yY] ]] && ZIP="${ZIP}-bbg"
ZIP="${ZIP}-v$(date +%Y%m%d).zip"

zip -r "../$ZIP" ./*
echo "🎉 HOÀN TẤT! File ZIP của bạn nằm tại: $(realpath "../$ZIP")"