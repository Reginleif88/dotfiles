# Reginleif88's personal Dotfiles

CachyOS + [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) workstation setup managed with [Chezmoi](https://www.chezmoi.io/) (dotfiles) + [Ansible](https://docs.ansible.com/) (system packages).

## Quick Start

```bash
./bootstrap.sh
```

This will:
1. Install Chezmoi and Ansible (paru ships with CachyOS)
2. Apply base chezmoi dotfiles
3. Run Ansible playbook (system packages, NVIDIA drivers, end-4 desktop, virtualization, games, AI tools)
4. Re-apply chezmoi to overlay personal configs on top of end-4

## Structure

```
ansible/                  Ansible playbook and roles (NOT copied to home by Chezmoi)
  inventory.ini           localhost connection
  main.yml                master playbook
  vars/secrets.yml        encrypted secrets (ansible-vault)
  roles/core/             git, curl, zsh, Oh My Zsh, starship, codecs, Flatpak, GitHub CLI, Bun
  roles/security/         SSH, UFW firewall
  roles/nvidia/           NVIDIA drivers (chwd), suspend/hibernate, Limine kernel params
  roles/hyprland/         end-4/dots-hyprland installer + ydotool
  roles/virtualisation/   KVM/QEMU, libvirt, Podman, Winboat, FreeRDP
  roles/games/            Steam (multilib), DawnProton, GeForce NOW
  roles/ai/               Claude Code, NVM, Node.js, Gemini CLI
  roles/github-repos/     Private repo cloning via gh CLI + vault token
dot_config/               Chezmoi mapping for ~/.config
  hypr/custom/env.conf    NVIDIA environment variables (sourced by end-4)
  hypr/custom/general.conf  Monitor layout, input, keybinds (sourced by end-4)
bootstrap.sh              One-click setup
```

## How It Works

End-4's `hyprland.conf` automatically sources `custom/env.conf` and `custom/general.conf`. Chezmoi places our personal overrides into those paths, so no lineinfile injection is needed.

## Secrets

```bash
# Encrypt
ansible-vault encrypt ansible/vars/secrets.yml

# Edit
ansible-vault edit ansible/vars/secrets.yml
```
