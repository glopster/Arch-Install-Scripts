#!/bin/bash
CYAN='\033[0;36m'
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m' # No Color

clear


# Wi-Fi setup with verification
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

    # Wait briefly for connection
    sleep 5

    # Verify connection with ping
    if ping -c 3 -W 3 google.com > /dev/null 2>&1; then
      echo -e "${GREEN}Connected successfully!${NC}"
      break
    else
      echo -e "${RED}Connection failed!${NC}"
      printf "${CYAN}Restart full Wi-Fi setup? (y) or retry credentials? (n): ${NC}"
      read RETRY_CHOICE
      if [[ "$RETRY_CHOICE" =~ ^[Yy]$ ]]; then
        # restart full process
        iwctl device list
        printf "${CYAN}Choose network interface: ${NC}"
        read NETWORK_INTERFACE
        iwctl station "$NETWORK_INTERFACE" scan
        iwctl station "$NETWORK_INTERFACE" get-networks
      fi
      # if 'n', it will loop back to SSID/password prompt
    fi
  done
else
  echo -e "${GREEN}Ethernet selected, skipping Wi-Fi setup.${NC}"
fi

# DRIVE PARTITIONING
printf "${PURPLE}========== Partition Your Drives ==========${NC}\n"

printf "${CYAN}%-35s${NC}" "Would you like to partition your drives? (y/n): "
read PARTITION_CHOICE

lsblk

while [[ "$PARTITION_CHOICE" =~ ^[Yy]$ ]]; do
  printf "${CYAN}Which drive would you like to partition? (or 'q' to cancel): ${NC}"
  read DRIVE_TO_PARTITION

  # User cancels
  if [[ "$DRIVE_TO_PARTITION" =~ ^[Qq]$ ]]; then
    echo -e "${GREEN}Skipping partitioning...${NC}"
    break
  fi

  # Check if the drive exists
  if [[ -b "/dev/$DRIVE_TO_PARTITION" ]]; then
    cfdisk "/dev/$DRIVE_TO_PARTITION"
    echo -e "${GREEN}Drive partitioned.${NC}"
    break
  else
    echo -e "${RED}Invalid drive. Please try again.${NC}"
    printf "${CYAN}Press [Enter] to continue...${NC}"
    read
    lsblk  # Show available drives again
  fi
done


# SELECT FILE SYSTEMS FOR DRIVES
printf "${PURPLE}========== Choose Your Filesystems ==========${NC}\n"

#BOOT PARTITION
lsblk
printf "${CYAN}%-35s${NC}" "Enter your boot partition (e.g. /dev/nvme0n1p1): "
read BOOT_PARTITION

if [[ -b "/dev/$BOOT_PARTITION" ]]; then
  mkfs.fat -F 32 "$BOOT_PARTITION"
  mount "$BOOT_PARTITION" /mnt/boot
  echo -e "${GREEN}Drive successfully formatted and mounted.${NC}"
  printf "${CYAN}Press [Enter] to continue...${NC}"
else
  echo -e "${RED}Invalid drive. Please try again.${NC}"
  printf "${CYAN}Press [Enter] to continue...${NC}"
  read
  lsblk
fi

#ROOT PARTITION

