#!/usr/bin/env bash
set -euo pipefail

# Map app class names to Nerd Font icons
icon_for() {
    local class="${1,,}" # lowercase
    case "$class" in
        firefox*)                echo "󰈹";;
        google-chrome*|chromium*)echo "";;
        brave*)                  echo "󰖟";;
        microsoft-edge*)         echo "󰇩";;
        code|code-oss|vscodium)  echo "󰨞";;
        neovide|nvim*)           echo "";;
        kitty|alacritty|foot|wezterm|ghostty|org.wezfurlong.wezterm)
                                 echo "";;
        thunar|nautilus|nemo|dolphin|pcmanfm*|org.gnome.nautilus)
                                 echo "󰝰";;
        spotify*)                echo "";;
        discord*)                echo "󰙯";;
        telegram*|org.telegram*) echo "";;
        slack*)                  echo "󰒱";;
        steam*)                  echo "󰓓";;
        gimp*)                   echo "";;
        inkscape*)               echo "󰃣";;
        blender*)                echo "󰂫";;
        obs*)                    echo "󰑋";;
        vlc*)                    echo "󰕼";;
        mpv*)                    echo "";;
        thunderbird*)            echo "󰺻";;
        libreoffice*writer*)     echo "󰈙";;
        libreoffice*calc*)       echo "󰧷";;
        libreoffice*impress*)    echo "󰐨";;
        libreoffice*)            echo "󰏆";;
        zathura|evince|okular|org.pwmt.zathura)
                                 echo "";;
        eog|loupe|imv|feh|org.gnome.eog)
                                 echo "󰋩";;
        pavucontrol*)            echo "󰕾";;
        nm-*|network*)           echo "󰤥";;
        signal*)                 echo "󰭹";;
        obsidian*)               echo "󱓧";;
        *)                       echo "";;
    esac
}

# Get minimized windows from special:minimized workspace
minimized=$(hyprctl clients -j | jq -c '.[] | select(.workspace.name == "special:minimized")')

# Build display lines and address list
display=""
addresses=""

while IFS= read -r win; do
    [[ -z "$win" ]] && continue
    class=$(echo "$win" | jq -r '.class')
    title=$(echo "$win" | jq -r '.title')
    addr=$(echo "$win" | jq -r '.address')
    icon=$(icon_for "$class")

    if [[ -n "$display" ]]; then
        display+=$'\n'
        addresses+=$'\n'
    fi
    display+="$icon  $class: $title"
    addresses+="$addr"
done <<< "$minimized"

# Show picker — walker exits non-zero on cancel
selected=$(echo "$display" | walker --dmenu --index --placeholder "Restore minimized window") || true

if [[ -z "$selected" ]]; then
    exit 0
fi

# Look up address by index (walker --index is 0-based)
addr=$(echo "$addresses" | sed -n "$((selected + 1))p")

if [[ -z "$addr" ]]; then
    exit 0
fi

# Get current workspace and move the window there
ws=$(hyprctl activeworkspace -j | jq -r '.id')
hyprctl dispatch movetoworkspace "$ws,address:$addr"
