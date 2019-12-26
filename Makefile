CURDIR  := ${PWD}
PKGS    := ${CURDIR}/pkgs
TOOLS   := ${CURDIR}/tools
NETWORK := ${CURDIR}/network
INPUT   := ${CURDIR}/input
OUTPUT  := ${CURDIR}/output

UENV  := ${OUTPUT}/u-boot-env.bin
NAND  := ${OUTPUT}/qemu_nand.bin
IMAGE := ${OUTPUT}/raw_image.bin

ETHERNET := ens33

QEMU := ${TOOLS}/qemu-system-arm -M overo256 -m 256M -nographic
QEMU_NET := -net nic,macaddr=00:aa:00:60:00:01,model=lan9118,vlan=1

QEMU_TAP := ${OUTPUT}/up

QEMU_UP := ${NETWORK}/qemu-ifup
QEMU_DOWN := ${NETWORK}/qemu-ifdown

QEMU_IP := 192.168.2.5
QEMU_MASK := 255.255.255.0
QEMU_SRV_IP := 192.168.2.10

define UBOOT_ENV
	bootdelay=1
	autostart=yes
	ipaddr=${QEMU_IP}
	netmask=${QEMU_MASK}
	gatewayip=${QEMU_SRV_IP}
	serverip=${QEMU_SRV_IP}
	mtdparts=mtdparts=omap2-nand.0:512k(xloader),1792k(u-boot),256k(u-env),8m(linux),-(rootfs)
	bootargs=console=ttyO2,115200n8 nohz=0ff mtdoops.mtddev=omap2-nand.0 \
					mtdparts=omap2-nand.0:512k(xloader),1792k(u-boot),256k(u-env),8m(linux),-(rootfs) \
					ro ubi.mtd=4 rootfstype=ubifs root=ubi0:rootfs ip=${QEMU_IP}::${QEMU_SRV_IP}:${QEMU_MASK}::eth0:off
	bootcmd=nand read 0x80000000 linux 0x800000; bootm 0x80000000
endef

all: usage
run: ${OUTPUT} ${NAND}
	${QEMU} -mtdblock ${NAND}

run-net-tap: ${OUTPUT} ${NAND} ${QEMU_TAP}
	sudo ${QEMU} -mtdblock ${NAND} ${QEMU_NET} -net tap,vlan=1,script=${QEMU_TAP},downscript=no

run-net-tap-br: ${OUTPUT} ${NAND}
	export ETHERNET=${ETHERNET}
	sudo ${QEMU} -mtdblock ${NAND} ${QEMU_NET} -net tap,vlan=1,script=${QEMU_UP},downscript=${QEMU_DOWN}

run-net-ssh: ${OUTPUT} ${NAND}
	${QEMU} -mtdblock ${NAND} ${QEMU_NET} -net user,vlan=1 -redir tcp:10022::22

${QEMU_TAP}:
	echo '#!/bin/bash' > ${QEMU_TAP}
	echo 'ifconfig $$@ ${QEMU_SRV_IP} up' >> ${QEMU_TAP} && chmod +x ${QEMU_TAP}
	echo 'echo 1 > /proc/sys/net/ipv4/ip_forward' >> ${QEMU_TAP}
	echo 'iptables -t nat -A POSTROUTING -o ${ETHERNET} -j MASQUERADE' >> ${QEMU_TAP}
	echo 'iptables -A FORWARD -i ${ETHERNET} -o tap0 -m state --state RELATED,ESTABLISHED -j ACCEPT' >> ${QEMU_TAP}
	echo 'iptables -A FORWARD -i tap0 -o ${ETHERNET} -j ACCEPT' >> ${QEMU_TAP}

${IMAGE}: ${UENV}
	#0: xloader             0x00080000      0x00000000      0
	#1: u-boot              0x001c0000      0x00080000      0
	#2: u-env               0x00040000      0x00240000      0
	#3: linux               0x00800000      0x00280000      0
	#5: rootfs              0x07580000      0x00a80000      0

	dd of=${IMAGE} if=/dev/zero                bs=1M   count=256
	dd of=${IMAGE} if=${PKGS}/x-load.bin.ift   bs=2k   count=$$((0x0080000 >> 11))  seek=$$((0x0000000 >> 11))  # xloader
	dd of=${IMAGE} if=${PKGS}/u-boot.bin       bs=2k   count=$$((0x01c0000 >> 11))  seek=$$((0x0080000 >> 11))  # u-boot
	dd of=${IMAGE} if=${OUTPUT}/u-boot-env.bin bs=2k   count=$$((0x0040000 >> 11))  seek=$$((0x0240000 >> 11))  # u-env
	dd of=${IMAGE} if=${PKGS}/uImage           bs=2k   count=$$((0x0800000 >> 11))  seek=$$((0x0280000 >> 11))  # linux
	dd of=${IMAGE} if=${INPUT}/rootfs.ubi      bs=2k   count=$$((0x7580000 >> 11))  seek=$$((0x0a80000 >> 11))  # rootfs

export UBOOT_ENV
${UENV}:
	@echo "$$UBOOT_ENV" > ${OUTPUT}/u-boot-env.txt
	${TOOLS}/mkubootenv -s 131072 ${OUTPUT}/u-boot-env.txt ${UENV}

${NAND}: ${IMAGE}
	cd ${OUTPUT} && ${TOOLS}/qemu-nand 2048 64 256 512 14 < ${IMAGE}

${OUTPUT}:
	mkdir $@

br-show:
	brctl show qemu_br

br-create:
	sudo ip link add qemu_br type bridge
	sudo ip link set ${ETHERNET} master qemu_br
	sudo ip link set dev qemu_br up
	sudo ip addr flush dev ${ETHERNET}
	sudo dhclient qemu_br

br-delete:
	sudo ip link set dev ${ETHERNET} nomaster
	sudo ip link set dev qemu_br down
	sudo ip link del qemu_br
	sudo dhclient ${ETHERNET}

usage:
	@echo
	@echo "Targets:                                                                        "
	@echo "  run:              Regular machine                                             "
	@echo "  run-net-tap:      Regular machine + tap                                       "
	@echo "  run-net-tap-br:   Regular machine + bridged system ethernet with tap          "
	@echo "  run-net-ssh:      Regular machine + oppend SSH on port 10022 (ssh 0 -p 10022) "
	@echo "  br-show:          Shows qemu_br and list of interfaces participated in it     "
	@echo "  br-create:        Creates qemu_br                                             "
	@echo "  br-delete:        Delates qemu_br                                             "
	@echo "  clean:            Cleans images                                               "
	@echo "                                                                                "
	@echo "To exit: ctrl+a ^x                                                              "
	@echo

clean:
	rm -rf ${OUTPUT}/
