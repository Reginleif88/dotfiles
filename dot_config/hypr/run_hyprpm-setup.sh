#!/usr/bin/env bash
# Runs on every chezmoi apply. Requires a live Hyprland session.

if [[ -z "$HYPRLAND_INSTANCE_SIGNATURE" ]]; then
    echo "hyprpm-setup: no Hyprland session detected, skipping."
    exit 0
fi

hyprpm update
hyprpm add https://github.com/hyprwm/hyprland-plugins || true
hyprpm enable hyprbars
hyprpm reload -n
