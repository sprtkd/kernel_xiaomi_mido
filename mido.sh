#!/bin/bash
#
# Copyright (C) 2021 Sleepy kernel project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Setup colour for the script
yellow='\033[0;33m'
white='\033[0m'
red='\033[0;31m'
green='\e[0;32m'

# Deleting out "kernel complied" and zip "anykernel" from an old compilation
echo -e "$green << cleanup >> \n $white"

rm -rf out
rm -rf zip
rm -rf error.log

echo -e "$green << setup dirs >> \n $white"

# With that setup , the script will set dirs and few important thinks

MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$MY_DIR" ]]; then MY_DIR="$PWD"; fi

# Now u can chose which things need to be modified
#
# DEVICE = your device codename
# KERNEL_NAME = the name of ur kranul
#
# DEFCONFIG = defconfig that will be used to compile the kernel
#
# AnyKernel = the url of your modified anykernel script
# AnyKernelbranch = the branch of your modified anykernel script
#
# HOSST = build host
# USEER = build user
#
# TOOLCHAIN = the toolchain u want to use "gcc/clang"

DEVICE="Redmi note 4"
CODENAME="mido"
KERNEL_NAME="SleepyKernel"

# Kernel build release tag
# KRNL_REL_TAG=""

DEFCONFIG="mido_defconfig"

AnyKernel="https://github.com/shashank1439/anykernel"
AnyKernelbranch="mido"

HOSST="sleeping-bag"
USEER="shashank"

TOOLCHAIN="clang"

post_build() {
        #Post MD5Checksum alongwith for easeness
        MD5CHECK=$(md5sum "$1" | cut -d' ' -f1)

        curl --progress-bar -X POST "https://filebin.net/" -H "accept: */*" -H "bin: ydvxxly37y3hb6md" -H "filename: $ZIP" -H "Content-Type: application/octet-stream" -d @"$1"
        echo "build finished in $(($Diff / 60)) minutes and $(($Diff % 60)) seconds | <b>MD5 Checksum : </b><code>$MD5CHECK</code>"
}


# Now let's clone gcc/clang on HOME dir
# And after that , the script start the compilation of the kernel it self
# For regen the defconfig . use the regen.sh script

if [ "$TOOLCHAIN" == gcc ]; then
	if [ ! -d "$HOME/gcc64" ] && [ ! -d "$HOME/gcc32" ]
	then
		echo -e "$green << cloning gcc from arter >> \n $white"
		git clone --depth=1 https://github.com/mvaisakh/gcc-arm64 "$HOME"/gcc64
		git clone --depth=1 https://github.com/mvaisakh/gcc-arm "$HOME"/gcc32
	fi
	export PATH="$HOME/gcc64/bin:$HOME/gcc32/bin:$PATH"
	export STRIP="$HOME/gcc64/aarch64-elf/bin/strip"
	export KBUILD_COMPILER_STRING=$("$HOME"/gcc64/bin/aarch64-elf-gcc --version | head -n 1)
elif [ "$TOOLCHAIN" == clang ]; then
	if [ ! -d "$HOME/proton_clang" ]
	then
		echo -e "$green << cloning proton clang >> \n $white"
		git clone --depth=1 https://github.com/kdrag0n/proton-clang.git "$HOME"/proton_clang
	fi
	export PATH="$HOME/proton_clang/bin:$PATH"
	export STRIP="$HOME/proton_clang/aarch64-linux-gnu/bin/strip"
	export KBUILD_COMPILER_STRING=$("$HOME"/proton_clang/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')
fi

# Setup build process

build_kernel() {
Start=$(date +"%s")

if [ "$TOOLCHAIN" == clang  ]; then
	echo clang
	make -j$(nproc --all) O=out \
                              ARCH=arm64 \
                              AR=llvm-ar \
                              NM=llvm-nm \
                              OBJCOPY=llvm-objcopy \
                              OBJDUMP=llvm-objdump \
                              STRIP=llvm-strip \
                              CC=clang \
                              CROSS_COMPILE=aarch64-linux-gnu- \
                              CROSS_COMPILE_ARM32=arm-linux-gnueabi-  2>&1 | tee error.log
elif [ "$TOOLCHAIN" == gcc  ]; then
	echo gcc
	make -j$(nproc --all) O=out \
			      ARCH=arm64 \
			      CROSS_COMPILE=aarch64-elf- \
			      CROSS_COMPILE_ARM32=arm-eabi- 2>&1 | tee error.log
fi

End=$(date +"%s")
Diff=$(($End - $Start))
}

export IMG="$MY_DIR"/out/arch/arm64/boot/Image.gz

# Let's start

echo -e "$green << doing pre-compilation process >> \n $white"
export ARCH=arm64
export SUBARCH=arm64
export HEADER_ARCH=arm64

export KBUILD_BUILD_HOST="$HOSST"
export KBUILD_BUILD_USER="$USEER"

mkdir -p out

make O=out clean && make O=out mrproper
make "$DEFCONFIG" O=out

echo -e "$yellow << compiling the kernel >> \n $white"

build_kernel || error=true

DATE=$(date +"%Y%m%d-%H%M%S")
KERVER=$(make kernelversion)

        if [ -f "$IMG" ]; then
                echo -e "$green << Build completed in $(($Diff / 60)) minutes and $(($Diff % 60)) seconds >> \n $white"
        else
                echo -e "$red << Failed to compile the kernel , Check up to find the error >>$white"
                rm -rf out
                rm -rf testing.log
                rm -rf error.log
                exit 1
        fi

        if [ -f "$IMG" ]; then
                echo -e "$green << cloning AnyKernel from your repo >> \n $white"
                git clone "$AnyKernel" --single-branch -b "$AnyKernelbranch" zip
                echo -e "$yellow << making kernel zip >> \n $white"
                cp -r "$IMG" zip/
                cd zip
                mv Image.gz zImage
                export ZIP="$KERNEL_NAME"-"$CODENAME"-"$DATE"
                zip -r9 "$ZIP" * -x .git README.md LICENSE *placeholder
                curl -sLo zipsigner-3.0.jar https://raw.githubusercontent.com/shashank1439/anykernel/zipper/zipsigner-3.0.jar
                java -jar zipsigner-3.0.jar "$ZIP".zip "$ZIP"-signed.zip
		MD5CHECK=$(md5sum "$ZIP"-signed.zip | cut -d' ' -f1)
		echo -e "$green << MD5 + $MD5CHECK >> \n $white"
		
		mv "$ZIP"-signed.zip kernel.zip
                cd ..
                rm -rf error.log
                rm -rf out
                rm -rf testing.log
                exit
        fi

