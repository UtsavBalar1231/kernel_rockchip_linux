#!/bin/bash

OUT=out/

make O=${OUT} ARCH=arm64 -j$(nproc --all) rockchip_defconfig
make O=${OUT} ARCH=arm64 -j$(nproc --all) savedefconfig

mv ${OUT}/defconfig arch/arm64/configs/rockchip_defconfig

