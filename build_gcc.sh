#!/usr/bin/env bash
# Builds the firmware without ModusToolbox, with the same sources, flags and
# library versions as the ModusToolbox 3.3 "Debug" build (recipe-make-cat3,
# GCC_ARM): build/gcc/osf_860c.hex (+ .elf, .map).
#
#   GCC=/path/to/arm-gnu-toolchain-11.3.rel1/bin  MTB_SHARED=/path/to/mtb_shared  ./build_gcc.sh
#
# MTB_SHARED must contain (git clone -b <tag> https://github.com/Infineon/<repo>):
#   mtb-xmclib-cat3 (release-v4.4.0), cmsis (release-v5.8.0),
#   core-lib (release-v1.4.3), retarget-io-cat3 (release-v1.1.0)
# ModusToolbox 3.3 ships Arm GNU Toolchain 11.3.rel1; use that version.
set -euo pipefail
shopt -s nullglob
cd "$(dirname "$0")"

GCC=${GCC:-}
MTB_SHARED=${MTB_SHARED:?set MTB_SHARED to the directory with the Infineon libraries}
CC=${GCC:+$GCC/}arm-none-eabi-gcc
OBJCOPY=${GCC:+$GCC/}arm-none-eabi-objcopy
SIZE=${GCC:+$GCC/}arm-none-eabi-size

XMCLIB=$MTB_SHARED/mtb-xmclib-cat3
BSP=bsps/TARGET_tsdz8_for_GPIO_TEST
OUT=build/gcc
HASH=$(git rev-parse HEAD 2>/dev/null | cut -c1-8 || true)
HASH=${HASH:-00000000}
if [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    echo "warning: uncommitted changes, OSF_GIT_HASH=$HASH does not describe this build" >&2
fi

COMMON="-mcpu=cortex-m0 --specs=nano.specs -mthumb -ffunction-sections -fdata-sections -ffat-lto-objects -g -Wall -pipe"
DEFS="-DCOMPONENT_CAT3 -DCOMPONENT_CM0 -DCOMPONENT_CM0_0 -DCOMPONENT_Debug -DCOMPONENT_GCC_ARM
 -DCOMPONENT_MW_CMSIS -DCOMPONENT_MW_CORE_LIB -DCOMPONENT_MW_CORE_MAKE -DCOMPONENT_MW_MTB_XMCLIB_CAT3
 -DCOMPONENT_MW_RECIPE_MAKE_CAT3 -DCOMPONENT_MW_RETARGET_IO_CAT3 -DCOMPONENT_SOFTFP -DCOMPONENT_XMC1300
 -DCOMPONENT_XMC13XX -DCOMPONENT_tsdz8_for_GPIO_TEST -DCORE_NAME_CM0_0=1
 -DCY_APPNAME_mtb_example_xmc_gpio_toggle -DCY_SUPPORTS_DEVICE_VALIDATION
 -DCY_TARGET_BOARD=tsdz8_for_GPIO_TEST -DDEBUG=DEBUG -DTARGET_tsdz8_for_GPIO_TEST -DXMC1302_T038x0064
 -DOSF_GIT_HASH=0x${HASH}UL"
INCS="-I. -I$BSP -Ibsps -I$BSP/config/GeneratedSource -I$BSP/config -IProbeScope
 -I$MTB_SHARED/retarget-io-cat3
 -I$MTB_SHARED/cmsis/Core/Include -I$MTB_SHARED/cmsis/Core -I$MTB_SHARED/cmsis
 -I$MTB_SHARED/core-lib/include -I$MTB_SHARED/core-lib
 -I$XMCLIB/CMSIS/Infineon/COMPONENT_XMC1300/Include -I$XMCLIB/CMSIS/Infineon/COMPONENT_XMC1300
 -I$XMCLIB/CMSIS/Infineon -I$XMCLIB/CMSIS -I$XMCLIB -I$XMCLIB/XMCLib/inc -I$XMCLIB/XMCLib"

# Same file set and link order as ModusToolbox: startup file, the application
# (everything not excluded by .cyignore, sorted by path), then the libraries.
SRC_APP=$(printf '%s\n' *.c Doc/*.c ProbeScope/*.c $BSP/cybsp.c $BSP/config/GeneratedSource/*.c | LC_ALL=C sort)
SRC_LIB="$XMCLIB/XMCLib/src/COMPONENT_CM0/TOOLCHAIN_GCC_ARM/xmc_common_gcc.S
 $XMCLIB/CMSIS/Infineon/COMPONENT_XMC1300/Source/system_XMC1300.c $XMCLIB/Newlib/syscalls.c
 $(printf '%s\n' $XMCLIB/XMCLib/src/*.c | LC_ALL=C sort) $MTB_SHARED/retarget-io-cat3/cy_retarget_io.c"

rm -rf $OUT && mkdir -p $OUT/obj
objs=()
n=0
for f in $XMCLIB/CMSIS/Infineon/COMPONENT_XMC1300/Source/TOOLCHAIN_GCC_ARM/startup_XMC1300.S $SRC_APP $SRC_LIB; do
    b=$(basename "$f"); o=$OUT/obj/$((n++))_${b%.*}.o
    case $f in
        *.S) $CC -c $COMMON $DEFS $INCS -o "$o" "$f" ;;
        *) $CC -gdwarf-3 -c $COMMON -Og $DEFS $INCS -o "$o" "$f" ;;
    esac
    objs+=("$o")
done
$CC $COMMON -nostartfiles -Wl,--gc-sections -T $BSP/TOOLCHAIN_GCC_ARM/linker.ld \
    -Wl,-Map,$OUT/osf_860c.map -o $OUT/osf_860c.elf -Wl,--start-group "${objs[@]}" -Wl,--end-group
$OBJCOPY -O ihex $OUT/osf_860c.elf $OUT/osf_860c.hex
$SIZE $OUT/osf_860c.elf
echo "built $OUT/osf_860c.hex (OSF_GIT_HASH=$HASH)"
