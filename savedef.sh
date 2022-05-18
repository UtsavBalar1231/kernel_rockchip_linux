make O=out ARCH=arm64 vaaman_linux_defconfig
make O=out ARCH=arm64 savedefconfig
mv out/defconfig arch/arm64/configs/vaaman_linux_defconfig
