#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> CachyOS personal Hyprland setup"

# ── Install chezmoi ───────────────────────────────────────────────
if ! command -v chezmoi &>/dev/null; then
  echo "==> Installing chezmoi..."
  sudo pacman -S --noconfirm chezmoi
fi

# ── Install ansible ───────────────────────────────────────────────
if ! command -v ansible-playbook &>/dev/null; then
  echo "==> Installing ansible..."
  sudo pacman -S --noconfirm ansible
fi

# ── Verify paru ───────────────────────────────────────────────────
if ! command -v paru &>/dev/null; then
  echo "==> ERROR: paru not found. CachyOS should ship paru by default."
  echo "==> Install manually: sudo pacman -S paru"
  exit 1
fi

# ── Link chezmoi source to this repo ─────────────────────────────
if [ ! -e "$HOME/.local/share/chezmoi" ]; then
  echo "==> Symlinking chezmoi source to $SCRIPT_DIR..."
  mkdir -p "$HOME/.local/share"
  ln -s "$SCRIPT_DIR" "$HOME/.local/share/chezmoi"
fi

# ── Ansible collections ──────────────────────────────────────────
echo "==> Installing ansible collections..."
ansible-galaxy collection install -r "$SCRIPT_DIR/ansible/requirements.yml"

# ── Ansible playbook ─────────────────────────────────────────────
echo "==> Running ansible playbook..."
cd "$SCRIPT_DIR/ansible"
ansible-playbook -i inventory.ini main.yml --ask-become-pass --ask-vault-pass

# ── Set zsh as default shell ─────────────────────────────────────
echo "==> Setting zsh as default shell for current user and root..."
sudo chsh -s /bin/zsh root
chsh -s /bin/zsh

# ── Full system upgrade ─────────────────────────────────────────
echo "==> Running full system upgrade..."
sudo pacman -Syu --noconfirm

# ── Apply dotfiles ────────────────────────────────────────────────
echo "==> Applying chezmoi dotfiles..."
chezmoi apply

echo "==> Bootstrap complete. Reboot and start Hyprland from TTY."
echo ""
echo "==> POST-BOOT: Run .bin in \"Downloads\" to complete some installs"
