#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> CachyOS + end-4/dots-hyprland bootstrap (chezmoi + ansible)"

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

# ── Chezmoi pass 1 ───────────────────────────────────────────────
echo "==> Applying chezmoi dotfiles (pass 1 — base configs)..."
chezmoi apply

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

# ── Dots-hyprland installer (run under zsh) ─────────────────────
HYPR_DIR="$HOME/.cache/dots-hyprland"
if [ -d "$HYPR_DIR" ] && [ ! -f "$HOME/.config/hypr/hyprland.conf" ]; then
  echo "==> Running dots-hyprland installer..."
  zsh -c "cd '$HYPR_DIR' && (printf '\n\n\n\nn\n'; yes) | ./setup install --skip-fish"
fi

# ── Patch hyprland.conf to source custom/workspaces.conf ──────────
HYPR_CONF="$HOME/.config/hypr/hyprland.conf"
if [ -f "$HYPR_CONF" ] && ! grep -q 'source=custom/workspaces.conf' "$HYPR_CONF"; then
  echo "==> Patching hyprland.conf to source custom/workspaces.conf..."
  sed -i '/^source=custom\/keybinds\.conf$/a source=custom/workspaces.conf' "$HYPR_CONF"
fi

# ── Chezmoi pass 2 ───────────────────────────────────────────────
echo "==> Applying chezmoi dotfiles (pass 2 — personal overlays)..."
chezmoi apply

echo "==> Bootstrap complete. Reboot and start Hyprland from TTY."
echo ""
echo "==> POST-BOOT: Run .bin in \"Downloads\" to complete some installs"
