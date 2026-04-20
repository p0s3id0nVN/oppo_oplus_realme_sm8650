#!/bin/bash
set -e

# ===== Lấy thư mục chứa tập lệnh =====
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# ===== Thiết lập các tham số tùy chỉnh (Đọc từ ENV trong Action) =====
echo "===== OKI SM8650 Universal 6.1.118 A15 - Script Biên Dịch Kernel By Coolapk@cctv18 (Modified) ====="
echo ">>> Đang áp dụng cấu hình từ GitHub Actions..."

MANIFEST=${MANIFEST:-oppo+oplus+realme}
CUSTOM_SUFFIX=${CUSTOM_SUFFIX:-android14-11-o-p0s3id0n}
APPLY_SUSFS=${APPLY_SUSFS:-y}
USE_PATCH_LINUX=${USE_PATCH_LINUX:-n}
KSU_BRANCH=${KSU_BRANCH:-r}
APPLY_LZ4=${APPLY_LZ4:-y}
APPLY_LZ4KD=${APPLY_LZ4KD:-n}
APPLY_DS=${APPLY_DS:-n}

# ===== Định nghĩa cấu trúc thư mục =====
WORKDIR=$(pwd)
echo "Thư mục làm việc: $WORKDIR"

export PATH="$WORKDIR/clang20/bin:$WORKDIR/build-tools/bin:$PATH"

# ===== Thiết lập Ccache =====
export CCACHE_DIR="$HOME/.ccache"
export CCACHE_MAXSIZE="3G"
ccache -M 3G
ccache -o compression=true
export PATH="/usr/lib/ccache:$PATH"

echo ">>> Bắt đầu xử lý cho Manifest: $MANIFEST"

cd "$WORKDIR/workspace/common"

# Xóa hậu tố -dirty
echo ">>> Đang dọn dẹp hậu tố -dirty..."
for f in scripts/setlocalversion; do
  sed -i 's/ -dirty//g' "$f"
  sed -i '$i res=$(echo "$res" | sed '\''s/-dirty//g'\'')' "$f"
done
echo ">>> Đã thêm hậu tố tùy chỉnh: -$CUSTOM_SUFFIX"
for f in scripts/setlocalversion; do
  sed -i "\$s|echo \"\\\$res\"|echo \"-${CUSTOM_SUFFIX}\"|" "$f"
done

# ================= KSU / SUSFS / LZ4 Patching =================

case "$KSU_BRANCH" in
  r|R)
    echo ">>> Đang tích hợp ReSukiSU..."
    curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/refs/heads/main/kernel/setup.sh" | bash -s main
    ;;
  y|Y)
    echo ">>> Đang tích hợp SukiSU Ultra..."
    curl -LSs "https://raw.githubusercontent.com/ShirkNeko/SukiSU-Ultra/refs/heads/main/kernel/setup.sh" | bash -s builtin
    ;;
  n|N)
    echo ">>> Đang tích hợp KernelSU-Next..."
    curl -LSs "https://raw.githubusercontent.com/pershoot/KernelSU-Next/refs/heads/dev-susfs/kernel/setup.sh" | bash -s dev-susfs
    ;;
  k|K)
    echo ">>> Đang tích hợp KernelSU gốc..."
    curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/refs/heads/main/kernel/setup.sh" | bash -s main
    ;;
  l|L)
    echo ">>> Bỏ qua tích hợp KernelSU (Chế độ LKM)."
    ;;
  *)
    echo "Lựa chọn nhánh KSU không hợp lệ ($KSU_BRANCH). Vui lòng kiểm tra lại."
    exit 1
    ;;
esac

