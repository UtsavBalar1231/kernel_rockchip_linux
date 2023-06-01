#!/usr/bin/env bash
# shellcheck disable=SC2199,SC2086
# shellcheck source=/dev/null

#
# SPDX-License-Identifier: MIT
# Copyright (C) 2020-23 Utsav Balar (utsavbalar1231@gmail.com)
# Version: 3.2
#

set -eE

export LC_ALL=C

# Date for boot image
DATE=$(date +"%d.%m.%y")
# Command used for this script
CMD=$(realpath $0)
# Kernel directory path
KERNEL_DIR=$(dirname ${CMD})
# Kernel out directory path
OUT_DIR=${KERNEL_DIR}/out
# Set boot image name
FILENAME="${OUT_DIR}/boot-${DATE}.img"
# Set Kernel Image path
KERNEL_IMAGE="${OUT_DIR}/arch/arm64/boot/Image"
# Set default defconfig
DEFCONFIG="rockchip_linux_defconfig"
# Set default extlinux config
EXTLINUX_CONF=extlinux/vicharak.conf
# read kernel version from Makefile
KERNEL_VERSION=$(grep "VERSION =" "${KERNEL_DIR}"/Makefile | grep -o '[0-9]')

# Prints the string in bold yellow color if the line is a header
# if the line is not a header then it prints the string in bold green color
function print() {
	# check if the line is a header or not
	if [[ $1 == *"---"* ]]; then
		echo -e "\e[1;33m${1}\e[0m"
		return
	fi
	echo -e "\e[1;32m    ${1}\e[0m"
}

# Usage function for this script
function usage() {
	print "--------------------------------------------------------------------------------"
	print "Build script for Vicharak kernel"
	print "Usage: $0 [OPTIONS]"
	print "Options:"
	print "  clean   | -C\t\tClean build files"
	print "  clang   | -c\t\tBuild kernel using clang, default if GCC 14.0"
	print "  perf    | -p\t\tBuild kernel with performance config"
	print "  axon    | -A\t\tBuild kernel for axon"
	print "  vaaman  | -V\t\tBuild kernel for vaaman"
	print "  modules | -m\t\tBuild kernel modules"
	print "  update  | -u\t\tUpdate defconfig with latest changes"
	print "  help    | -h\t\tShow this help"
	print ""
	print "Example: $0 -c -p -A"
	print "Above command will build kernel using clang with performance config for axon"
	print "--------------------------------------------------------------------------------"
}

# Check bootimage size and exit if it is less than 50MB
function check_build() {
	if [ -f "${FILENAME}" ] && [ "$(stat -c%s "${FILENAME}")" -lt 50000000 ]; then
		print "----------------------------------------------------------------"
		print "Build failed!"
		print "----------------------------------------------------------------"
		exit 1
	else
		print "----------------------------------------------------------------"
		print "Build successful!"
		print "----------------------------------------------------------------"
	fi

}

# Pack Image into boot image using extlinux config
# and copy kernel image and dtb file to boot image
function pack_image() {
	if [ -f "${FILENAME}" ]; then
		rm -f "${FILENAME}"
		print "---- Removed previous ${FILENAME} ----"
	fi
	mkfs.vfat -n "boot" -S 512 -C "${FILENAME}" $((60 * 1024))

	if [ -d "${KERNEL_DIR}"/extlinux ]; then
		cp -r "${KERNEL_DIR}"/extlinux/ "${OUT_DIR}"
	else
		print "----------------------------------------------------------------"
		print "extlinux directory not found!"
		print "----------------------------------------------------------------"
		exit 1
	fi

	cd "${OUT_DIR}" || exit

	if [ -f "$(which mmd)" ]; then
		mmd -i "${FILENAME}" ::/extlinux
		mcopy -i "${FILENAME}" -s $EXTLINUX_CONF ::/extlinux/extlinux.conf
		mcopy -i "${FILENAME}" -s "${KERNEL_IMAGE}" ::
		mcopy -i "${FILENAME}" -s "${KERNEL_DIR}"/logo.bmp ::
		mcopy -i "${FILENAME}" -s "${KERNEL_DIR}"/logo_kernel.bmp ::
		mcopy -i "${FILENAME}" -s "${DTB_FILE}" ::/rk-kernel.dtb
	else
		print "----------------------------------------------------------------"
		print "mtools not found!"
		print "----------------------------------------------------------------"
	fi

	check_build
}

