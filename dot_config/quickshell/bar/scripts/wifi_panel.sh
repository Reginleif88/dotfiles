#!/usr/bin/env bash
# WiFi panel backend for Quickshell bar
# Uses nmcli + jq to produce JSON for the QML popup
# Adapted from ilyamiro/nixos-configuration wifi_panel_logic.sh
set -euo pipefail

CACHE_DIR="/tmp/quickshell_network_cache"
mkdir -p "$CACHE_DIR"

# ── Signal strength → icon tiers ─────────────────────────────────────
get_signal_icon() {
    local signal="${1:-0}"
    if   (( signal >= 80 )); then echo "󰤨"    # wifi-strength-4
    elif (( signal >= 60 )); then echo "󰤥"    # wifi-strength-3
    elif (( signal >= 40 )); then echo "󰤢"    # wifi-strength-2
    elif (( signal >= 20 )); then echo "󰤟"    # wifi-strength-1
    else                          echo "󰤯"    # wifi-strength-alert
    fi
}

# ── Check if WiFi radio is on ────────────────────────────────────────
get_power() {
    local radio
    radio=$(nmcli radio wifi 2>/dev/null | tail -1 | tr -d '[:space:]')
    if [[ "$radio" == "enabled" ]]; then
        echo "on"
    else
        echo "off"
    fi
}

# ── Get active connection info ───────────────────────────────────────
get_connected() {
    local active_ssid
    active_ssid=$(nmcli -t -f NAME,TYPE,DEVICE con show --active 2>/dev/null \
        | grep ':802-11-wireless:' | head -1 | cut -d: -f1)

    if [[ -z "$active_ssid" ]]; then
        echo "null"
        return
    fi

    # Get signal strength for connected network
    local signal
    signal=$(nmcli -t -f SSID,SIGNAL dev wifi list --rescan no 2>/dev/null \
        | grep "^${active_ssid}:" | head -1 | cut -d: -f2)
    signal="${signal:-0}"

    local icon
    icon=$(get_signal_icon "$signal")

    # Get security
    local security
    security=$(nmcli -t -f SSID,SECURITY dev wifi list --rescan no 2>/dev/null \
        | grep "^${active_ssid}:" | head -1 | cut -d: -f2)
    security="${security:-Open}"

    # Get IP (cached per SSID, refreshed every 30s)
    local ip_cache="$CACHE_DIR/wifi_ip_${active_ssid//[^a-zA-Z0-9]/_}"
    local ip=""
    if [[ -f "$ip_cache" ]] && [[ $(( $(date +%s) - $(stat -c %Y "$ip_cache" 2>/dev/null || echo 0) )) -lt 30 ]]; then
        ip=$(cat "$ip_cache")
    else
        ip=$(nmcli -t -f IP4.ADDRESS dev show 2>/dev/null \
            | grep "IP4.ADDRESS" | head -1 | cut -d: -f2 | cut -d/ -f1)
        ip="${ip:-}"
        [[ -n "$ip" ]] && echo "$ip" > "$ip_cache"
    fi

    # Get frequency (cached per SSID)
    local freq_cache="$CACHE_DIR/wifi_freq_${active_ssid//[^a-zA-Z0-9]/_}"
    local freq=""
    if [[ -f "$freq_cache" ]] && [[ $(( $(date +%s) - $(stat -c %Y "$freq_cache" 2>/dev/null || echo 0) )) -lt 60 ]]; then
        freq=$(cat "$freq_cache")
    else
        freq=$(iw dev 2>/dev/null | awk '/channel/{print $2 " MHz"; exit}' || true)
        freq="${freq:-}"
        [[ -n "$freq" ]] && echo "$freq" > "$freq_cache"
    fi

    jq -n \
        --arg id "$active_ssid" \
        --arg ssid "$active_ssid" \
        --arg icon "$icon" \
        --arg signal "$signal" \
        --arg security "$security" \
        --arg ip "$ip" \
        --arg freq "$freq" \
        '{"id":$id,"ssid":$ssid,"icon":$icon,"signal":$signal,"security":$security,"ip":$ip,"freq":$freq}'
}

# ── Get available networks ───────────────────────────────────────────
get_networks() {
    local active_ssid
    active_ssid=$(nmcli -t -f NAME,TYPE,DEVICE con show --active 2>/dev/null \
        | grep ':802-11-wireless:' | head -1 | cut -d: -f1)

    local networks="[]"

    # Use --rescan no for instant results
    while IFS=: read -r ssid signal security _; do
        [[ -z "$ssid" ]] && continue
        # Skip the connected network (shown separately)
        [[ "$ssid" == "$active_ssid" ]] && continue

        local icon
        icon=$(get_signal_icon "$signal")

        networks=$(echo "$networks" | jq \
            --arg id "$ssid" \
            --arg ssid "$ssid" \
            --arg icon "$icon" \
            --arg signal "$signal" \
            --arg security "$security" \
            '. + [{"id":$id,"ssid":$ssid,"icon":$icon,"signal":$signal,"security":$security}]')
    done < <(nmcli -t -f SSID,SIGNAL,SECURITY dev wifi list --rescan no 2>/dev/null \
        | sort -t: -k2 -rn | awk -F: '!seen[$1]++')

    echo "$networks"
}

# ── Build full status JSON ───────────────────────────────────────────
build_status() {
    local power
    power=$(get_power)

    if [[ "$power" == "off" ]]; then
        echo '{"power":"off","connected":null,"networks":[]}'
        return
    fi

    local connected
    connected=$(get_connected)

    local networks
    networks=$(get_networks)

    jq -n \
        --arg power "$power" \
        --argjson connected "$connected" \
        --argjson networks "$networks" \
        '{"power":$power,"connected":$connected,"networks":$networks}'
}

# ── Toggle WiFi ──────────────────────────────────────────────────────
toggle_power() {
    local current
    current=$(get_power)
    if [[ "$current" == "on" ]]; then
        nmcli radio wifi off 2>/dev/null
    else
        nmcli radio wifi on 2>/dev/null
    fi
    sleep 1
    build_status
}

# ── Connect to network ───────────────────────────────────────────────
connect_network() {
    local ssid="$1"
    # Try known connections first
    nmcli con up "$ssid" 2>/dev/null || \
        nmcli dev wifi connect "$ssid" 2>/dev/null || true
    sleep 1

    # Invalidate IP/freq cache
    rm -f "$CACHE_DIR/wifi_ip_${ssid//[^a-zA-Z0-9]/_}" 2>/dev/null || true
    rm -f "$CACHE_DIR/wifi_freq_${ssid//[^a-zA-Z0-9]/_}" 2>/dev/null || true

    build_status
}

# ── Disconnect ───────────────────────────────────────────────────────
disconnect_network() {
    local device
    device=$(nmcli -t -f DEVICE,TYPE dev 2>/dev/null | grep ':wifi$' | head -1 | cut -d: -f1)
    [[ -n "$device" ]] && nmcli dev disconnect "$device" 2>/dev/null || true
    sleep 0.5
    build_status
}

# ── Main dispatch ────────────────────────────────────────────────────
case "${1:---status}" in
    --status)       build_status ;;
    --toggle)       toggle_power ;;
    --connect)      connect_network "${2:?SSID required}" ;;
    --disconnect)   disconnect_network ;;
    *)              echo '{"error":"Unknown command"}' ;;
esac
