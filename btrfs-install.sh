#!/bin/bash
CYAN='\033[0;36m'
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m' # No Color

printf "${PURPLE}========== Partition Your Drives ==========${NC}\n"

printf "${CYAN}%-35s${NC}" "Would you like to partition your drives? (y/n): "
read PARTITION_CHOICE

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
    printf "${CYAN}Press 'enter' to continue...${NC}"
    read
    lsblk  # Show available drives again
  fi
done