if [[ "$APPLY_SUSFS" == "y" || "$APPLY_SUSFS" == "Y" ]]; then
  echo ">>> Đang áp dụng bản vá SUSFS..."
  cd "$WORKDIR/workspace"
  git clone --depth=1 https://gitlab.com/simonpunk/susfs4ksu.git -b gki-android14-6.1
  
  cd "$WORKDIR/workspace/common"
  cp ../susfs4ksu/kernel_patches/50_add_susfs_in_gki-android14-6.1.patch ./
  cp ../susfs4ksu/kernel_patches/fs/* ./fs/
  cp ../susfs4ksu/kernel_patches/include/linux/* ./include/linux/
  patch -p1 < 50_add_susfs_in_gki-android14-6.1.patch || true
  
  if [[ "$KSU_BRANCH" == "k" || "$KSU_BRANCH" == "K" ]]; then
    echo ">>> Đang áp dụng bản vá SUSFS cho KSU gốc..."
    cp ../susfs4ksu/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch ./KernelSU/
    cd ./KernelSU
    patch -p1 < 10_enable_susfs_for_ksu.patch || true
    cd ..
  fi
fi

if [[ "$APPLY_LZ4" == "y" || "$APPLY_LZ4" == "Y" ]]; then
  echo ">>> Đang áp dụng bản vá tối ưu hóa LZ4 và ZSTD..."
  cd "$WORKDIR/workspace/common"
  wget -q https://github.com/cctv18/oppo_oplus_realme_sm8650/raw/refs/heads/main/zram_patch/001-lz4.patch
  wget -q https://github.com/cctv18/oppo_oplus_realme_sm8650/raw/refs/heads/main/zram_patch/lz4armv8.S
  wget -q https://github.com/cctv18/oppo_oplus_realme_sm8650/raw/refs/heads/main/zram_patch/002-zstd.patch
  cp lz4armv8.S ./lib/
  git apply -p1 < 001-lz4.patch || true
  patch -p1 < 002-zstd.patch || true
fi

if [[ "$APPLY_LZ4KD" == "y" || "$APPLY_LZ4KD" == "Y" ]]; then
  echo ">>> Đang áp dụng bản vá LZ4KD..."
  cd "$WORKDIR/workspace"
  git clone --depth=1 https://github.com/ShirkNeko/SukiSU_patch.git
  
  cd "$WORKDIR/workspace/common"
  cp -r ../SukiSU_patch/other/zram/lz4k/include/linux/* ./include/linux/
  cp -r ../SukiSU_patch/other/zram/lz4k/lib/* ./lib/
  cp -r ../SukiSU_patch/other/zram/lz4k/crypto/* ./crypto/
  cp ../SukiSU_patch/other/zram/zram_patch/6.1/lz4kd.patch ./
  patch -p1 -F 3 < lz4kd.patch || true
fi

# ================= Cấu hình (Defconfig) =================
cd "$WORKDIR/workspace/common"
DEFCONFIG="arch/arm64/configs/gki_defconfig"

echo ">>> Đang sửa đổi file cấu hình kernel (gki_defconfig)..."
# KSU cơ bản
if [[ "$KSU_BRANCH" != "l" && "$KSU_BRANCH" != "L" ]]; then
  echo "CONFIG_KSU=y" >> $DEFCONFIG
  if [[ "$KSU_BRANCH" == "r" || "$KSU_BRANCH" == "R" || "$KSU_BRANCH" == "y" || "$KSU_BRANCH" == "Y" ]]; then
    echo 'CONFIG_KSU_FULL_NAME_FORMAT="%TAG_NAME%-%COMMIT_SHA%@cctv18"' >> $DEFCONFIG
  fi
fi

# KPM
if [[ "$USE_PATCH_LINUX" == "b" || "$USE_PATCH_LINUX" == "B" ]]; then
  echo "CONFIG_KPM=y" >> $DEFCONFIG
fi

# SUSFS
if [[ "$APPLY_SUSFS" == "y" || "$APPLY_SUSFS" == "Y" ]]; then
  echo "CONFIG_KSU_SUSFS=y" >> $DEFCONFIG
  echo "CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y" >> $DEFCONFIG
  echo "CONFIG_KSU_SUSFS_SUS_PATH=y" >> $DEFCONFIG
  echo "CONFIG_KSU_SUSFS_SUS_MOUNT=y" >> $DEFCONFIG
  echo "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y" >> $DEFCONFIG
  echo "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y" >> $DEFCONFIG
  echo "CONFIG_KSU_SUSFS_SUS_KSTAT=y" >> $DEFCONFIG
  echo "CONFIG_KSU_SUSFS_TRY_UMOUNT=y" >> $DEFCONFIG
  echo "CONFIG_KSU_SUSFS_SPOOF_UNAME=y" >> $DEFCONFIG
  echo "CONFIG_KSU_SUSFS_ENABLE_LOG=y" >> $DEFCONFIG
  echo "CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y" >> $DEFCONFIG
  echo "CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y" >> $DEFCONFIG
  echo "CONFIG_KSU_SUSFS_OPEN_REDIRECT=y" >> $DEFCONFIG
  echo "CONFIG_KSU_SUSFS_SUS_MAP=y" >> $DEFCONFIG
fi

# LZ4KD
if [[ "$APPLY_LZ4KD" == "y" || "$APPLY_LZ4KD" == "Y" ]]; then
  echo "CONFIG_ZSMALLOC=y" >> $DEFCONFIG
  echo "CONFIG_CRYPTO_LZ4HC=y" >> $DEFCONFIG
  echo "CONFIG_CRYPTO_LZ4K=y" >> $DEFCONFIG
  echo "CONFIG_CRYPTO_LZ4KD=y" >> $DEFCONFIG
  echo "CONFIG_CRYPTO_842=y" >> $DEFCONFIG
fi

# Droidspaces
if [[ "$APPLY_DS" == "y" || "$APPLY_DS" == "Y" ]]; then
  echo "CONFIG_SYSVIPC=y" >> $DEFCONFIG
  echo "CONFIG_DEVTMPFS=y" >> $DEFCONFIG
  echo "CONFIG_PID_NS=y" >> $DEFCONFIG
  echo "CONFIG_POSIX_MQUEUE=y" >> $DEFCONFIG
  echo "CONFIG_NETFILTER_XT_TARGET_REJECT=y" >> $DEFCONFIG
  echo "CONFIG_NETFILTER_XT_TARGET_LOG=y" >> $DEFCONFIG
  echo "CONFIG_NETFILTER_XT_MATCH_RECENT=y" >> $DEFCONFIG
fi

# Tối ưu hóa hiệu năng
echo "CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE=y" >> $DEFCONFIG

sed -i 's/check_defconfig//' ./build.config.gki

# ================= Biên dịch Kernel =================
echo ">>> Đang tạo Defconfig (gki_defconfig)..."
make -j$(nproc --all) LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC="ccache clang" LD="ld.lld" HOSTLD=ld.lld O=out KCFLAGS+=-O2 KCFLAGS+=-Wno-error gki_defconfig

echo ">>> Bắt đầu biên dịch kernel (Image)..."
make -j$(nproc --all) LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC="ccache clang" LD="ld.lld" HOSTLD=ld.lld O=out KCFLAGS+=-O2 KCFLAGS+=-Wno-error Image

# ================= Áp dụng KPM sau khi biên dịch =================
if [[ "$USE_PATCH_LINUX" == "b" || "$USE_PATCH_LINUX" == "B" ]]; then
  echo ">>> Đang áp dụng KPM (Builtin)..."
  cd "$WORKDIR/workspace/common/out/arch/arm64/boot/"
  wget -q https://github.com/SukiSU-Ultra/SukiSU_KernelPatch_patch/releases/latest/download/patch_linux
  chmod +x patch_linux
  ./patch_linux
  mv oImage Image
elif [[ "$USE_PATCH_LINUX" == "k" || "$USE_PATCH_LINUX" == "K" ]]; then
  echo ">>> Đang áp dụng KPM (KernelPatch Next)..."
  cd "$WORKDIR/workspace/common/out/arch/arm64/boot/"
  wget -q https://github.com/KernelSU-Next/KPatch-Next/releases/latest/download/kptools-linux
  wget -q https://github.com/KernelSU-Next/KPatch-Next/releases/latest/download/kpimg-linux
  chmod +x kptools-linux
  ./kptools-linux -p -i ./Image -k ./kpimg-linux -o ./oImage
  mv oImage Image
fi

# ================= Đóng gói AnyKernel3 =================
echo ">>> Đang sao chép Image vào AnyKernel3..."
cd "$WORKDIR/workspace"
git clone -b gki-2.0 --depth=1 https://github.com/p0s3id0nVN/AnyKernel30 AnyKernel3
cp "$WORKDIR/workspace/common/out/arch/arm64/boot/Image" ./AnyKernel3/

echo ">>> Đang đóng gói file ZIP AnyKernel3..."
cd "$WORKDIR/workspace/AnyKernel3"

if [[ "$APPLY_LZ4KD" == "y" || "$APPLY_LZ4KD" == "Y" ]]; then
  wget -q https://raw.githubusercontent.com/cctv18/oppo_oplus_realme_sm8650/refs/heads/main/zram.zip
fi

if [[ "$USE_PATCH_LINUX" == "k" || "$USE_PATCH_LINUX" == "K" ]]; then
  wget -q https://github.com/cctv18/KPatch-Next/releases/latest/download/kpn.zip
fi

# Tạo tên file ZIP
ZIP_NAME="AK3_${MANIFEST}"
if [[ "$APPLY_SUSFS" == "y" || "$APPLY_SUSFS" == "Y" ]]; then ZIP_NAME="${ZIP_NAME}-susfs"; fi
if [[ "$APPLY_LZ4KD" == "y" || "$APPLY_LZ4KD" == "Y" ]]; then ZIP_NAME="${ZIP_NAME}-lz4kd"; fi
if [[ "$APPLY_LZ4" == "y" || "$APPLY_LZ4" == "Y" ]]; then ZIP_NAME="${ZIP_NAME}-lz4-zstd"; fi
if [[ "$USE_PATCH_LINUX" == "b" || "$USE_PATCH_LINUX" == "B" ]]; then ZIP_NAME="${ZIP_NAME}-builtin_kpm"; fi
if [[ "$USE_PATCH_LINUX" == "k" || "$USE_PATCH_LINUX" == "K" ]]; then ZIP_NAME="${ZIP_NAME}-kpn"; fi
if [[ "$APPLY_DS" == "y" || "$APPLY_DS" == "Y" ]]; then ZIP_NAME="${ZIP_NAME}-ds"; fi

case "$KSU_BRANCH" in
  r|R) ZIP_NAME="${ZIP_NAME}-ReSukiSU" ;;
  y|Y) ZIP_NAME="${ZIP_NAME}-SukiSU" ;;
  n|N) ZIP_NAME="${ZIP_NAME}-KSUN" ;;
  k|K) ZIP_NAME="${ZIP_NAME}-KSU" ;;
  l|L) ZIP_NAME="${ZIP_NAME}-LKM" ;;
esac

ZIP_NAME="${ZIP_NAME}.zip"

# Nén thư mục AnyKernel3
zip -r9 "../$ZIP_NAME" ./* -x "README.md"
cd ..

echo "✅ Biên dịch và đóng gói hoàn tất! File ZIP: $ZIP_NAME"