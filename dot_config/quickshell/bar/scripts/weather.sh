#!/usr/bin/env bash
# Weather data provider for Quickshell bar
# Uses Open-Meteo API (no key required) with local caching
# Inspired by github.com/ilyamiro/nixos-configuration weather.sh
set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────
CACHE_DIR="${HOME}/.cache/quickshell/weather"
GEO_CACHE="${CACHE_DIR}/location.json"
FORECAST_CACHE="${CACHE_DIR}/forecast.json"
CACHE_MAX_AGE=1800    # 30 minutes
GEO_MAX_AGE=3600      # 1 hour

DEFAULT_LAT="48.7306"
DEFAULT_LON="2.2719"
DEFAULT_CITY="Massy"

mkdir -p "$CACHE_DIR"

# ── WMO weather code → Nerd Font icon ──────────────────────────────
# Uses same \uE3xx codepoints as the existing Quickshell bar
get_icon() {
    local code=$1 is_day=${2:-1}
    case $code in
        0)       [[ $is_day -eq 1 ]] && echo -e "\uE302" || echo -e "\uE32B" ;;
        1|2)     [[ $is_day -eq 1 ]] && echo -e "\uE303" || echo -e "\uE379" ;;
        3)       echo -e "\uE312" ;;
        45|48)   echo -e "\uE311" ;;
        51|53|55|56|57|61|63|65|66|67|80|81|82)
                 echo -e "\uE318" ;;
        71|73|75|77|85|86)
                 echo -e "\uE31A" ;;
        95|96|99)
                 echo -e "\uE334" ;;
        *)       echo -e "\uE302" ;;
    esac
}

# ── WMO weather code → description ─────────────────────────────────
get_desc() {
    local code=$1
    case $code in
        0)       echo "Clear sky" ;;
        1)       echo "Mainly clear" ;;
        2)       echo "Partly cloudy" ;;
        3)       echo "Overcast" ;;
        45|48)   echo "Fog" ;;
        51)      echo "Light drizzle" ;;
        53)      echo "Drizzle" ;;
        55)      echo "Dense drizzle" ;;
        56|57)   echo "Freezing drizzle" ;;
        61)      echo "Light rain" ;;
        63)      echo "Rain" ;;
        65)      echo "Heavy rain" ;;
        66|67)   echo "Freezing rain" ;;
        71)      echo "Light snow" ;;
        73)      echo "Snow" ;;
        75)      echo "Heavy snow" ;;
        77)      echo "Snow grains" ;;
        80)      echo "Light showers" ;;
        81)      echo "Showers" ;;
        82)      echo "Heavy showers" ;;
        85|86)   echo "Snow showers" ;;
        95)      echo "Thunderstorm" ;;
        96|99)   echo "Thunderstorm with hail" ;;
        *)       echo "Unknown" ;;
    esac
}

# ── WMO weather code → Gruvbox hex color ───────────────────────────
get_hex() {
    local code=$1 is_day=${2:-1}
    case $code in
        0)       [[ $is_day -eq 1 ]] && echo "#fabd2f" || echo "#d3869b" ;;
        1|2)     echo "#83a598" ;;
        3)       echo "#a89984" ;;
        45|48)   echo "#a89984" ;;
        51|53|55|56|57|61|63|65|66|67|80|81|82)
                 echo "#83a598" ;;
        71|73|75|77|85|86)
                 echo "#ebdbb2" ;;
        95|96|99)
                 echo "#fb4934" ;;
        *)       echo "#8ec07c" ;;
    esac
}

# ── Geolocation via ipinfo.io ──────────────────────────────────────
get_location() {
    # Return cached location if fresh enough
    if [[ -f "$GEO_CACHE" ]]; then
        local age=$(( $(date +%s) - $(stat -c %Y "$GEO_CACHE") ))
        if [[ $age -lt $GEO_MAX_AGE ]]; then
            cat "$GEO_CACHE"
            return
        fi
    fi

    local geo
    geo=$(curl -sf --max-time 10 "https://ipinfo.io/json" 2>/dev/null) || true

    if [[ -n "$geo" ]]; then
        local city loc
        city=$(echo "$geo" | jq -r '.city // empty')
        loc=$(echo "$geo" | jq -r '.loc // empty')

        # Paris metro exception: IP geolocation lumps the whole area into Paris
        if [[ -n "$loc" && "$city" != "Paris" && -n "$city" ]]; then
            echo "$geo" > "$GEO_CACHE"
            echo "$geo"
            return
        fi
    fi

    # Fallback to Massy, France
    local fallback="{\"loc\":\"${DEFAULT_LAT},${DEFAULT_LON}\",\"city\":\"${DEFAULT_CITY}\"}"
    echo "$fallback" > "$GEO_CACHE"
    echo "$fallback"
}

