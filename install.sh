#!/bin/bash
CYAN='\033[0;36m'
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m' # No Color

clear

# --- WIFI SETUP ---
printf "${PURPLE}========== Wifi Setup ==========${NC}\n"

printf "${CYAN}%-35s${NC}" "Are you using ethernet? (y/n): "
read USING_ETHERNET

if [[ "$USING_ETHERNET" =~ ^[Nn]$ ]]; then
  echo -e "${GREEN}Showing network interfaces...${NC}\n"
  iwctl device list

  printf "${CYAN}Choose network interface: ${NC}"
  read NETWORK_INTERFACE

  echo -e "${GREEN}Showing available networks...${NC}\n"
  iwctl station "$NETWORK_INTERFACE" scan
  iwctl station "$NETWORK_INTERFACE" get-networks

  while true; do
    printf "${CYAN}Enter network name (SSID): ${NC}"
    read WIFI_SSID
    printf "${CYAN}Enter wifi password: ${NC}"
    read -s WIFI_PASSWORD
    echo ""

    echo -e "${GREEN}Connecting to ${WIFI_SSID}...${NC}"
    iwctl --passphrase "$WIFI_PASSWORD" station "$NETWORK_INTERFACE" connect "$WIFI_SSID"
    sleep 5

    if ping -c 3 -W 3 google.com > /dev/null 2>&1; then
      echo -e "${GREEN}Connected successfully!${NC}"
      break
    else
      echo -e "${RED}Connection failed!${NC}"
      printf "${CYAN}Restart full Wi-Fi setup? (y) or retry credentials? (n): ${NC}"
      read RETRY_CHOICE
      if [[ "$RETRY_CHOICE" =~ ^[Yy]$ ]]; then
        iwctl device list
        printf "${CYAN}Choose network interface: ${NC}"
        read NETWORK_INTERFACE
        iwctl station "$NETWORK_INTERFACE" scan
        iwctl station "$NETWORK_INTERFACE" get-networks
      fi
    fi
  done
else
  echo -e "${GREEN}Ethernet selected, skipping Wi-Fi setup.${NC}"
fi

# --- MIRRORLIST ---
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
pacman -Sy --noconfirm pacman-contrib
rankmirrors -n 6 /etc/pacman.d/mirrorlist.backup > /etc/pacman.d/mirrorlist
sleep 2

# --- DRIVE PARTITIONING ---
printf "${PURPLE}========== Partition Your Drives ==========${NC}\n"
printf "${CYAN}%-35s${NC}" "Would you like to partition your drives? (y/n): "
read PARTITION_CHOICE

lsblk
if [[ "$PARTITION_CHOICE" =~ ^[Yy]$ ]]; then
  while true; do
    printf "${CYAN}Which drive would you like to partition? (or 'q' to cancel): ${NC}"
    read DRIVE_TO_PARTITION

    if [[ "$DRIVE_TO_PARTITION" =~ ^[Qq]$ ]]; then
      echo -e "${GREEN}Skipping partitioning...${NC}"
      break
    elif [[ -b "/dev/$DRIVE_TO_PARTITION" ]]; then
      cfdisk "/dev/$DRIVE_TO_PARTITION"
      echo -e "${GREEN}Drive partitioned.${NC}"
      break
    else
      echo -e "${RED}Invalid drive. Please try again.${NC}"
      lsblk
    fi
  done
fi

# --- FILESYSTEMS ---
printf "${PURPLE}========== Choose Your Filesystems ==========${NC}\n"
lsblk

# BOOT
printf "${CYAN}Enter your boot partition (e.g. /dev/nvme0n1p1): ${NC}"
read BOOT_PARTITION
if [[ -b "$BOOT_PARTITION" ]]; then
  mkfs.fat -F 32 "$BOOT_PARTITION"
  mkdir -p /mnt/boot
  mount "$BOOT_PARTITION" /mnt/boot
fi

# ROOT
printf "${CYAN}Enter your root partition (e.g. /dev/nvme0n1p2): ${NC}"
read ROOT_PARTITION
if [[ -b "$ROOT_PARTITION" ]]; then
  printf "${CYAN}Format as 'btrfs' or 'ext4'?: ${NC}"
  read ROOT_FORMAT
  if [[ "$ROOT_FORMAT" == "btrfs" ]]; then
    pacman -S --noconfirm btrfs-progs
    mkfs.btrfs -L root "$ROOT_PARTITION"
    mount "$ROOT_PARTITION" /mnt
  elif [[ "$ROOT_FORMAT" == "ext4" ]]; then
    mkfs.ext4 "$ROOT_PARTITION"
    mount "$ROOT_PARTITION" /mnt
  fi
