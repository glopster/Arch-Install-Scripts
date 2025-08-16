#!/usr/bin/env bash

# ----- Colors -----
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

  echo -e "${GREEN}Scanning for networks...${NC}\n"
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

# --- DRIVE PARTITIONING ---
printf "${PURPLE}========== Partition Your Drives ==========${NC}\n"
printf "${CYAN}Would you like to partition your drives? (y/n): ${NC}"
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

# ROOT (mount this FIRST)
printf "${CYAN}Enter your root partition (e.g. /dev/nvme0n1p2): ${NC}"
read ROOT_PARTITION
if [[ -b "$ROOT_PARTITION" ]]; then
  printf "${CYAN}Format as 'btrfs' or 'ext4'?: ${NC}"
  read ROOT_FORMAT
  if [[ "$ROOT_FORMAT" == "btrfs" ]]; then
    pacman -S --noconfirm btrfs-progs

    echo -e "${GREEN}Formatting root partition as Btrfs...${NC}"
    mkfs.btrfs -L root "$ROOT_PARTITION"

    echo -e "${GREEN}Creating subvolumes...${NC}"
    mount "$ROOT_PARTITION" /mnt
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@log
    btrfs subvolume create /mnt/@cache
    btrfs subvolume create /mnt/@tmp
    btrfs subvolume create /mnt/@.snapshots
    umount /mnt

    echo -e "${GREEN}Mounting subvolumes...${NC}"
    mount -o subvol=@,compress=zstd,noatime "$ROOT_PARTITION" /mnt
    mkdir -p /mnt/{home,var/log,var/cache,var/tmp,.snapshots}

    mount -o subvol=@home,compress=zstd,noatime "$ROOT_PARTITION" /mnt/home
    mount -o subvol=@log,compress=zstd,noatime "$ROOT_PARTITION" /mnt/var/log
    mount -o subvol=@cache,compress=zstd,noatime "$ROOT_PARTITION" /mnt/var/cache
    mount -o subvol=@tmp,compress=zstd,noatime "$ROOT_PARTITION" /mnt/var/tmp
    mount -o subvol=@.snapshots,compress=zstd,noatime "$ROOT_PARTITION" /mnt/.snapshots

  elif [[ "$ROOT_FORMAT" == "ext4" ]]; then
    mkfs.ext4 "$ROOT_PARTITION"
    mount "$ROOT_PARTITION" /mnt
  else
    echo -e "${RED}Unknown format. Exiting.${NC}"; exit 1
  fi
else
  echo -e "${RED}Root partition not found. Exiting.${NC}"; exit 1
fi

# BOOT (mount after root)
printf "${CYAN}Enter your boot partition (e.g. /dev/nvme0n1p1): ${NC}"
read BOOT_PARTITION
if [[ -b "$BOOT_PARTITION" ]]; then
  mkfs.fat -F 32 "$BOOT_PARTITION"
  mkdir -p /mnt/boot
  mount "$BOOT_PARTITION" /mnt/boot
else
  echo -e "${RED}Boot partition not found. Exiting.${NC}"; exit 1
fi

# --- SWAP ---
printf "${CYAN}Do you want SWAP? (y/n): ${NC}"
read SWAP_YES_NO
if [[ "$SWAP_YES_NO" =~ ^[Yy]$ ]]; then
  if [[ "$ROOT_FORMAT" == "btrfs" ]]; then
    printf "${CYAN}Swap size in MB (e.g. 4096): ${NC}"
    read RAM_AMOUNT
    mkdir -p /mnt/swap
    btrfs subvolume create /mnt/@swap
    chattr +C /mnt/@swap
    dd if=/dev/zero of=/mnt/@swap/swapfile bs=1M count="$RAM_AMOUNT" status=progress
    chmod 600 /mnt/@swap/swapfile
    mkswap /mnt/@swap/swapfile
    swapon /mnt/@swap/swapfile
  else
    printf "${CYAN}Swap size (e.g. 4G): ${NC}"
    read RAM_AMOUNT
    fallocate -l "$RAM_AMOUNT" /mnt/swapfile
    chmod 600 /mnt/swapfile
    mkswap /mnt/swapfile
    swapon /mnt/swapfile
  fi
fi

# --- INSTALL BASE ---
EXTRA_PKGS=()
[[ "$ROOT_FORMAT" == "btrfs" ]] && EXTRA_PKGS+=(btrfs-progs)
pacstrap -K /mnt base linux linux-firmware base-devel networkmanager "${EXTRA_PKGS[@]}"

# --- FSTAB ---
genfstab -U /mnt >> /mnt/etc/fstab
if [[ "$SWAP_YES_NO" =~ ^[Yy]$ ]]; then
  if [[ "$ROOT_FORMAT" == "btrfs" ]]; then
    echo '/@swap/swapfile none swap defaults 0 0' >> /mnt/etc/fstab
  else
    echo '/swapfile none swap defaults 0 0' >> /mnt/etc/fstab
  fi
fi