# ── Fetch forecast from Open-Meteo ─────────────────────────────────
fetch_forecast() {
    local location lat lon

    location=$(get_location)
    lat=$(echo "$location" | jq -r '.loc' | cut -d, -f1)
    lon=$(echo "$location" | jq -r '.loc' | cut -d, -f2)

    # Fallback if parsing failed
    lat="${lat:-$DEFAULT_LAT}"
    lon="${lon:-$DEFAULT_LON}"

    local url="https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}"
    url+="&current=temperature_2m,apparent_temperature,is_day,weather_code"
    url+="&daily=weather_code,temperature_2m_max,temperature_2m_min,wind_speed_10m_max,relative_humidity_2m_mean,precipitation_probability_max"
    url+="&hourly=temperature_2m,weather_code,precipitation_probability"
    url+="&timezone=auto&forecast_days=5"

    local raw
    raw=$(curl -sf --max-time 15 "$url" 2>/dev/null) || {
        echo '{"ready":false,"error":"API request failed"}' >&2
        return 1
    }

    # ── Build current conditions ────────────────────────────────────
    local cur_temp cur_feels cur_code cur_is_day cur_icon cur_hex cur_desc
    cur_temp=$(echo "$raw" | jq -r '.current.temperature_2m')
    cur_feels=$(echo "$raw" | jq -r '.current.apparent_temperature')
    cur_code=$(echo "$raw" | jq -r '.current.weather_code')
    cur_is_day=$(echo "$raw" | jq -r '.current.is_day')
    cur_icon=$(get_icon "$cur_code" "$cur_is_day")
    cur_hex=$(get_hex "$cur_code" "$cur_is_day")
    cur_desc=$(get_desc "$cur_code")

    # ── Build daily forecast array ──────────────────────────────────
    local days_count
    days_count=$(echo "$raw" | jq '.daily.time | length')

    local forecast="["
    for (( i=0; i<days_count; i++ )); do
        local d_date d_code d_max d_min d_wind d_humidity d_pop d_icon d_hex d_day
        d_date=$(echo "$raw" | jq -r ".daily.time[$i]")
        d_code=$(echo "$raw" | jq -r ".daily.weather_code[$i]")
        d_max=$(echo "$raw" | jq -r ".daily.temperature_2m_max[$i]")
        d_min=$(echo "$raw" | jq -r ".daily.temperature_2m_min[$i]")
        d_wind=$(echo "$raw" | jq -r ".daily.wind_speed_10m_max[$i]")
        d_humidity=$(echo "$raw" | jq -r ".daily.relative_humidity_2m_mean[$i]")
        d_pop=$(echo "$raw" | jq -r ".daily.precipitation_probability_max[$i]")
        d_icon=$(get_icon "$d_code" 1)
        d_hex=$(get_hex "$d_code" 1)
        d_day=$(date -d "$d_date" +%a)

        # ── Hourly slots for this day ───────────────────────────────
        local hourly="["
        local h_start=$(( i * 24 ))
        local h_end=$(( h_start + 24 ))
        local first_hour=1
        for (( h=h_start; h<h_end; h+=3 )); do
            local h_time h_temp h_code h_pop h_icon h_hex
            h_time=$(echo "$raw" | jq -r ".hourly.time[$h]" | cut -dT -f2 | cut -c1-5)
            h_temp=$(echo "$raw" | jq -r ".hourly.temperature_2m[$h]")
            h_code=$(echo "$raw" | jq -r ".hourly.weather_code[$h]")
            h_pop=$(echo "$raw" | jq -r ".hourly.precipitation_probability[$h]")
            h_icon=$(get_icon "$h_code" 1)
            h_hex=$(get_hex "$h_code" 1)

            [[ $first_hour -eq 0 ]] && hourly+=","
            first_hour=0

            hourly+=$(jq -nc \
                --arg time "$h_time" \
                --arg icon "$h_icon" \
                --arg hex "$h_hex" \
                --argjson temp "$h_temp" \
                --argjson pop "${h_pop:-0}" \
                '{time:$time,icon:$icon,hex:$hex,temp:$temp,pop:$pop}')
        done
        hourly+="]"

        [[ $i -gt 0 ]] && forecast+=","

        forecast+=$(jq -nc \
            --arg day "$d_day" \
            --arg date "$d_date" \
            --arg icon "$d_icon" \
            --arg hex "$d_hex" \
            --argjson max "$d_max" \
            --argjson min "$d_min" \
            --argjson wind "$d_wind" \
            --argjson humidity "$d_humidity" \
            --argjson pop "${d_pop:-0}" \
            --argjson hourly "$hourly" \
            '{day:$day,date:$date,icon:$icon,hex:$hex,max:$max,min:$min,wind:$wind,humidity:$humidity,pop:$pop,hourly:$hourly}')
    done
    forecast+="]"

    # ── Write final JSON to cache ───────────────────────────────────
    jq -nc \
        --arg icon "$cur_icon" \
        --argjson temp "$cur_temp" \
        --argjson feels_like "$cur_feels" \
        --arg hex "$cur_hex" \
        --arg desc "$cur_desc" \
        --argjson is_day "$cur_is_day" \
        --argjson forecast "$forecast" \
        '{current:{icon:$icon,temp:$temp,feels_like:$feels_like,hex:$hex,desc:$desc,is_day:$is_day},forecast:$forecast,ready:true}' \
        > "$FORECAST_CACHE"
}

# ── Cache freshness check ──────────────────────────────────────────
is_cache_fresh() {
    [[ -f "$FORECAST_CACHE" ]] || return 1
    local age=$(( $(date +%s) - $(stat -c %Y "$FORECAST_CACHE") ))
    [[ $age -lt $CACHE_MAX_AGE ]]
}

# ── Ensure fresh data ─────────────────────────────────────────────
ensure_data() {
    if ! is_cache_fresh; then
        fetch_forecast
    fi
}

# ── CLI interface ──────────────────────────────────────────────────
case "${1:---bar}" in
    --bar)
        ensure_data
        if [[ -f "$FORECAST_CACHE" ]]; then
            jq -c '.current + {ready: .ready}' "$FORECAST_CACHE"
        else
            echo '{"ready":false}'
        fi
        ;;
    --json)
        ensure_data
        if [[ -f "$FORECAST_CACHE" ]]; then
            cat "$FORECAST_CACHE"
        else
            echo '{"ready":false,"forecast":[]}'
        fi
        ;;
    --update)
        fetch_forecast
        echo "Cache updated: $FORECAST_CACHE"
        ;;
    *)
        echo "Usage: $0 [--bar|--json|--update]" >&2
        exit 1
        ;;
esac