fi

# --- SWAP ---
printf "${CYAN}Do you want SWAP? (y/n): ${NC}"
read SWAP_YES_NO

if [[ "$SWAP_YES_NO" =~ ^[Yy]$ ]]; then
  if [[ "$ROOT_FORMAT" == "btrfs" ]]; then
    printf "${CYAN}How much RAM (MB)? e.g. 4096: ${NC}"
    read RAM_AMOUNT
    btrfs subvolume create /mnt/@swap
    mount -o subvol=@swap "$ROOT_PARTITION" /mnt/swap
    chattr +C /mnt/swap
    truncate -s 0 /mnt/swap/swapfile
    dd if=/dev/zero of=/mnt/swap/swapfile bs=1M count="$RAM_AMOUNT" status=progress
    chmod 0600 /mnt/swap/swapfile
    mkswap /mnt/swap/swapfile
    swapon /mnt/swap/swapfile
  elif [[ "$ROOT_FORMAT" == "ext4" ]]; then
    printf "${CYAN}How much RAM (GB)? e.g. 4G: ${NC}"
    read RAM_AMOUNT
    fallocate -l "$RAM_AMOUNT" /mnt/swapfile
    chmod 600 /mnt/swapfile
    mkswap /mnt/swapfile
    swapon /mnt/swapfile
  fi
fi

# --- INSTALL BASE ---
pacstrap -K --noconfirm /mnt base linux linux-firmware base-devel

# --- FSTAB ---
genfstab -U /mnt >> /mnt/etc/fstab

# Add swap entry if needed
if [[ "$SWAP_YES_NO" =~ ^[Yy]$ ]]; then
  if [[ "$ROOT_FORMAT" == "btrfs" ]]; then
    echo '/swap/swapfile none swap defaults 0 0' >> /mnt/etc/fstab
  elif [[ "$ROOT_FORMAT" == "ext4" ]]; then
    echo '/swapfile none swap sw 0 0' >> /mnt/etc/fstab
  fi
fi

# ADD EXTRA DRIVES TO FSTAB
printf "${PURPLE}========== Additional Drive Setup ==========${NC}\n"

while true; do
  printf "${CYAN}Would you like to add another drive to fstab? (y/n): ${NC}"
  read ADD_DRIVE

  if [[ "$ADD_DRIVE" =~ ^[Nn]$ ]]; then
    echo -e "${GREEN}Skipping additional drives setup.${NC}"
    break
  fi

  echo -e "${GREEN}Available drives:${NC}"
  lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT

  printf "${CYAN}Enter the partition (e.g. sdb1): ${NC}"
  read DRIVE_PART

  if [[ ! -b "/dev/$DRIVE_PART" ]]; then
    echo -e "${RED}Invalid partition. Please try again.${NC}"
    continue
  fi

  printf "${CYAN}Enter filesystem type (ext4, xfs, btrfs, ntfs, vfat, etc.): ${NC}"
  read FS_TYPE

  printf "${CYAN}Enter mount point (e.g. /mnt/data): ${NC}"
  read MOUNT_POINT

  # create mount point if it doesn’t exist
  if [[ ! -d "$MOUNT_POINT" ]]; then
    mkdir -p "$MOUNT_POINT"
    echo -e "${GREEN}Created mount point at $MOUNT_POINT${NC}"
  fi

  printf "${CYAN}Enter mount options (press enter for defaults): ${NC}"
  read MOUNT_OPTS
  [[ -z "$MOUNT_OPTS" ]] && MOUNT_OPTS="defaults"

  UUID=$(blkid -s UUID -o value "/dev/$DRIVE_PART")

  if [[ -z "$UUID" ]]; then
    echo -e "${RED}Could not retrieve UUID for /dev/$DRIVE_PART. Skipping...${NC}"
    continue
  fi

  echo "UUID=$UUID  $MOUNT_POINT  $FS_TYPE  $MOUNT_OPTS  0  2" >> /etc/fstab
  echo -e "${GREEN}Added /dev/$DRIVE_PART to /etc/fstab.${NC}"

done

# TEST FSTAB MOUNTS
echo -e "${CYAN}Testing fstab entries with 'mount -a'...${NC}"
if mount -a; then
  echo -e "${GREEN}All drives mounted successfully!${NC}"
else
  echo -e "${RED}One or more drives failed to mount. Please check your /etc/fstab entries.${NC}"
fi

echo -e "${GREEN}Installation steps completed. Check /mnt/etc/fstab for accuracy and use post-install.sh for system configuration.${NC}"

