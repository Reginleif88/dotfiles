#!/usr/bin/env bash
# Bluetooth panel backend for Quickshell bar
# Uses bluetoothctl + pactl + jq to produce JSON for the QML popup
# Adapted from ilyamiro/nixos-configuration bluetooth_panel_logic.sh
set -euo pipefail

CACHE_DIR="/tmp/quickshell_network_cache"
mkdir -p "$CACHE_DIR"

# ── Device-type icon mapping ─────────────────────────────────────────
get_icon() {
    local mac="$1"
    local info
    info=$(bluetoothctl info "$mac" 2>/dev/null || true)
    local icon_str
    icon_str=$(echo "$info" | grep -i "Icon:" | head -1 | awk '{print $2}')
    case "$icon_str" in
        audio-headphones|audio-headset) echo "🎧" ;;
        phone)                          echo "📱" ;;
        input-mouse)                    echo "🖱" ;;
        input-keyboard)                 echo "⌨" ;;
        input-gaming)                   echo "🎮" ;;
        audio-card)                     echo "🔊" ;;
        computer)                       echo "💻" ;;
        *)                              echo "📶" ;;
    esac
}

# ── Audio profile detection via pactl ────────────────────────────────
get_audio_profile() {
    local mac="$1"
    local mac_under="${mac//:/_}"
    local profile=""
    # Search pactl cards for this device's active profile
    local card_info
    card_info=$(pactl list cards 2>/dev/null || true)
    if echo "$card_info" | grep -qi "$mac_under"; then
        local active_profile
        active_profile=$(echo "$card_info" | awk -v dev="$mac_under" '
            BEGIN { found=0 }
            /Name:/ && tolower($0) ~ tolower(dev) { found=1 }
            found && /Active Profile:/ { gsub(/.*Active Profile: */, ""); print; exit }
        ')
        case "$active_profile" in
            *a2dp*|*A2DP*)  profile="Hi-Fi (A2DP)" ;;
            *hfp*|*HFP*|*hsp*|*HSP*) profile="Calls (HFP)" ;;
            *headset*) profile="Headset" ;;
            *) profile="$active_profile" ;;
        esac
    fi
    echo "$profile"
}

# ── Get battery level ────────────────────────────────────────────────
get_battery() {
    local mac="$1"
    local info
    info=$(bluetoothctl info "$mac" 2>/dev/null || true)
    local battery
    battery=$(echo "$info" | grep -i "Battery Percentage" | grep -oP '0x[0-9a-fA-F]+\s*\(\K[0-9]+' || true)
    echo "${battery:-}"
}

# ── Check if BT is powered on ───────────────────────────────────────
get_power() {
    local powered
    powered=$(bluetoothctl show 2>/dev/null | grep "Powered:" | awk '{print $2}')
    if [[ "$powered" == "yes" ]]; then
        echo "on"
    else
        echo "off"
    fi
}

