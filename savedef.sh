make O=out ARCH=arm64 nanopi4_linux_defconfig
make O=out ARCH=arm64 savedefconfig
mv out/defconfig arch/arm64/configs/nanopi4_linux_defconfig
