#!/bin/bash
CONFIG_FILE=".vs-config"
INSTALL_DIR=$(whiptail --inputbox "Enter new Vintage Story install directory:" 10 60 3>&1 1>&2 2>&3)
if [ $? -ne 0 ] || [ -z "$INSTALL_DIR" ]; then
  echo "Cancelled"
  exit 1
fi
echo "$INSTALL_DIR" > "$CONFIG_FILE"
whiptail --msgbox "Install directory updated." 8 40
