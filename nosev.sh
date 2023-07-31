#!/bin/bash

if [ $# -lt 1 ]; then
    echo "usage: ./nosev.sh <qemu-system-x86_64 parent directory>"
    exit 1
fi
# virtio-scsi
${1}/qemu-system-x86_64 \
    -enable-kvm \
    -cpu EPYC-v4,host-phys-bits=true \
    -smp 16 \
    -m 16G \
    -machine type=q35 \
    -drive if=pflash,format=raw,unit=0,file=./OVMF_files/OVMF_CODE_nosev.fd,readonly=on \
    -drive if=pflash,format=raw,unit=1,file=./OVMF_files/OVMF_VARS_nosev.fd \
    -drive file=./cloud-config-nosev.iso,media=cdrom,index=0 \
    -drive file=./nosev.img,if=none,id=disk0,format=raw \
    -device virtio-scsi-pci,id=scsi0,disable-legacy=on,iommu_platform=true \
    -device scsi-hd,drive=disk0 \
    -nographic \
    -device virtio-net-pci,netdev=net0 \
    -netdev user,id=net0,hostfwd=tcp::2223-:22

# virtio-blk:
#     -device virtio-blk-pci,drive=drive0,id=virtblk0,num-queues=4 \
# nvme
    # -device nvme,serial=cafebabe,drive=disk0 \

# QUESTIONS
# 1. why hosy-phys-bits=true
# 2. what is machine type=q35

