<div align="center">

# dotfiles

Personal system configuration for a CachyOS / Hyprland desktop, managed with Chezmoi and provisioned by Ansible.

![Arch Linux](https://img.shields.io/badge/Arch_Linux-1793D1?style=flat&logo=archlinux&logoColor=white)
![Hyprland](https://img.shields.io/badge/Hyprland-58E1FF?style=flat&logo=hyprland&logoColor=black)
![Wayland](https://img.shields.io/badge/Wayland-FFBC00?style=flat&logo=wayland&logoColor=black)
![Chezmoi](https://img.shields.io/badge/Chezmoi-2E3440?style=flat&logo=chezmoi&logoColor=white)
![Ansible](https://img.shields.io/badge/Ansible-EE0000?style=flat&logo=ansible&logoColor=white)

Gruvbox Dark themed, dual-monitor, NVIDIA-optimized

</div>

---

## What's Included

| Category | Tools |
|---|---|
| Window Manager | Hyprland, Hyprbars |
| Status Bar | Quickshell |
| Terminal | Alacritty |
| Shell | Zsh, Oh My Zsh, Starship |
| App Launcher | Walker |
| Notifications | Mako |
| Clipboard | cliphist |
| Screenshots | grimblast |
| File Manager | Thunar |
| Browsers | Zen Browser, Google Chrome |
| Development | VS Code, Claude Code, Node.js, Bun |
| Containers | Podman, Podman Compose |
| Virtualisation | KVM / QEMU, libvirt, virt-manager |
| Gaming | Steam, DawnProton, GeForce NOW |
| GPU | NVIDIA with suspend/hibernate support |
| Theme | Gruvbox Material Dark |

---

## Repository Structure

```
dotfiles/
├── ansible/
│   ├── ansible.cfg              # Ansible configuration
│   ├── inventory.ini            # Localhost inventory
│   ├── main.yml                 # Master playbook
│   ├── requirements.yml         # Galaxy collections
│   ├── roles/
│   │   ├── ai/                  # Claude Code, NVM, Node.js, Bun
│   │   ├── apps/                # Desktop applications
│   │   ├── core/                # Base packages (git, curl, starship, zsh, ...)
│   │   ├── games/               # Steam, Proton, GeForce NOW
│   │   ├── github-repos/        # Authenticated repo cloning
│   │   ├── hyprland/            # Compositor and desktop components
│   │   ├── nvidia/              # GPU drivers, suspend services, VRAM preservation
│   │   ├── security/            # UFW firewall
│   │   └── virtualisation/      # KVM, Podman, FreeRDP
│   └── vars/
│       └── secrets.yml          # Ansible Vault encrypted secrets
├── dot_config/
│   ├── gtk-3.0/settings.ini     # GTK 3 theme settings
│   ├── gtk-4.0/settings.ini     # GTK 4 theme settings
│   ├── hypr/
│   │   ├── env.conf             # Environment variables (NVIDIA, GTK)
│   │   ├── hyprland.conf        # Main Hyprland config
│   │   ├── monitors.conf        # Display layout
│   │   └── workspaces.conf      # Workspace-to-monitor bindings
│   ├── quickshell/
│   │   └── bar/
│   │       ├── shell.qml           # Status bar (QML)
│   │       └── sidebar/
│   │           └── GeminiSidebar.qml # Gemini AI sidebar panel
│   ├── starship.toml            # Prompt configuration
│   └── xfce4/helpers.rc         # Default terminal helper
├── dot_zshrc                    # Zsh configuration
├── zen-browser/
│   ├── run_onchange_after_install-zen-userjs.sh.tmpl
│   └── user.js                  # Zen Browser user.js overrides
├── bootstrap.sh                 # One-shot system bootstrap
└── LICENSE
```

---

## Prerequisites

- **CachyOS** (or another Arch-based distribution with access to AUR)
- The Ansible Vault password for `ansible/vars/secrets.yml`

---

## Installation

```bash
git clone https://github.com/Reginleif88/dotfiles.git ~/Documents/dotfiles
cd ~/Documents/dotfiles
./bootstrap.sh
```

The bootstrap script will:

1. Install Chezmoi and Ansible if they are not already present.
2. Symlink the repository to `~/.local/share/chezmoi`.
3. Install required Ansible Galaxy collections (`community.general`, `kewlfft.aur`).
4. Run the Ansible playbook -- you will be prompted for the vault password and sudo password.
5. Set Zsh as the default shell for the current user and root.
6. Perform a full system upgrade via pacman.
7. Apply all dotfiles through Chezmoi.

---

## License

[MIT](LICENSE)