# Cleanup previous build files if any
function cleanup() {
	if [ -f "${FILENAME}" ]; then
		print "---- Cleaning up previous boot image ----"
		rm -f "${FILENAME}"
	fi
	if [ -f "${KERNEL_IMAGE}" ]; then
		print "---- Cleaning up previous kernel image ----"
		rm -f "${KERNEL_IMAGE}"
	fi
	if [ -f "${DTB_FILE}" ]; then
		print "---- Cleaning up previous dtb file ----"
		rm -f "${DTB_FILE}"
	fi
	if [ -d "${OUT_DIR}"/extlinux ]; then
		print "---- Cleaning up previous extlinux directory ----"
		rm -rf "${OUT_DIR}"/extlinux
	fi
	if [ -d "${OUT_DIR}"/modules_vicharak ]; then
		print "---- Cleaning up previous modules directory ----"
		rm -rf "${OUT_DIR}"/modules*
	fi
	if [ -d "${OUT_DIR}"/deb ]; then
		print "---- Cleaning up previous modules directory ----"
		rm -rf "${OUT_DIR}"/deb
	fi
}

function use_standalone_clang() {
	print "----------------------------------------------------------------"
	print "Using standalone clang"
	print "----------------------------------------------------------------"

	# check if prebuilt clang is installed
	if [ ! -d "${KERNEL_DIR}"/../clang ]; then
		print "----------------------------------------------------------------"
		print "Downloading clang"
		print "----------------------------------------------------------------"
		git clone \
			https://gitlab.com/ThankYouMario/android_prebuilts_clang-standalone/ \
			-b 12 \
			--depth=1 \
			"${KERNEL_DIR}"/../clang

	fi

	PATH="${KERNEL_DIR}"/../clang/bin:${PATH}
	LD_LIBRARY_PATH="${KERNEL_DIR}"/../clang/lib:$LD_LIBRARY_PATH
	export PATH
	export LD_LIBRARY_PATH
}

# Set environment variables for clang
function build_clang() {
	if [ -z "$(which clang)" ]; then
		use_standalone_clang
	elif [ "${KERNEL_VERSION}" == "4" ]; then
		use_standalone_clang
	else
		LD_LIBRARY_PATH=/usr/lib/llvm-15/lib:$LD_LIBRARY_PATH
		export LD_LIBRARY_PATH
	fi

	print "----------------------------------------------------------------"
	print "KERNEL VERSION: ${KERNEL_VERSION}"
	print "----------------------------------------------------------------"

	if [ "${KERNEL_VERSION}" == "4" ]; then
		print "----------------------------------------------------------------"
		print "PATH: ${PATH}"
		print "----------------------------------------------------------------"
		ARGS="ARCH=arm64 \
			O=${OUT_DIR} \
			CC=clang \
			LD=ld.lld \
			AR=llvm-ar \
			NM=llvm-nm \
			STRIP=llvm-strip \
			OBJCOPY=llvm-objcopy \
			OBJDUMP=llvm-objdump \
			CROSS_COMPILE=aarch64-linux-gnu- \
			CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
			CLANG_TRIPLE=aarch64-linux-gnu- \
			-j$(nproc --all)"
	else
		ARGS="ARCH=arm64 \
			O=${OUT_DIR} \
			LLVM=1 \
			CROSS_COMPILE=aarch64-linux-gnu- \
			CROSS_COMPILE_COMPAT=arm-linux-gnueabi- \
			-j$(nproc --all)"
	fi

	export ARGS
}

