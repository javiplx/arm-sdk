#!/usr/bin/env zsh
# Copyright (c) 2016 Dyne.org Foundation
# arm-sdk is written and maintained by Ivan J. <parazyd@dyne.org>
#
# This file is part of arm-sdk
#
# This source code is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This software is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this source code. If not, see <http://www.gnu.org/licenses/>.

## kernel build script for Acer Chromebook boards

## settings & config
vars+=(device_name arch size parted_type parted_boot parted_root inittab)
vars+=(gitkernel gitbranch)
arrs+=(custmodules)
arrs+=(gpt_root gpt_boot)

device_name="chromeacer"
arch="armhf"
size=1730
#inittab=""

parted_type="gpt"
gpt_boot=(8192 32768)
gpt_root=(40960)

extra_packages+=(abootimg cgpt fake-hwclock u-boot-tools)
extra_packages+=(vboot-utils vboot-kernel-utils)
extra_packages+=(laptop-mode-tools usbutils)
custmodules=()

gitkernel="https://chromium.googlesource.com/chromiumos/third_party/kernel"
gitbranch="chromeos-3.10"


prebuild() {
	fn prebuild
	req=(device_name strapdir)
	ckreq || return 1

	notice "executing $device_name prebuild"

	enablessh
	write-fstab
	copy-zram-init
	install-custom-packages

	mkdir -p $R/tmp/kernels/$device_name
}

postbuild() {
	fn postbuild

	notice "executing $device_name postbuild"

	## {{{ yo dawg i heard you like hacks
	## lid switch
	notice "yo dawg i heard you like hacks"
	act "writing 99-tegra-lid-switch.rules"
	cat << EOF | sudo tee ${strapdir}/etc/udev/rules.d/99-tegra-lid-switch.rules ${TEEVERBOSE}
ACTION=="remove", GOTO="tegra_lid_switch_end"
SUBSYSTEM=="input", KERNEL=="event*", SUBSYSTEMS=="platform", KERNELS=="gpio-keys.4", TAG+="power-switch"
LABEL="tegra_lid_switch_end"
EOF

	## hack in a hack
	act "writing hide-emmc-partitions.rules"
	cat << EOF | sudo tee ${strapdir}/etc/udev/rules.d/99-hide-emmc-partitions.rules ${TEEVERBOSE}
KERNEL=="mmcblk0*", ENV{UDISKS_IGNORE}="1"
EOF

	## nvidia device nodes
	act "writing nvrm.rules"
	cat << EOF | sudo tee ${strapdir}/lib/udev/rules.d/51-nvrm.rules ${TEEVERBOSE}
KERNEL=="knvmap", GROUP="video", MODE="0660"
KERNEL=="nvhdcp1", GROUP="video", MODE="0660"
KERNEL=="nvhost-as-gpu", GROUP="video", MODE="0660"
KERNEL=="nvhost-ctrl", GROUP="video", MODE="0660"
KERNEL=="nvhost-ctrl-gpu", GROUP="video", MODE="0660"
KERNEL=="nvhost-dbg-gpu", GROUP="video", MODE="0660"
KERNEL=="nvhost-gpu", GROUP="video", MODE="0660"
KERNEL=="nvhost-msenc", GROUP="video", MODE=0660"
KERNEL=="nvhost-prof-gpu", GROUP="video", MODE=0660"
KERNEL=="nvhost-tsec", GROUP="video", MODE="0660"
KERNEL=="nvhost-vic", GROUP="video", MODE="0660"
KERNEL=="nvmap", GROUP="video", MODE="0660"
KERNEL=="tegra_dc_0", GROUP="video", MODE="0660"
KERNEL=="tegra_dc_1", GROUP="video", MODE="0660"
KERNEL=="tegra_dc_ctrl", GROUP="video", MODE="0660"
EOF

	sudo mkdir -p ${strapdir}/etc/X11/xorg.conf.d
	act "writing synaptics-chromebook.conf (xorg)"
	cat <<EOF | sudo tee ${strapdir}/etc/X11/xorg.conf.d/10-synaptics-chromebook.conf ${TEEVERBOSE}
Section "InputClass"
	Identifier "touchpad"
	MatchIsTouchpad "on"
	Driver "synaptics"
	Option "TapButton1"    "1"
	Option "TapButton2"    "3"
	Option "TapButton3"    "2"
	Option "FingerLow"     "15"
	Option "FingerHigh"    "20"
	Option "FingerPress"   "256"
EndSection
EOF
	## }}}

	notice "grabbing some coreboot stuff"
	#clone-git "https://chromium.googlesource.com/chromiumos/third_party/coreboot" "$R/tmp/chromiumos-coreboot"
	git clone https://chromium.googlesource.com/chromiumos/third_party/coreboot $R/tmp/chromiumos-coreboot

	pushd $R/tmp/chromiumos-coreboot
		notice "copying coreboot tegra"
		git checkout 071167b667685c26106641e6899984c7bd91e84b

		make GCC_PREFIX=${compiler} -C src/soc/nvidia/tegra124/lp0 || zerr
		sudo mkdir -p $strapdir/lib/firmware/tegra12x
		sudo cp -f $CPVERBOSE src/soc/nvidia/tegra124/lp0/tegra_lp0_resume.fw $strapdir/lib/firmware/tegra/12x/
	popd

	sudo dd if=$workdir/kernel.bin of=$bootpart || { die "unable to dd to $bootpart"; zerr }

	postbuild-clean
}