# --- Additional Drives ---
printf "${PURPLE}========== Additional Drive Setup ==========${NC}\n"
while true; do
  printf "${CYAN}Add another drive to fstab? (y/n): ${NC}"
  read ADD_DRIVE
  [[ "$ADD_DRIVE" =~ ^[Nn]$ ]] && break

  lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT
  printf "${CYAN}Enter the partition (e.g. sdb1): ${NC}"
  read DRIVE_PART
  [[ ! -b "/dev/$DRIVE_PART" ]] && { echo -e "${RED}Invalid partition.${NC}"; continue; }

  printf "${CYAN}Filesystem type: ${NC}"
  read FS_TYPE
  printf "${CYAN}Mount point (e.g. /mnt/data): ${NC}"
  read MOUNT_POINT
  [[ ! -d "/mnt$MOUNT_POINT" ]] && mkdir -p "/mnt$MOUNT_POINT"

  printf "${CYAN}Mount options [defaults]: ${NC}"
  read MOUNT_OPTS
  [[ -z "$MOUNT_OPTS" ]] && MOUNT_OPTS="defaults"

  UUID=$(blkid -s UUID -o value "/dev/$DRIVE_PART")
  [[ -z "$UUID" ]] && { echo -e "${RED}UUID lookup failed.${NC}"; continue; }

  echo "UUID=$UUID  $MOUNT_POINT  $FS_TYPE  $MOUNT_OPTS  0  2" >> /mnt/etc/fstab
done

# Test fstab **inside** target system
echo -e "${CYAN}Testing fstab inside target with 'mount -a'...${NC}"
arch-chroot /mnt mount -a && \
  echo -e "${GREEN}All target mounts succeeded.${NC}" || \
  echo -e "${RED}Some target mounts failed. Check /mnt/etc/fstab.${NC}"

# --- CHROOT CONFIG (no heredocs; run step-by-step) ---
# Locale + time + hwclock
arch-chroot /mnt bash -c 'echo "LANG=en_US.UTF-8" > /etc/locale.conf'
arch-chroot /mnt bash -c "sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen"
arch-chroot /mnt ln -sf /usr/share/zoneinfo/America/Los_Angeles /etc/localtime
arch-chroot /mnt hwclock --systohc

# Hostname
while true; do
  printf "${CYAN}Computer hostname: ${NC}"
  read COMPUTER_NAME
  printf "${CYAN}Re-enter hostname: ${NC}"
  read COMPUTER_NAME_2
  if [[ "$COMPUTER_NAME" == "$COMPUTER_NAME_2" ]]; then
    echo "$COMPUTER_NAME" | arch-chroot /mnt tee /etc/hostname >/dev/null
    break
  else
    echo -e "${RED}Hostnames do not match. Try again.${NC}"
  fi
done

# Enable services
arch-chroot /mnt systemctl enable fstrim.timer || true
arch-chroot /mnt systemctl enable NetworkManager

# Root password
echo -e "${CYAN}Set root password (inside chroot).${NC}"
arch-chroot /mnt passwd

# User account
while true; do
  printf "${CYAN}New username: ${NC}"
  read USER_NAME
  printf "${CYAN}Re-enter username: ${NC}"
  read USER_NAME_2
  if [[ "$USER_NAME" == "$USER_NAME_2" ]]; then
    arch-chroot /mnt useradd -m -G wheel,storage,power -s /bin/bash "$USER_NAME"
    echo -e "${CYAN}Set password for ${USER_NAME}.${NC}"
    arch-chroot /mnt passwd "$USER_NAME"
    break
  else
    echo -e "${RED}Usernames do not match. Try again.${NC}"
  fi
done

# Sudoers: enable wheel and require root password
arch-chroot /mnt bash -c "sed -i '/%wheel ALL=(ALL:ALL) ALL/s/^# //' /etc/sudoers"
arch-chroot /mnt bash -c "grep -q '^Defaults rootpw' /etc/sudoers || echo 'Defaults rootpw' >> /etc/sudoers"

# --- GRUB Bootloader (UEFI/BIOS) ---
printf "${PURPLE}========== Bootloader Setup (GRUB) ==========${NC}\n"
arch-chroot /mnt pacman -S --noconfirm grub efibootmgr os-prober mtools

# Determine disk that holds the root partition (for BIOS GRUB)
ROOT_DISK=$(lsblk -no pkname "$ROOT_PARTITION")
if [[ -d /sys/firmware/efi/efivars ]]; then
  echo -e "${GREEN}UEFI detected. Installing GRUB (EFI)...${NC}"
  arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
  echo -e "${GREEN}BIOS detected. Installing GRUB (MBR) on /dev/${ROOT_DISK}...${NC}"
  arch-chroot /mnt grub-install --target=i386-pc "/dev/${ROOT_DISK}"
fi
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
echo -e "${GREEN}GRUB installed.${NC}"

echo -e "${GREEN}Installation complete! You can now 'arch-chroot /mnt' for any extras, or reboot.${NC}"
printf "${CYAN}Reboot now? (y/n): ${NC}"
read REBOOT_ANS
if [[ "$REBOOT_ANS" =~ ^[Yy]$ ]]; then
  umount -R /mnt || true
  echo -e "${GREEN}Rebooting...${NC}"
  reboot
fi