# Set environment variables for gcc
function build_gcc() {
	if [ ! -d "${KERNEL_DIR}"/../gcc-arm64 ]; then
		print "----------------------------------------------------------------"
		print "Downloading gcc-arm64"
		print "----------------------------------------------------------------"
		git clone \
			https://github.com/mvaisakh/gcc-arm64 \
			--depth=1 \
			"${KERNEL_DIR}"/../gcc-arm64
	fi
	if [ ! -d "${KERNEL_DIR}"/../gcc-arm ]; then
		print "----------------------------------------------------------------"
		print "Downloading gcc-arm"
		print "----------------------------------------------------------------"
		git clone \
			https://github.com/mvaisakh/gcc-arm \
			--depth=1 \
			"${KERNEL_DIR}"/../gcc-arm

	fi

	PATH=${KERNEL_DIR}/../gcc-arm64/bin:${KERNEL_DIR}/../gcc-arm/bin:${PATH}
	ARGS="ARCH=arm64 \
		O=${OUT_DIR} \
		CROSS_COMPILE=aarch64-elf- \
		CROSS_COMPILE_COMPAT=arm-eabi- \
		-j$(nproc --all)"

	export ARGS
}

# Make defconfig with optional argument
# If argument is passed, merge it with defconfig
function build_config() {
	# check if arg > 0
	if [ $# -gt 0 ]; then
		make ${ARGS} ${DEFCONFIG}
		print "----------------------------------------------------------------"
		print "Merging $1 with $DEFCONFIG"
		print "----------------------------------------------------------------"

		if [ ! -f "${KERNEL_DIR}/arch/arm64/configs/$1" ]; then
			print "----------------------------------------------------------------"
			print "$1 File not found!"
			print "----------------------------------------------------------------"
		else
			cat "${KERNEL_DIR}/arch/arm64/configs/$1" >>"${OUT_DIR}"/.config

			print "----------------------------------------------------------------"
			print "Merge complete"
			print "----------------------------------------------------------------"
		fi

	else
		make ${ARGS} ${DEFCONFIG}
	fi

}

# Make performance defconfig with optional argument
# If argument is passed, merge it with defconfig
function build_performance_config() {
	make ${ARGS} ${DEFCONFIG}
	# check if arg > 0
	if [ $# -gt 0 ]; then
		print "----------------------------------------------------------------"
		print "Merging $1 and rockchip_performance.config with $DEFCONFIG"
		print "----------------------------------------------------------------"

		if [ ! -f "${KERNEL_DIR}/arch/arm64/configs/$1" ]; then
			print "----------------------------------------------------------------"
			print "$1 File not found!"
			print "----------------------------------------------------------------"
		else
			cat "${KERNEL_DIR}/arch/arm64/configs/$1" >>"${OUT_DIR}"/.config
			cat "${KERNEL_DIR}"/arch/arm64/configs/rockchip_performance.config >>"${OUT_DIR}"/.config
			print "----------------------------------------------------------------"
			print "Merge complete"
			print "----------------------------------------------------------------"
		fi

	else
		print "----------------------------------------------------------------"
		print "Merging rockchip_performance.config with $DEFCONFIG"
		print "----------------------------------------------------------------"

		if [ ! -f "${KERNEL_DIR}"/arch/arm64/configs/rockchip_performance.config ]; then
			print "----------------------------------------------------------------"
			print "rockchip_performance.config File not found!"
			print "----------------------------------------------------------------"
		else
			cat "${KERNEL_DIR}"/arch/arm64/configs/rockchip_performance.config >>"${OUT_DIR}"/.config
			print "----------------------------------------------------------------"
			print "Merge complete"
			print "----------------------------------------------------------------"
		fi

	fi
}

# Make kernel image
function build_kernel() {
	if [ "$CLANG" == "1" ]; then
		print "----------------------------------------------------------------"
		print "Building with Clang"
		print "----------------------------------------------------------------"
		build_clang
	else
		print "----------------------------------------------------------------"
		print "Building with GCC"
		print "----------------------------------------------------------------"
		build_gcc
	fi
	# check performance config
	if [ "$PERF" == "1" ]; then
		print "----------------------------------------------------------------"
		print "Building with Performance config"
		print "----------------------------------------------------------------"
		build_performance_config "$@"
	else
		print "----------------------------------------------------------------"
		print "Building with Default (Non performance) config"
		print "----------------------------------------------------------------"
		build_config "$@"
	fi

	print "----------------------------------------------------------------"
	print "Building kernel image"
	print "----------------------------------------------------------------"
	make ${ARGS}
}

# Make modules and gunzip them to modules_vicharak directory
function build_modules() {
	if [ ! -d "${OUT_DIR}/modules_vicharak" ]; then
		mkdir -p "${OUT_DIR}"/modules_vicharak
	fi
	make modules_install ${ARGS} INSTALL_MOD_PATH="${OUT_DIR}"/modules_vicharak
	# tar gzip modules
	tar -czvf "${OUT_DIR}"/modules_vicharak.tar.gz -C "${OUT_DIR}"/modules_vicharak .
}

# Update defconfig with savedefconfig command
function update_defconfig() {
	if [ "$CLANG" == "1" ]; then
		print "----------------------------------------------------------------"
		print "Building with Clang"
		print "----------------------------------------------------------------"
		build_clang
	else
		print "----------------------------------------------------------------"
		print "Building with GCC"
		print "----------------------------------------------------------------"
		build_gcc
	fi
	build_config
	make ${ARGS} savedefconfig

	mv "${OUT_DIR}"/defconfig "${KERNEL_DIR}"/arch/arm64/configs/"${DEFCONFIG}"
	print "----------------------------------------------------------------"
	print "Updated ${DEFCONFIG} with savedefconfig"
	print "----------------------------------------------------------------"
}

# Package debian package
function pack_deb() {
	make ${ARGS} bindeb-pkg

	if [ ! -d "${OUT_DIR}/deb" ]; then
		mkdir -p "${OUT_DIR}"/deb
	fi

	mv "${KERNEL_DIR}"/*.deb "${OUT_DIR}"/deb
	mv "${KERNEL_DIR}"/*.changes "${OUT_DIR}"/deb

	print "----------------------------------------------------------------"
	print "Debian package created at ${OUT_DIR}/deb"
	print "----------------------------------------------------------------"
}

if echo "$@" | grep -wqE "help|-h"; then
	if [ -n "$2" ] && [ "$(type -t usage$2)" == function ]; then
		print "----------------------------------------------------------------"
		print "--- $2 Build Command ---"
		print "----------------------------------------------------------------"
		eval usage$2
	else
		usage
	fi
	exit 0
fi

OPTIONS=$(echo "$@" | sed -e 's/ /\n/g' | tr '\n' ' ')
print "--- Build Commands = ${OPTIONS}"
for OPT in ${OPTIONS}; do
	case ${OPT} in
	"clean" | "-C")
		cleanup
		;;
	"clang" | "-c")
		export CLANG=1
		;;
	"perf" | "-p")
		export PERF=1
		;;
	"modules" | "-m")
		build_modules
		;;
	"update" | "-u")
		update_defconfig
		;;
	"axon" | "-A")
		print "----------------------------------------------------------------"
		print "Building for Axon"
		print "----------------------------------------------------------------"
		export DTB_FILE="${OUT_DIR}/arch/arm64/boot/dts/rockchip/rk3588-axon.dtb"
		build_kernel rk3588_axon.config
		pack_image
		;;
	"vaaman" | "-V")
		print "----------------------------------------------------------------"
		print "Building for Vaaman"
		print "----------------------------------------------------------------"
		export DTB_FILE="${OUT_DIR}/arch/arm64/boot/dts/rockchip/rk3399-vaaman.dtb"
		build_kernel rk3399_vaaman.config
		pack_image
		;;
	"deb" | "-d")
		print "----------------------------------------------------------------"
		print "Building Debian Package"
		print "----------------------------------------------------------------"
		pack_deb
		;;
	*)
		print "----------------------------------------------------------------"
		print "Invalid option: ${OPT}"
		print "----------------------------------------------------------------"
		usage
		;;
	esac
done