build_kernel_armhf() {
	fn build_kernel_armhf
	req=(R arch device_name gitkernel gitbranch MAKEOPTS)
	req+=(strapdir)
	req+=(loopdevice)
	ckreq || return 1

	notice "building $arch kernel"

	prebuild || zerr


	get-kernel-sources
	pushd $R/tmp/kernels/$device_name/${device_name}-linux
		#WIFIVERSION="-3.8" make exynos_defconfig || zerr
		copy-kernel-config
		mkdir -p firmware/nvidia/tegra124/
		cp -f $R/extra/chromebook-acer/xusb.bin firmware/nvidia/tegra124/
		WIFIVERSION="-3.8" make $MAKEOPTS || zerr
		WIFIVERSION="-3.8" make $MAKEOPTS dtbs || zerr
		sudo -E PATH="$PATH" \
			WIFIVERSION="-3.8" \
			make INSTALL_MOD_PATH=$strapdir modules_install || zerr
	popd

	#sudo rm -rf $strapdir/lib/firmware
	#get-kernel-firmware
	#sudo cp $CPVERBOSE -ra $R/tmp/linux-firmware $strapdir/lib/firmware

	pushd $R/tmp/kernels/$device_name/${device_name}-linux/arch/arm/boot
	## {{{ kernel-nyan.its
	cat << EOF | sudo tee kernel-nyan.its
/dts-v1/;
/ {
	description = "Chrome OS kernel image with one or more FDT blobs";
	#address-cells = <1>;
	images {
		kernel@1{
			description = "kernel";
			data = /incbin/("zImage");
			type = "kernel_noload";
			arch = "arm";
			os = "linux";
			compression = "none";
			load = <0>;
			entry = <0>;
		};
		fdt@1{
			description = "tegra124-nyan-big-rev0_2.dtb";
			data = /incbin/("dts/tegra124-nyan-big-rev0_2.dtb");
			type = "flat_dt";
			arch = "arm";
			compression = "none";
			hash@1{
				algo = "sha1";
			};
		};
		fdt@2{
			description = "tegra124-nyan-big-rev3_7.dtb";
			data = /incbin/("dts/tegra124-nyan-big-rev3_7.dtb");
			type = "flat_dt";
			arch = "arm";
			compression = "none";
			hash@1{
				algo = "sha1";
			};
		};
		fdt@3{
			description = "tegra124-nyan-big-rev8_9.dtb";
			data = /incbin/("dts/tegra124-nyan-big-rev8_9.dtb");
			type = "flat_dt";
			arch = "arm";
			compression = "none";
			hash@1{
				algo = "sha1";
			};
		};
		fdt@4{
			description = "tegra124-nyan-blaze.dtb";
			data = /incbin/("dts/tegra124-nyan-blaze.dtb");
			type = "flat_dt";
			arch = "arm";
			compression = "none";
			hash@1{
				algo = "sha1";
			};
		};
		fdt@5{
			description = "tegra124-nyan-rev0.dtb";
			data = /incbin/("dts/tegra124-nyan-rev0.dtb");
			type = "flat_dt";
			arch = "arm";
			compression = "none";
			hash@1{
				algo = "sha1";
			};
		};
		fdt@6{
			description = "tegra124-nyan-rev1.dtb";
			data = /incbin/("dts/tegra124-nyan-rev1.dtb");
			type = "flat_dt";
			arch = "arm";
			compression = "none";
			hash@1{
				algo = "sha1";
			};
		};
		fdt@7{
			description = "tegra124-nyan-kitty-rev0_3.dtb";
			data = /incbin/("dts/tegra124-nyan-kitty-rev0_3.dtb");
			type = "flat_dt";
			arch = "arm";
			compression = "none";
			hash@1{
				algo = "sha1";
			};
		};
		fdt@8{
			description = "tegra124-nyan-kitty-rev8.dtb";
			data = /incbin/("dts/tegra124-nyan-kitty-rev8.dtb");
			type = "flat_dt";
			arch = "arm";
			compression = "none";
			hash@1{
				algo = "sha1";
			};
		};
	};
	configurations {
		default = "conf@1";
		conf@1{
			kernel = "kernel@1";
			fdt = "fdt@1";
		};
		conf@2{
			kernel = "kernel@1";
			fdt = "fdt@2";
		};
		conf@3{
			kernel = "kernel@1";
			fdt = "fdt@3";
		};
		conf@4{
			kernel = "kernel@1";
			fdt = "fdt@4";
		};
		conf@5{
			kernel = "kernel@1";
			fdt = "fdt@5";
		};
		conf@6{
			kernel = "kernel@1";
			fdt = "fdt@6";
		};
		conf@7{
			kernel = "kernel@1";
			fdt = "fdt@7";
		};
		conf@8{
			kernel = "kernel@1";
			fdt = "fdt@8";
		};
	};
};
EOF
	## }}}
	notice "making kernel-nyan image"
	mkimage -f kernel-nyan.its nyan-big-kernel || zerr

	## BEHOLD THE POWER OF PARTUUID/PARTNROFF
	print "noinitrd console=tty1 quiet root=PARTUUID=%U/PARTNROFF=1 rootwait rw lsm.module_locking=0 net.ifnames=0 rootfstype=ext4" > cmdline

	sudo dd if=/dev/zero of=bootloader.bin bs=512 count=1 || { die "unable to dd bootloader"; zerr }

	vbutil_kernel --arch arm --pack $workdir/kernel.bin \
		--keyblock /usr/share/vboot/devkeys/kernel.keyblock \
		--signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
		--version 1 \
		--config cmdline \
		--bootloader bootloader.bin \
		--vmlinuz nyan-big-kernel || zerr
	popd

	pushd $R/tmp/kernels/$device_name/${device_name}-linux
		make mrproper
		#WIFIVERSION="-3.8" make exynos_defconfig || zerr
		copy-kernel-config
		sudo -E PATH="$PATH" \
			WIFIVERSION="-3.8" \
			make modules_prepare || zerr
	popd

	postbuild || zerr
}
