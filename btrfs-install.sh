#!/bin/bash

echo "==========Partition Your Drives=========="

read -p "Would you like to partition your drives? (y/n): " PARTITION_CHOICE
if [[ "$PARTITION_CHOICE" =~ ^[Yy]$ ]]; then
  lsblk
  read -p "Which drive would you like to partition?: " DRIVE_TO_PARTITION
  cfdisk "$DRIVE_TO_PARTITION"
  echo "Drive partitioned."
else
  echo "Skipping partitioning."
fi

