#!/bin/sh -x

NAME=core
IMAGE=fedora-coreos-qemu.x86_64.qcow2
BUTANE_CONFIG=core.bu
DISK_SIZE=10
MEMORY=2048
VCPUS=2
VERSION=1.28.2
STREAM=stable
PODSUBNET="10.244.0.0\/16"

while getopts ":n:i:b:c:k:d:m:s:v:p:r:h" opt; do
    case $opt in
        n) NAME="$OPTARG"
        ;;
        i) IMAGE="$OPTARG"
        ;;
        b) BUTANE_CONFIG="$OPTARG"
        ;;
        d) DISK_SIZE="$OPTARG"
        ;;
        m) MEMORY="$OPTARG"
        ;;
        s) STREAM="$OPTARG"
        ;;
        c) VCPUS="$OPTARG"
        ;;
        v) VERSION="$OPTARG"
        ;;
        p) PODSUBNET="$OPTARG"
        ;;
        r) REMOVE="yes"
        ;;
        k) SSH_KEY=$(cat "$OPTARG")
        ;;
        h) cat <<EOF
Usage: $0 [-n name] [-i image] [-b butane_config] [-d disk_size] [-m memory] [-s stream] [-c vcpus] [-v version] [-p podsubnet] [-r] [-k ssh_key_file] [-h]
Options:
  -n: name of the virtual machine
  -i: path to the image file
  -b: path to the butane config file
  -d: size of the disk in GB
  -m: amount of memory in MB
  -s: stream to use for the image
  -c: number of virtual CPUs
  -v: version of the image
  -p: pod subnet to use
  -r: remove the virtual machine
  -k: path to the SSH key file
  -h: display this help message
EOF
        exit 1
        ;;
        \?) echo "Invalid option -$OPTARG" >&2
        ;;
    esac
done

if [ "$REMOVE" == "yes" ]; then
    read -r -p "Removing $NAME, are you sure? [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY])
            sudo virsh destroy $NAME
            sudo virsh undefine $NAME
            sudo virsh vol-delete --pool default $NAME.qcow2
            exit 0
            ;;
        *)
            exit 1
            ;;
    esac
fi

if [ -z "$SSH_KEY" ]; then
    if [ -e ~/.ssh/id_ed25519.pub ]; then
        SSH_KEY=$(cat ~/.ssh/id_ed25519.pub)
        echo ed2
    elif [ -e ~/.ssh/id_rsa.pub ]; then
        SSH_KEY=$(cat ~/.ssh/id_rsa.pub)
        echo rsa
    else
        echo "No SSH key found"
        exit 1
    fi
fi

if ! [ -e $IMAGE ]; then
    echo "Image not found: $IMAGE"
    exit 1
fi

if ! [ -e $BUTANE_CONFIG ]; then
    echo "Butane config not found: $BUTANE_CONFIG"
    exit 1
fi

if ! [[ "$IMAGE" = /* ]]; then
    IMAGE=$(realpath $IMAGE)
fi

IGNITION_CONFIG=$NAME.ign
sed -e "s/HOSTNAME/$NAME/" \
    -e "s/PODSUBNET/$PODSUBNET/" \
    -e "s/VERSION/$VERSION/" \
    -e "s/SSH_KEY/$SSH_KEY/" \
    $BUTANE_CONFIG | butane --pretty --strict > $IGNITION_CONFIG || exit 1

chcon -t svirt_home_t $IGNITION_CONFIG || true
IGNITION_CONFIG=$(realpath $NAME.ign)

IGNITION_DEVICE_ARG=(--qemu-commandline="-fw_cfg name=opt/com.coreos/config,file=${IGNITION_CONFIG}")

sudo virt-install --connect="qemu:///system" --name="${NAME}" --vcpus="${VCPUS}" --memory="${MEMORY}" \
        --os-variant="fedora-coreos-$STREAM" --graphics=none --cpu=host --import \
        --disk="size=${DISK_SIZE},backing_store=${IMAGE}" \
        --network default "${IGNITION_DEVICE_ARG[@]}"
