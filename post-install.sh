#!/bin/bash
CYAN='\033[0;36m'
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m' # No Color

clear

echo -e "${CYAN}Installing basic packages...${NC}"
sudo pacman -S --noconfirm neovim flatpak fastfetch kitty zsh ldns vlc steam lutris obs-studio discover libreoffice-fresh dolphin rhythmbox gwenview mpv btop htop yazi kate ark unzip zip spectacle gparted
yay -S --noconfirm zen-browser-bin vesktop spotify brave-bin localsend

# --- INSTALL YAY ---
echo -e "${CYAN}Installing yay (AUR helper)...${NC}"
sudo pacman -S --needed --noconfirm git base-devel
git clone https://aur.archlinux.org/yay.git /tmp/yay
cd /tmp/yay || exit
makepkg -si --noconfirm
cd ~
rm -rf /tmp/yay

# --- INSTALL PIPEWIRE (for laptop audio) ---
echo -e "${CYAN}Installing PipeWire and audio utilities...${NC}"
sudo pacman -S --noconfirm pipewire pipewire-pulse pipewire-alsa pipewire-jack pavucontrol wireplumber

# --- INSTALL KDE PLASMA 6 + SDDM + WAYLAND ---
echo -e "${CYAN}Installing KDE Plasma 6 minimal packages...${NC}"
sudo pacman -S --noconfirm plasma plasma-wayland-session kde-applications sddm kwin-wayland

# --- POWER MANAGEMENT FOR LAPTOPS ---
echo -e "${CYAN}Installing power management utilities...${NC}"
sudo pacman -S --noconfirm tlp tlp-rdw acpi acpid powertop
sudo systemctl enable tlp
sudo systemctl enable acpid

# --- ENABLE SDDM TO START KDE ---
echo -e "${CYAN}Enabling SDDM display manager...${NC}"
sudo systemctl enable sddm
sudo systemctl set-default graphical.target

# --- INSTALL FONTS ---
echo -e "${CYAN}Installing Nerd Fonts, emoji, and international fonts...${NC}"
sudo pacman -S --noconfirm ttf-dejavu ttf-liberation ttf-ubuntu-font-family noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-hack ttf-fira-code nerd-fonts-hack

# --- INSTALL MULTIMEDIA CODECS ---
echo -e "${CYAN}Installing multimedia codecs...${NC}"
sudo pacman -S --noconfirm gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-libav ffmpeg

echo -e "${GREEN}All requested packages and configurations have been installed.${NC}"

# --- INSTALL VIRT MANAGER ---]
sudo pacman -S --noconfirm qemu virt-manager dnsmasq ebtables
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt "$USER"

# ========== CUPS & Printing Setup ==========
printf "${PURPLE}========== CUPS & Printing Setup ==========${NC}\n"
# Install CUPS and related packages
sudo pacman -S --noconfirm cups cups-pdf system-config-printer
# Enable and start the CUPS service
sudo systemctl enable --now org.cups.cupsd.service
# Add current user to lp group for printing permissions
sudo usermod -aG lp "$USER"

echo -e "${GREEN}CUPS installed and started. You can now add printers using system-config-printer.${NC}"

# --- ZSH SETUP ---
#
# ohmyzsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
# zsh-autosuggestions & zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-autosuggestions.git $ZSH_CUSTOM/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $ZSH_CUSTOM/plugins/zsh-syntax-highlighting
# add to zshrc config
sed -i 's/^plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' ~/.zshrc
source ~/.zshrc
# powerlevel10k
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/powerlevel10k
echo 'source ~/powerlevel10k/powerlevel10k.zsh-theme' >>~/.zshrc
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
chsh -s /usr/bin/zsh

