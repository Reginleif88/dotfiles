#!/usr/bin/env bash
# First-boot setup for hyprpm plugins.
# Runs once, then marks itself done via a flag file.

FLAG="$HOME/.local/state/hyprpm-setup-done"

if [[ -f "$FLAG" ]]; then
    exit 0
fi

mkdir -p "$(dirname "$FLAG")"

hyprpm add https://github.com/hyprwm/hyprland-plugins && \
hyprpm update && \
hyprpm enable hyprbars && \
hyprpm reload -n && \
touch "$FLAG"
