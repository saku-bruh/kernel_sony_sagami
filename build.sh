#!/bin/bash
#
# Compile script for QuicksilveR kernel
# Copyright (C) 2024 Adithya R.

SECONDS=0 # start builtin bash timer

CLANG_DIR="$HOME/tc/clang-r547379"

# Setup getopt.
DO_CLEAN=false
REGEN_DEFCONFIG=false
TARGET=

while [ "${#}" -gt 0 ]; do
    case "${1}" in
        -c | --clean )
                DO_CLEAN=true
                ;;
        -r | --regen )
                REGEN_DEFCONFIG=true
                ;;
        * )
                TARGET="${1}"
                ;;
    esac
    shift
done

if [ -z "$TARGET" ]; then
    echo "Target (device) not specified!"
    exit 1
fi

AK3_DIR="$HOME_DIR/AnyKernel3"
ZIPNAME="QuicksilveR-$TARGET-$(date '+%Y%m%d-%H%M').zip"
if test -z "$(git rev-parse --show-cdup 2>/dev/null)" &&
   head=$(git rev-parse --verify HEAD 2>/dev/null); then
        ZIPNAME="${ZIPNAME::-4}-$(echo $head | cut -c1-8).zip"
fi

DEFCONFIG="sagami_defconfig"

export PATH="$CLANG_DIR/bin:$PATH"

function m() {
    make -j$(nproc --all) O=out ARCH=arm64 CC=clang LLVM=1 LLVM_IAS=1 \
        TARGET_PRODUCT=$TARGET $@ || exit $?
}

# Prep for a clean build, if requested so
$DO_CLEAN && (
    rm -rf out
    echo "Cleaned output directories."
)

# Regenerate defconfig, if requested so
if [ "$REGEN_DEFCONFIG" = 'true' ]; then
    echo -e "Regenerating config...\n"
    m $DEFCONFIG savedefconfig
    cp out/defconfig arch/arm64/configs/$DEFCONFIG
    echo -e "\nSuccessfully regenerated defconfig at $DEFCONFIG"
    exit
fi

echo -e "Generating config...\n"
mkdir -p out
m $DEFCONFIG
m ./scripts/kconfig/merge_config.sh $DEFCONFIG vendor/${TARGET}_QGKI.config

echo -e "\nBuilding kernel...\n"
m 2> >(tee out/error.log >&2)

kernel="out/arch/arm64/boot/Image"
dtb_dir="out/arch/arm64/boot/dts/vendor/qcom"
dtbo_dir="out/arch/arm64/boot/dts/vendor/somc"

if [ -f "$kernel" ] && [ -d "$dtb_dir" ] && [ -d "$dtbo_dir" ]; then
	echo -e "\nKernel compiled succesfully! Zipping up...\n"
	if [ -d "$AK3_DIR" ]; then
		cp -r $AK3_DIR AnyKernel3
		git -C AnyKernel3 checkout sagami &> /dev/null
	elif ! git clone -q https://github.com/BladeRunner-A2C/AnyKernel3 -b sagami --depth=1; then
		echo -e "\nAnyKernel3 repo not found locally and couldn't clone from GitHub! Aborting..."
		exit 1
	fi
	cp $kernel AnyKernel3
	cat $dtb_dir/*.dtb > AnyKernel3/dtb
	python3 scripts/dtc/libfdt/mkdtboimg.py create AnyKernel3/dtbo.img --page_size=4096 $dtbo_dir/*.dtbo
	rm -rf out/arch/arm64/boot
	cd AnyKernel3
	zip -r9 "../$ZIPNAME" * -x .git README.md *placeholder
	cd ..
	rm -rf AnyKernel3
	echo -e "\nCompleted in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s) !"
	echo "Zip: $(realpath $ZIPNAME)"
	curl -F "file=@${ZIPNAME}" https://oshi.at
#	curl -# -F "file=@${ZIPNAME}" https://0x0.st
else
	echo -e "\nCompilation failed!"
	exit 1
fi