# ── Build status JSON ────────────────────────────────────────────────
build_status() {
    local power
    power=$(get_power)

    if [[ "$power" == "off" ]]; then
        echo '{"power":"off","connected":[],"devices":[]}'
        return
    fi

    # Get paired devices
    local paired_raw
    paired_raw=$(bluetoothctl devices Paired 2>/dev/null || bluetoothctl paired-devices 2>/dev/null || true)

    local connected_json="[]"
    local devices_json="[]"

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local mac name
        mac=$(echo "$line" | awk '{print $2}')
        name=$(echo "$line" | cut -d' ' -f3-)
        [[ -z "$mac" ]] && continue
        [[ -z "$name" ]] && name="$mac"

        # Check cache for stable data (icon)
        local icon_cache="$CACHE_DIR/bt_icon_${mac//:/}"
        local icon
        if [[ -f "$icon_cache" ]]; then
            icon=$(cat "$icon_cache")
        else
            icon=$(get_icon "$mac")
            echo "$icon" > "$icon_cache"
        fi

        # Check if connected
        local info
        info=$(bluetoothctl info "$mac" 2>/dev/null || true)
        local is_connected
        is_connected=$(echo "$info" | grep "Connected:" | awk '{print $2}')

        if [[ "$is_connected" == "yes" ]]; then
            # Get dynamic data
            local battery
            battery=$(get_battery "$mac")

            # Cache profile (relatively stable)
            local profile_cache="$CACHE_DIR/bt_profile_${mac//:/}"
            local profile
            if [[ -f "$profile_cache" ]] && [[ $(( $(date +%s) - $(stat -c %Y "$profile_cache" 2>/dev/null || echo 0) )) -lt 30 ]]; then
                profile=$(cat "$profile_cache")
            else
                profile=$(get_audio_profile "$mac")
                echo "$profile" > "$profile_cache"
            fi

            connected_json=$(echo "$connected_json" | jq \
                --arg id "$mac" \
                --arg name "$name" \
                --arg mac "$mac" \
                --arg icon "$icon" \
                --arg battery "$battery" \
                --arg profile "$profile" \
                '. + [{"id":$id,"name":$name,"mac":$mac,"icon":$icon,"battery":$battery,"profile":$profile}]')
        else
            # Check if paired (can connect) vs just discovered (needs pairing)
            local is_paired
            is_paired=$(echo "$info" | grep "Paired:" | awk '{print $2}')
            local action="Pair"
            [[ "$is_paired" == "yes" ]] && action="Connect"

            devices_json=$(echo "$devices_json" | jq \
                --arg id "$mac" \
                --arg name "$name" \
                --arg mac "$mac" \
                --arg icon "$icon" \
                --arg action "$action" \
                '. + [{"id":$id,"name":$name,"mac":$mac,"icon":$icon,"action":$action}]')
        fi
    done <<< "$paired_raw"

    # Also include recently discovered (non-paired) devices
    local discovered_raw
    discovered_raw=$(bluetoothctl devices 2>/dev/null || true)
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local mac name
        mac=$(echo "$line" | awk '{print $2}')
        name=$(echo "$line" | cut -d' ' -f3-)
        [[ -z "$mac" ]] && continue
        [[ -z "$name" ]] && name="$mac"

        # Skip if already in paired list
        if echo "$paired_raw" | grep -q "$mac"; then
            continue
        fi

        local icon_cache="$CACHE_DIR/bt_icon_${mac//:/}"
        local icon
        if [[ -f "$icon_cache" ]]; then
            icon=$(cat "$icon_cache")
        else
            icon=$(get_icon "$mac")
            echo "$icon" > "$icon_cache"
        fi

        devices_json=$(echo "$devices_json" | jq \
            --arg id "$mac" \
            --arg name "$name" \
            --arg mac "$mac" \
            --arg icon "$icon" \
            --arg action "Pair" \
            '. + [{"id":$id,"name":$name,"mac":$mac,"icon":$icon,"action":$action}]')
    done <<< "$discovered_raw"

    jq -n \
        --arg power "$power" \
        --argjson connected "$connected_json" \
        --argjson devices "$devices_json" \
        '{"power":$power,"connected":$connected,"devices":$devices}'
}

# ── Toggle power ─────────────────────────────────────────────────────
toggle_power() {
    local current
    current=$(get_power)
    if [[ "$current" == "on" ]]; then
        bluetoothctl power off >/dev/null 2>&1
    else
        bluetoothctl power on >/dev/null 2>&1
        # Start scan briefly to discover devices
        (bluetoothctl scan on >/dev/null 2>&1 &
         local scan_pid=$!
         sleep 5
         kill "$scan_pid" 2>/dev/null || true) &
    fi
    # Return new status after a brief wait
    sleep 0.5
    build_status
}

# ── Connect to device ────────────────────────────────────────────────
connect_device() {
    local mac="$1"
    # Pause any active scan during connect for stability
    local scan_pid
    scan_pid=$(pgrep -f "bluetoothctl scan" 2>/dev/null || true)
    [[ -n "$scan_pid" ]] && kill -STOP "$scan_pid" 2>/dev/null || true

    # Check if device is paired first
    local info
    info=$(bluetoothctl info "$mac" 2>/dev/null || true)
    local is_paired
    is_paired=$(echo "$info" | grep "Paired:" | awk '{print $2}')

    if [[ "$is_paired" != "yes" ]]; then
        bluetoothctl pair "$mac" 2>/dev/null || true
        sleep 1
        bluetoothctl trust "$mac" 2>/dev/null || true
        sleep 0.5
    fi

    bluetoothctl connect "$mac" 2>/dev/null || true
    sleep 1

    # Resume scan
    [[ -n "$scan_pid" ]] && kill -CONT "$scan_pid" 2>/dev/null || true

    # Invalidate profile cache for this device
    rm -f "$CACHE_DIR/bt_profile_${mac//:/}" 2>/dev/null || true

    build_status
}

# ── Disconnect from device ───────────────────────────────────────────
disconnect_device() {
    local mac="$1"
    bluetoothctl disconnect "$mac" 2>/dev/null || true
    sleep 0.5
    rm -f "$CACHE_DIR/bt_profile_${mac//:/}" 2>/dev/null || true
    build_status
}

# ── Main dispatch ────────────────────────────────────────────────────
case "${1:---status}" in
    --status)       build_status ;;
    --toggle)       toggle_power ;;
    --connect)      connect_device "${2:?MAC address required}" ;;
    --disconnect)   disconnect_device "${2:?MAC address required}" ;;
    *)              echo '{"error":"Unknown command"}' ;;
esac
