#
# Makefile
#
# Copyright (c) 2020 Cisco Systems, Inc. <pmoore2@cisco.com>
#

#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#

include make.conf

SUBDIRS = \
	libefihelpers \
	keys \
	misc

# files to include in the fs_esp.img
FS_ESP_DEPS = \
	keys/*.efi \
	misc/*.efi \
	fs_esp/*

# extra fs space (in bytes) to allocate for the fs_esp.img
FS_ESP_BUFFER = 8388608

.PHONY: all
all: help

.PHONY: help
help:
	@echo "build system"
	@echo " make targets:"
	@echo "  help:             display a list of make targets [DEFAULT]"
	@echo "  build:            build the binaries, keys, etc."
	@echo "  qemu-esp:         start QEMU with just the ESP drive"
	@echo "  qemu-full:        start QEMU with the ESP and OS drives"
	@echo "  clean:            remove all build artifacts"
	@echo "  clean-keys:       remove all of the UEFI keys/certs"

.PHONY: build
build:
	for i in ${SUBDIRS}; do \
		${MAKE} -C $$i $@; \
	done

.PHONY: version.raw
version.raw: build
	echo "#define VERSION_STR " \
		"L\"$$(date '+%Y-%m-%d') $$(git rev-parse HEAD | cut -c 1-12)" \
		"$$(cat ${FS_ESP_DEPS} | sha1sum | cut -c 1-12)"\" \
		> version.raw

version.txt: version.raw
	diff -q version.raw $@ || cp version.raw $@

fs_esp.img: version.txt
	size=$$(du -b -c ${FS_ESP_DEPS} | tail -n 1 | awk '{ print $$1 }'); \
		guestfish -N $@=disk:$$(( $$size + ${FS_ESP_BUFFER} )) quit
	guestfish -a $@ run : part-disk /dev/sda gpt
	guestfish -a $@ run : part-set-gpt-type /dev/sda 1 "C12A7328-F81F-11D2-BA4B-00A0C93EC93B"
	guestfish -a $@ run : mkfs vfat /dev/sda1
	(tar cf - version.txt) \
		| guestfish -a $@ run : mount /dev/sda1 / : tar-in - /
	for i in ${FS_ESP_DEPS}; do \
		(cd $$(dirname $$i); tar cf - $$(basename $$i)) \
		 | guestfish -a $@ run : mount /dev/sda1 / : tar-in - /; \
	done

ovmf_fw.fd:
	cp ${OVMF_CODE} $@
ovmf_vars.fd:
	cp ${OVMF_VARS} $@

.PHONY: qemu-esp
qemu-esp: ovmf_fw.fd ovmf_vars.fd fs_esp.img
	# NOTE: swtpm normally exits when qemu exits, no need to cleanup
	[ -d .tpm2 ] || mkdir .tpm2
	(swtpm socket --tpmstate dir=.tpm2 --tpm2 \
		--ctrl type=unixio,path=.tpm2/swtpm-sock &)
	${QEMU_CMD_CORE}

.PHONY: qemu-full
qemu-full: ovmf_fw.fd ovmf_vars.fd fs_esp.img
	# NOTE: swtpm normally exits when qemu exits, no need to cleanup
	[ -d .tpm2 ] || mkdir .tpm2
	(swtpm socket --tpmstate dir=.tpm2 --tpm2 \
		--ctrl type=unixio,path=.tpm2/swtpm-sock &)
	${QEMU_CMD_CORE} \
		-drive if=virtio,format=raw,cache=none,file=drive_qemu.img \
		-drive file=distro.iso,media=cdrom

.PHONY: clean
clean:
	${RM} -f fs_esp.img version.txt
	for i in ${SUBDIRS}; do \
		${MAKE} -C $$i $@; \
	done

.PHONY: clean-keys
clean-keys:
	${MAKE} -C keys clean-keys
