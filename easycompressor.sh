#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════════════════════
#   EasyCompressor v1.1  -  Smart Video Compression for Termux
#   Optimised for screen recordings | ffmpeg + termux-dialog
# ═══════════════════════════════════════════════════════════════

APP_NAME="EasyCompressor"
VERSION="1.1"
CONFIG_DIR="$HOME/.easycompressor"
CONFIG_FILE="$CONFIG_DIR/config"
HISTORY_FILE="$CONFIG_DIR/history"
LOG_FILE="$CONFIG_DIR/compressions.log"
PROGRESS_PIPE="$CONFIG_DIR/.ffprogress"

# ── Default config values ────────────────────────────────────
DEFAULT_PRESET="moderate"
DEFAULT_RESOLUTION="original"
DEFAULT_AUDIO="128k"
DEFAULT_SUBTITLE="remove"
DEFAULT_SPEED="medium"
DEFAULT_SUFFIX="_compressed"
DEFAULT_DELETE_ORIGINAL="no"
DEFAULT_HW_ACCEL="no"

# ── CRF values per preset (libx265) ─────────────────────────
CRF_HIGH_QUALITY=22
CRF_MODERATE=28
CRF_HIGH_COMPRESSION=34
CRF_SOCIAL_MEDIA=30

# ── ANSI palette ─────────────────────────────────────────────
RED='\033[0;31m';    GREEN='\033[0;32m';  YELLOW='\033[1;33m'
BLUE='\033[0;34m';   CYAN='\033[0;36m';   MAGENTA='\033[0;35m'
BOLD='\033[1m';      DIM='\033[2m';       NC='\033[0m'

# ═══════════════════════════════════════════════════════════════
# CONFIG
# ═══════════════════════════════════════════════════════════════

init_config() {
    mkdir -p "$CONFIG_DIR"
    [[ ! -f "$CONFIG_FILE" ]] && _write_defaults
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
}

_write_defaults() {
    cat > "$CONFIG_FILE" <<EOF
PRESET=$DEFAULT_PRESET
RESOLUTION=$DEFAULT_RESOLUTION
AUDIO=$DEFAULT_AUDIO
SUBTITLE=$DEFAULT_SUBTITLE
SPEED=$DEFAULT_SPEED
SUFFIX=$DEFAULT_SUFFIX
DELETE_ORIGINAL=$DEFAULT_DELETE_ORIGINAL
HW_ACCEL=$DEFAULT_HW_ACCEL
EOF
}

reload_config() { source "$CONFIG_FILE"; }

save_config() {
    cat > "$CONFIG_FILE" <<EOF
PRESET=${PRESET:-$DEFAULT_PRESET}
RESOLUTION=${RESOLUTION:-$DEFAULT_RESOLUTION}
AUDIO=${AUDIO:-$DEFAULT_AUDIO}
SUBTITLE=${SUBTITLE:-$DEFAULT_SUBTITLE}
SPEED=${SPEED:-$DEFAULT_SPEED}
SUFFIX=${SUFFIX:-$DEFAULT_SUFFIX}
DELETE_ORIGINAL=${DELETE_ORIGINAL:-$DEFAULT_DELETE_ORIGINAL}
HW_ACCEL=${HW_ACCEL:-$DEFAULT_HW_ACCEL}
EOF
}

add_to_history() {
    touch "$HISTORY_FILE"
    grep -Fxv "$1" "$HISTORY_FILE" > "${HISTORY_FILE}.tmp" 2>/dev/null || true
    { echo "$1"; cat "${HISTORY_FILE}.tmp"; } > "$HISTORY_FILE" 2>/dev/null || true
    rm -f "${HISTORY_FILE}.tmp"
    head -5 "$HISTORY_FILE" > "${HISTORY_FILE}.tmp" && mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
}

write_log() {
    local status="$1" input="$2" output="$3" before="$4" after="$5" elapsed="$6"
    local saved=$(( before - after ))
    local pct; pct=$(awk "BEGIN{printf \"%d\", $saved*100/$before}" 2>/dev/null || echo "?")
    printf "[%s] %s | %s → %s | saved %d%% | %ds | %s → %s\n" \
        "$(date '+%Y-%m-%d %H:%M')" "$status" \
        "$(bytes_to_human "$before")" "$(bytes_to_human "$after")" \
        "$pct" "$elapsed" \
        "$(basename "$input")" "$(basename "$output")" >> "$LOG_FILE"
}

# ═══════════════════════════════════════════════════════════════
# DEPENDENCY CHECK
# ═══════════════════════════════════════════════════════════════

check_dependencies() {
    local missing=()
    command -v ffmpeg       >/dev/null 2>&1 || missing+=("ffmpeg")
    command -v ffprobe      >/dev/null 2>&1 || missing+=("ffprobe  (part of ffmpeg)")
    command -v termux-dialog>/dev/null 2>&1 || missing+=("termux-api  →  pkg install termux-api")

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}Missing required tools:${NC}"
        for m in "${missing[@]}"; do echo "  • $m"; done
        echo ""
        echo "Quick install:"
        echo "  pkg install ffmpeg termux-api"
        echo "  Also install 'Termux:API' from F-Droid / Play Store"
        exit 1
    fi

    if [[ ! -d "$HOME/storage" ]]; then
        echo -e "${YELLOW}Requesting storage permission...${NC}"
        termux-setup-storage && sleep 2
    fi
}

# ═══════════════════════════════════════════════════════════════
# DIALOG HELPERS
# ═══════════════════════════════════════════════════════════════

_dlg_text_val() {
    # Extract "text" field  -  handle both "text":"val" and "text": "val"
    grep -o '"text" *: *"[^"]*"' | head -1 | sed 's/.*"text" *: *"//;s/"$//'
}

_dlg_index_val() {
    # Extract "index" field  -  handle both "index":N and "index": N
    grep -o '"index" *: *-\?[0-9]*' | head -1 | grep -o '-\?[0-9]*$'
}

# Radio  -  returns selected text; empty string + rc=1 on cancel
dlg_radio() {
    local title="$1" opts="$2"
    local raw; raw=$(termux-dialog radio -t "$title" -v "$opts" 2>/dev/null)
    local idx; idx=$(echo "$raw" | _dlg_index_val)
    [[ -z "$idx" || "$idx" == "-1" ]] && { echo ""; return 1; }
    echo "$raw" | _dlg_text_val
}

# Confirm  -  rc=0 for yes, rc=1 for no/cancel
dlg_confirm() {
    local raw; raw=$(termux-dialog confirm -t "$1" -i "$2" 2>/dev/null)
    echo "$raw" | grep -q '"text" *: *"yes"'
}

# Text input  -  returns typed text; empty + rc=1 on cancel
dlg_text() {
    local raw; raw=$(termux-dialog text -t "$1" -i "$2" 2>/dev/null)
    local idx; idx=$(echo "$raw" | _dlg_index_val)
    [[ -z "$idx" || "$idx" == "-1" ]] && { echo ""; return 1; }
    echo "$raw" | _dlg_text_val
}

# Info popup (OK only)
dlg_info() { termux-dialog confirm -t "$1" -i "$2" 2>/dev/null; }

# ═══════════════════════════════════════════════════════════════
# UTILITIES
# ═══════════════════════════════════════════════════════════════

bytes_to_human() {
    local b="${1:-0}"
    if   [[ "$b" -ge 1073741824 ]]; then awk "BEGIN{printf \"%.2f GB\",$b/1073741824}"
    elif [[ "$b" -ge 1048576    ]]; then awk "BEGIN{printf \"%.1f MB\",$b/1048576}"
    elif [[ "$b" -ge 1024       ]]; then awk "BEGIN{printf \"%.1f KB\",$b/1024}"
    else echo "${b} B"
    fi
}

file_size_bytes() { wc -c < "$1" 2>/dev/null || echo "0"; }

video_duration()   {
    ffprobe -v quiet -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$1" 2>/dev/null | cut -d. -f1
}

video_resolution() {
    ffprobe -v quiet -select_streams v:0 \
        -show_entries stream=width,height \
        -of csv=s=x:p=0 "$1" 2>/dev/null
}

video_bitrate_kbps() {
    local br; br=$(ffprobe -v quiet -show_entries format=bit_rate \
        -of default=noprint_wrappers=1:nokey=1 "$1" 2>/dev/null)
    awk "BEGIN{printf \"%d\",${br:-0}/1000}"
}

has_encoder() { ffmpeg -encoders 2>/dev/null | grep -q " $1 "; }

choose_encoder() {
    if [[ "${HW_ACCEL:-no}" == "yes" ]] && has_encoder "h264_mediacodec"; then
        echo "h264_mediacodec"
    elif has_encoder "libx265"; then
        echo "libx265"
    else
        echo "libx264"
    fi
}

calc_bitrate_for_target() {
    local target_mb="$1" dur_sec="$2" audio_kbps="${3:-128}"
    awk "BEGIN{
        total = ($target_mb * 8192 * 0.95) / $dur_sec
        v = total - $audio_kbps
        printf \"%d\", (v < 50 ? 50 : v)
    }"
}

notify() {
    termux-notification --title "$APP_NAME" --content "$1" --id 42 2>/dev/null || true
}

sec_to_hms() {
    local s="$1"
    printf "%02d:%02d:%02d" $(( s/3600 )) $(( (s%3600)/60 )) $(( s%60 ))
}

draw_bar() {
    local pct="$1" width="${2:-40}"
    local filled=$(( pct * width / 100 ))
    local bar=""
    local i
    for (( i=0; i<filled; i++ ));       do bar+="█"; done
    for (( i=filled; i<width; i++ ));   do bar+="░"; done
    echo "$bar"
}

# ═══════════════════════════════════════════════════════════════
# REAL-TIME PROGRESS DISPLAY
# ═══════════════════════════════════════════════════════════════

# Run ffmpeg with live progress bar.
# Usage: run_ffmpeg_progress <duration_sec> <ffmpeg args...>
# Returns ffmpeg exit code.
run_ffmpeg_progress() {
    local duration="$1"; shift

    rm -f "$PROGRESS_PIPE"

    # Run ffmpeg in background, writing progress to pipe file
    ffmpeg "$@" -progress "$PROGRESS_PIPE" -nostats 2>&1 | \
        grep --line-buffered -E "^(error|Error)" | \
        sed "s/^/${RED}/" &
    local ffpid=$!

    local t_start; t_start=$(date +%s)

    echo ""
    while kill -0 "$ffpid" 2>/dev/null; do
        sleep 0.8

        local out_ms frame speed
        if [[ -f "$PROGRESS_PIPE" ]]; then
            out_ms=$(grep "^out_time_ms=" "$PROGRESS_PIPE" 2>/dev/null | tail -1 | cut -d= -f2)
            frame=$(grep  "^frame="       "$PROGRESS_PIPE" 2>/dev/null | tail -1 | cut -d= -f2)
            speed=$(grep  "^speed="       "$PROGRESS_PIPE" 2>/dev/null | tail -1 | cut -d= -f2 | tr -d ' ')
        fi

        local pct=0
        if [[ -n "$out_ms" && "$out_ms" -gt 0 && "$duration" -gt 0 ]] 2>/dev/null; then
            pct=$(( out_ms / 1000 * 100 / duration ))
            [[ $pct -gt 100 ]] && pct=100
        fi

        local elapsed=$(( $(date +%s) - t_start ))
        local eta_str="calculating..."
        if [[ $pct -gt 2 && $pct -lt 100 ]]; then
            local eta_sec=$(( elapsed * (100 - pct) / pct ))
            eta_str="ETA $(sec_to_hms "$eta_sec")"
        fi

        local bar; bar=$(draw_bar "$pct" 35)
        printf "\r  ${CYAN}[%s]${NC} ${BOLD}%3d%%${NC}  spd:${YELLOW}%-6s${NC}  frm:%-6s  %s  " \
            "$bar" "$pct" "${speed:-?x}" "${frame:-?}" "$eta_str"
    done

    wait "$ffpid"
    local rc=$?

    printf "\r%80s\r" ""   # clear progress line
    rm -f "$PROGRESS_PIPE"
    return $rc
}

# ═══════════════════════════════════════════════════════════════
# FILE SELECTION
# ═══════════════════════════════════════════════════════════════

_label_with_size() {
    local f="$1"
    local sz; sz=$(file_size_bytes "$f")
    local h; h=$(bytes_to_human "$sz")
    echo "$(basename "$f")  [${h}]"
}

_find_videos() {
    local dir="$1" depth="${2:-2}"
    find "$dir" -maxdepth "$depth" -type f \
        \( -iname "*.mp4" -o -iname "*.mov" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.webm" \) \
        2>/dev/null | sort
}

select_from_dir() {
    local dir="$1"
    local -a labels paths

    while IFS= read -r f; do
        labels+=("$(_label_with_size "$f")")
        paths+=("$f")
    done < <(_find_videos "$dir")

    [[ ${#labels[@]} -eq 0 ]] && {
        dlg_info "No Videos" "No video files found in:\n$(basename "$dir")"
        return 1
    }

    local opts; opts=$(printf "%s," "${labels[@]}"); opts="${opts%,}"
    local chosen; chosen=$(dlg_radio "Browse  -  $(basename "$dir")" "$opts") || return 1
    [[ -z "$chosen" ]] && return 1

    for i in "${!labels[@]}"; do
        [[ "${labels[$i]}" == "$chosen" ]] && { echo "${paths[$i]}"; return 0; }
    done
    return 1
}

select_from_history() {
    [[ ! -s "$HISTORY_FILE" ]] && { dlg_info "No History" "No recent files recorded."; return 1; }

    local -a labels paths
    while IFS= read -r p; do
        [[ -f "$p" ]] && { labels+=("$(_label_with_size "$p")"); paths+=("$p"); }
    done < "$HISTORY_FILE"

    [[ ${#labels[@]} -eq 0 ]] && { dlg_info "No History" "Recent files no longer exist."; return 1; }

    local opts; opts=$(printf "%s," "${labels[@]}"); opts="${opts%,}"
    local chosen; chosen=$(dlg_radio "Recent Files" "$opts") || return 1
    [[ -z "$chosen" ]] && return 1

    for i in "${!labels[@]}"; do
        [[ "${labels[$i]}" == "$chosen" ]] && { echo "${paths[$i]}"; return 0; }
    done
    return 1
}

pick_video_file() {
    local -a loc_labels loc_paths

    for d in \
        "/sdcard/DCIM/Screen recordings" \
        "/sdcard/DCIM" "/sdcard/Movies" \
        "/sdcard/Download" "/sdcard/Downloads" \
        "/sdcard/Recordings" \
        "$HOME/storage/dcim" \
        "$HOME/storage/movies" \
        "$HOME/storage/downloads"
    do
        [[ -d "$d" ]] && { loc_labels+=("Browse: $(basename "$d")"); loc_paths+=("$d"); }
    done

    local menu="Enter path manually"
    [[ -s "$HISTORY_FILE" ]] && menu+=",Recent files  (last 5)"
    for l in "${loc_labels[@]}"; do menu+=",${l}"; done

    local choice; choice=$(dlg_radio "Select Video  -  $APP_NAME" "$menu") || return 1
    [[ -z "$choice" ]] && return 1

    case "$choice" in
        "Enter path manually")
            local p; p=$(dlg_text "Full Video Path" "/sdcard/Movies/video.mp4") || return 1
            echo "$p"
            ;;
        "Recent files"*)
            select_from_history
            ;;
        "Browse: "*)
            local lbl="${choice#Browse: }"
            for i in "${!loc_labels[@]}"; do
                [[ "${loc_labels[$i]}" == "Browse: $lbl" ]] && {
                    select_from_dir "${loc_paths[$i]}"
                    return $?
                }
            done
            ;;
    esac
}

pick_folder() {
    local p; p=$(dlg_text "Folder Path" "/sdcard/Movies") || return 1
    [[ -d "$p" ]] || { dlg_info "Not Found" "Folder does not exist:\n$p"; return 1; }
    echo "$p"
}

# ═══════════════════════════════════════════════════════════════
# SETTINGS WIZARD
# All results go into WIZARD_* globals.
# ═══════════════════════════════════════════════════════════════

run_wizard() {
    # ── 1. Preset ────────────────────────────────────────────
    local p; p=$(dlg_radio "Step 1/7  -  Compression Preset" \
"High Quality  (CRF 22  -  best visuals),\
Moderate  (CRF 28  -  recommended),\
High Compression  (CRF 34  -  max size savings),\
Social Media  (CRF 30  -  under 50MB target),\
Custom CRF  (manual control)") || return 1
    [[ -z "$p" ]] && return 1

    case "$p" in
        "High Quality"*)     WIZARD_PRESET="high_quality" ;;
        "Moderate"*)         WIZARD_PRESET="moderate" ;;
        "High Compression"*) WIZARD_PRESET="high_compression" ;;
        "Social Media"*)     WIZARD_PRESET="social_media" ;;
        "Custom CRF"*)       WIZARD_PRESET="custom" ;;
    esac

    WIZARD_CRF=""
    if [[ "$WIZARD_PRESET" == "custom" ]]; then
        WIZARD_CRF=$(dlg_text "Custom CRF" \
            "Range 18-51 | Lower = better quality | 28 is typical") || return 1
        [[ -z "$WIZARD_CRF" ]] && WIZARD_CRF=28
    fi

    # ── 2. Resolution ────────────────────────────────────────
    local r; r=$(dlg_radio "Step 2/7  -  Output Resolution" \
"Keep Original,\
1080p   -  Full HD,\
720p   -  Recommended for screen recordings,\
480p   -  Aggressive (smallest file)") || return 1
    [[ -z "$r" ]] && return 1

    case "$r" in
        "Keep Original") WIZARD_RESOLUTION="original" ;;
        "1080p"*)        WIZARD_RESOLUTION="1080p" ;;
        "720p"*)         WIZARD_RESOLUTION="720p" ;;
        "480p"*)         WIZARD_RESOLUTION="480p" ;;
    esac

    # ── 3. Target file size ───────────────────────────────────
    local sz; sz=$(dlg_radio "Step 3/7  -  Target File Size" \
"No limit,\
50 MB  (WhatsApp / Telegram),\
100 MB,\
200 MB,\
Custom size") || return 1
    [[ -z "$sz" ]] && return 1

    case "$sz" in
        "No limit")    WIZARD_TARGET_MB=0 ;;
        "50 MB"*)      WIZARD_TARGET_MB=50 ;;
        "100 MB")      WIZARD_TARGET_MB=100 ;;
        "200 MB")      WIZARD_TARGET_MB=200 ;;
        "Custom size")
            local c; c=$(dlg_text "Target Size (MB)" "e.g. 75") || return 1
            WIZARD_TARGET_MB="${c:-0}"
            ;;
    esac

    # ── 4. Audio ─────────────────────────────────────────────
    local au; au=$(dlg_radio "Step 4/7  -  Audio" \
"Keep Original,\
128k AAC  (recommended),\
96k AAC  (smaller),\
Mute   -  remove all audio") || return 1
    [[ -z "$au" ]] && return 1

    case "$au" in
        "Keep Original") WIZARD_AUDIO="copy" ;;
        "128k"*)         WIZARD_AUDIO="128k" ;;
        "96k"*)          WIZARD_AUDIO="96k" ;;
        "Mute"*)         WIZARD_AUDIO="mute" ;;
    esac

    # ── 5. Subtitles ─────────────────────────────────────────
    local sub; sub=$(dlg_radio "Step 5/7  -  Subtitles" \
"Remove subtitles,\
Copy subtitles  (if present),\
Burn into video  (hardcode)") || return 1
    [[ -z "$sub" ]] && return 1

    case "$sub" in
        "Remove"*)  WIZARD_SUBTITLE="remove" ;;
        "Copy"*)    WIZARD_SUBTITLE="copy" ;;
        "Burn"*)    WIZARD_SUBTITLE="burn" ;;
    esac

    # ── 6. Encoder speed ─────────────────────────────────────
    local spd; spd=$(dlg_radio "Step 6/7  -  Encoder Speed" \
"ultrafast   -  fastest / lower quality,\
veryfast,\
fast,\
medium   -  balanced,\
slow,\
veryslow   -  best quality / very slow") || return 1
    [[ -z "$spd" ]] && return 1
    WIZARD_SPEED=$(echo "$spd" | awk '{print $1}')

    # ── 7. Output options ─────────────────────────────────────
    local nm; nm=$(dlg_radio "Step 7/7  -  Output File" \
"Add '_compressed' suffix,\
Custom suffix,\
Same name  (overwrite original)") || return 1
    [[ -z "$nm" ]] && return 1

    case "$nm" in
        "Add '_compressed'"*)  WIZARD_SUFFIX="_compressed" ;;
        "Same name"*)          WIZARD_SUFFIX="" ;;
        "Custom suffix")
            WIZARD_SUFFIX=$(dlg_text "Enter Suffix" "_small") || { WIZARD_SUFFIX="_compressed"; }
            ;;
    esac

    WIZARD_DELETE_ORIGINAL="no"
    dlg_confirm "Delete Original?" \
        "Remove the ORIGINAL file after successful compression?\n\nThis cannot be undone." \
        && WIZARD_DELETE_ORIGINAL="yes"

    return 0
}

# ═══════════════════════════════════════════════════════════════
# CONFIRMATION SCREEN
# ═══════════════════════════════════════════════════════════════

show_confirmation() {
    local input="$1" output="$2"

    local fsz; fsz=$(file_size_bytes "$input")
    local dur;  dur=$(video_duration "$input")
    local res;  res=$(video_resolution "$input")
    local dur_m=$(( dur / 60 )) dur_s=$(( dur % 60 ))

    local est_label preset_label
    if [[ "${WIZARD_TARGET_MB:-0}" -gt 0 ]]; then
        est_label="~${WIZARD_TARGET_MB} MB  (2-pass target mode)"
    else
        local ratios; declare -A ratios=(
            [high_quality]=55 [moderate]=30
            [high_compression]=12 [social_media]=18 [custom]=30
        )
        local ratio="${ratios[$WIZARD_PRESET]:-30}"
        local em; em=$(awk "BEGIN{printf \"%d\",$fsz*$ratio/100/1048576}")
        est_label="~${em} MB  (estimate  -  actual varies)"
    fi

    case "$WIZARD_PRESET" in
        high_quality)     preset_label="High Quality  (CRF $CRF_HIGH_QUALITY)" ;;
        moderate)         preset_label="Moderate  (CRF $CRF_MODERATE)" ;;
        high_compression) preset_label="High Compression  (CRF $CRF_HIGH_COMPRESSION)" ;;
        social_media)     preset_label="Social Media  (CRF $CRF_SOCIAL_MEDIA)" ;;
        custom)           preset_label="Custom  (CRF ${WIZARD_CRF})" ;;
    esac

    local encoder; encoder=$(choose_encoder)

    dlg_confirm "Ready to Compress?" \
"--- INPUT ---
  File:       $(basename "$input")
  Size:       $(bytes_to_human "$fsz")
  Duration:   ${dur_m}m ${dur_s}s
  Resolution: $res

--- SETTINGS ---
  Preset:     $preset_label
  Resolution: $WIZARD_RESOLUTION
  Target:     ${WIZARD_TARGET_MB:-0} MB limit
  Audio:      $WIZARD_AUDIO
  Subtitles:  $WIZARD_SUBTITLE
  Speed:      $WIZARD_SPEED
  Encoder:    $encoder

--- OUTPUT ---
  File:       $(basename "$output")
  Est. size:  $est_label
  Delete src: $WIZARD_DELETE_ORIGINAL

Start compression?"
}

# ═══════════════════════════════════════════════════════════════
# VIDEO FILTER BUILDER
# ═══════════════════════════════════════════════════════════════

build_vf() {
    local input="$1"
    local -a filters

    case "$WIZARD_RESOLUTION" in
        "1080p") filters+=("scale=-2:1080") ;;
        "720p")  filters+=("scale=-2:720") ;;
        "480p")  filters+=("scale=-2:480") ;;
    esac

    if [[ "$WIZARD_SUBTITLE" == "burn" ]]; then
        local esc="${input//\'/\'\\\'\'}"
        filters+=("subtitles='${esc}'")
    fi

    if [[ ${#filters[@]} -gt 0 ]]; then
        local IFS=','; echo "${filters[*]}"
    else
        echo ""
    fi
}

# ═══════════════════════════════════════════════════════════════
# CORE COMPRESSION ENGINE
# ═══════════════════════════════════════════════════════════════

compress_video() {
    local input="$1" output="$2" time_limit="${3:-}"

    local in_size; in_size=$(file_size_bytes "$input")
    local duration; duration=$(video_duration "$input")
    local encoder;  encoder=$(choose_encoder)
    local vf;       vf=$(build_vf "$input")

    # Effective duration for bitrate calc (quick-test or full)
    local eff_dur="${time_limit:-$duration}"

    echo ""
    echo -e "  ${BOLD}${CYAN}>> Compressing...${NC}"
    echo -e "  Encoder : ${YELLOW}${encoder}${NC}"
    echo -e "  Input   : $(basename "$input")  ($(bytes_to_human "$in_size"))"
    echo -e "  Output  : $(basename "$output")"
    [[ -n "$time_limit" ]] && echo -e "  ${YELLOW}Quick Test mode  -  first ${time_limit}s only${NC}"
    echo ""

    mkdir -p "$(dirname "$output")"
    notify "Compressing $(basename "$input")..."

    local t_start; t_start=$(date +%s)
    local rc=0

    # ── Audio args ────────────────────────────────────────────
    local -a audio_args
    case "$WIZARD_AUDIO" in
        copy) audio_args=(-c:a copy) ;;
        96k)  audio_args=(-c:a aac -b:a 96k) ;;
        mute) audio_args=(-an) ;;
        *)    audio_args=(-c:a aac -b:a 128k) ;;
    esac

    # ── Subtitle args ─────────────────────────────────────────
    local -a sub_args=(-sn)
    [[ "$WIZARD_SUBTITLE" == "copy" ]] && sub_args=(-c:s copy)

    # ── CRF value ─────────────────────────────────────────────
    local crf
    case "$WIZARD_PRESET" in
        high_quality)     crf=$CRF_HIGH_QUALITY ;;
        moderate)         crf=$CRF_MODERATE ;;
        high_compression) crf=$CRF_HIGH_COMPRESSION ;;
        social_media)     crf=$CRF_SOCIAL_MEDIA ;;
        custom)           crf="${WIZARD_CRF:-28}" ;;
        *)                crf=$CRF_MODERATE ;;
    esac

    local speed="${WIZARD_SPEED:-medium}"

    # ════════════════════════════════════════════════════════
    if [[ "${WIZARD_TARGET_MB:-0}" -gt 0 ]]; then
        # ── TWO-PASS TARGET-SIZE ENCODING ──────────────────
        local audio_kbps=128
        [[ "$WIZARD_AUDIO" == "96k"  ]] && audio_kbps=96
        [[ "$WIZARD_AUDIO" == "mute" ]] && audio_kbps=0

        local vbr; vbr=$(calc_bitrate_for_target "$WIZARD_TARGET_MB" "$eff_dur" "$audio_kbps")

        echo -e "  ${BLUE}[Pass 1/2]${NC} Analysis..."

        if [[ "$encoder" == "libx265" ]]; then
            run_ffmpeg_progress "$eff_dur" \
                -y ${time_limit:+-t "$time_limit"} -i "$input" \
                -c:v libx265 -b:v "${vbr}k" -preset "$speed" \
                -x265-params "pass=1:log-level=error" \
                -an -f null /dev/null
        else
            run_ffmpeg_progress "$eff_dur" \
                -y ${time_limit:+-t "$time_limit"} -i "$input" \
                -c:v "$encoder" -b:v "${vbr}k" -preset "$speed" \
                -pass 1 -passlogfile "$CONFIG_DIR/ffmpeg2pass" \
                -an -f null /dev/null
        fi

        echo -e "  ${BLUE}[Pass 2/2]${NC} Encoding..."

        if [[ "$encoder" == "libx265" ]]; then
            run_ffmpeg_progress "$eff_dur" \
                -y ${time_limit:+-t "$time_limit"} -i "$input" \
                -c:v libx265 -b:v "${vbr}k" -preset "$speed" \
                -x265-params "pass=2" \
                ${vf:+-vf "$vf"} \
                "${audio_args[@]}" "${sub_args[@]}" \
                "$output"
            rc=$?
        else
            run_ffmpeg_progress "$eff_dur" \
                -y ${time_limit:+-t "$time_limit"} -i "$input" \
                -c:v "$encoder" -b:v "${vbr}k" -preset "$speed" \
                -pass 2 -passlogfile "$CONFIG_DIR/ffmpeg2pass" \
                ${vf:+-vf "$vf"} \
                "${audio_args[@]}" "${sub_args[@]}" \
                "$output"
            rc=$?
        fi

        rm -f "$CONFIG_DIR"/ffmpeg2pass-*.log* 2>/dev/null || true

    else
        # ── SINGLE-PASS CRF ENCODING ──────────────────────
        run_ffmpeg_progress "$duration" \
            -y ${time_limit:+-t "$time_limit"} -i "$input" \
            -c:v "$encoder" -crf "$crf" -preset "$speed" \
            ${vf:+-vf "$vf"} \
            "${audio_args[@]}" "${sub_args[@]}" \
            "$output"
        rc=$?
    fi
    # ════════════════════════════════════════════════════════

    local t_end; t_end=$(date +%s)
    local elapsed=$(( t_end - t_start ))
    local e_min=$(( elapsed / 60 )) e_sec=$(( elapsed % 60 ))

    if [[ $rc -eq 0 && -f "$output" ]]; then
        local out_size; out_size=$(file_size_bytes "$output")
        local saved=$(( in_size - out_size ))
        local pct; pct=$(awk "BEGIN{printf \"%d\",$saved*100/$in_size}")

        echo -e ""
        echo -e "  ${GREEN}${BOLD}DONE!${NC}  ${e_min}m ${e_sec}s"
        echo -e "  ┌──────────────────────────────────"
        echo -e "  │  Before : $(bytes_to_human "$in_size")"
        echo -e "  │  After  : $(bytes_to_human "$out_size")"
        echo -e "  │  Saved  : ${GREEN}$(bytes_to_human "$saved") (${pct}%)${NC}"
        echo -e "  └──────────────────────────────────"
        echo ""

        notify "Done! $(basename "$input") - saved ${pct}% ($(bytes_to_human "$out_size"))"

        write_log "OK" "$input" "$output" "$in_size" "$out_size" "$elapsed"

        dlg_info "Compression Complete!" \
"Time:      ${e_min}m ${e_sec}s
Before:    $(bytes_to_human "$in_size")
After:     $(bytes_to_human "$out_size")
Saved:     $(bytes_to_human "$saved")  (${pct}% reduction)

Output file:
$(basename "$output")"

        add_to_history "$output"

        if [[ "$WIZARD_DELETE_ORIGINAL" == "yes" ]]; then
            rm -f "$input"
            echo -e "  ${YELLOW}Original deleted.${NC}"
        fi

        return 0
    else
        echo -e "  ${RED}${BOLD}FAILED (exit ${rc})${NC}"
        notify "Failed: $(basename "$input")"
        write_log "FAIL" "$input" "$output" "$in_size" "0" "$elapsed"
        rm -f "$output"
        dlg_info "Failed" \
"Compression failed (exit code $rc).

Common causes:
• Input file is corrupted
• Not enough free storage
• Format not supported
• Bitrate target too low

Check the log:
$LOG_FILE"
        return 1
    fi
}

# ─── Build output path from input + wizard settings ──────────
make_output_path() {
    local input="$1"
    local dir; dir=$(dirname "$input")
    local base; base=$(basename "$input")
    local name="${base%.*}" ext="${base##*.}"
    echo "${dir}/${name}${WIZARD_SUFFIX:-_compressed}.${ext}"
}

# ═══════════════════════════════════════════════════════════════
# MODES
# ═══════════════════════════════════════════════════════════════

mode_info() {
    local input; input=$(pick_video_file) || return
    [[ -z "$input" ]] && return
    [[ ! -f "$input" ]] && { dlg_info "Not Found" "File not found:\n$input"; return; }

    local sz; sz=$(file_size_bytes "$input")
    local dur; dur=$(video_duration "$input")
    local res; res=$(video_resolution "$input")
    local br;  br=$(video_bitrate_kbps "$input")
    local dm=$(( dur / 60 )) ds=$(( dur % 60 ))
    local enc; enc=$(has_encoder "libx265" && echo "libx265" || echo "libx264")

    dlg_info "Video Info" \
"--- FILE ---
  Name:       $(basename "$input")
  Size:       $(bytes_to_human "$sz")
  Path:       $input

--- STREAMS ---
  Resolution: $res
  Duration:   ${dm}m ${ds}s
  Bitrate:    ${br} kbps

--- SYSTEM ---
  Encoder:    $(choose_encoder)
  Config:     $CONFIG_DIR"
}

mode_single() {
    local input; input=$(pick_video_file) || return
    [[ -z "$input" ]] && return
    [[ ! -f "$input" ]] && { dlg_info "Not Found" "File not found:\n$input"; return; }

    add_to_history "$input"
    run_wizard || return

    local output; output=$(make_output_path "$input")
    show_confirmation "$input" "$output" || return

    compress_video "$input" "$output"
}

mode_quick_test() {
    local input; input=$(pick_video_file) || return
    [[ -z "$input" ]] && return
    [[ ! -f "$input" ]] && { dlg_info "Not Found" "File not found:\n$input"; return; }

    run_wizard || return

    local dir; dir=$(dirname "$input")
    local base; base=$(basename "$input")
    local output="${dir}/${base%.*}_test45s.${base##*.}"

    dlg_confirm "Quick Test" \
"Compress FIRST 45 SECONDS only.

Purpose: test your settings before
running full compression.

Output: $(basename "$output")

Proceed?" || return

    compress_video "$input" "$output" "45"
}

mode_batch() {
    local folder; folder=$(pick_folder) || return
    [[ -z "$folder" ]] && return

    local -a videos=()
    while IFS= read -r f; do videos+=("$f"); done < <(
        find "$folder" -maxdepth 1 -type f \
            \( -iname "*.mp4" -o -iname "*.mov" -o -iname "*.mkv" \
               -o -iname "*.avi" -o -iname "*.webm" \) \
            2>/dev/null | sort
    )

    local count="${#videos[@]}"
    [[ $count -eq 0 ]] && {
        dlg_info "No Videos" "No video files found in:\n$folder"
        return
    }

    local list=""
    for v in "${videos[@]}"; do
        list+="  • $(basename "$v")  [$(bytes_to_human "$(file_size_bytes "$v")")]\n"
    done

    run_wizard || return

    dlg_confirm "Batch Compress  -  $count videos" \
"Videos found:\n${list}
Settings will apply to all.
Skip already-compressed files: YES

Start batch?" || return

    local ok=0 fail=0 skip=0 total_saved=0

    for vid in "${videos[@]}"; do
        local suffix="${WIZARD_SUFFIX:-_compressed}"
        local base; base=$(basename "$vid")
        local out; out=$(make_output_path "$vid")

        # Skip if output already exists
        if [[ -f "$out" ]]; then
            echo -e "  ${DIM}[skip] already exists: $(basename "$out")${NC}"
            (( skip++ ))
            continue
        fi

        echo ""
        echo -e "  ${BOLD}[$((ok+fail+skip+1))/$count]${NC}  $(basename "$vid")"
        local before; before=$(file_size_bytes "$vid")

        if compress_video "$vid" "$out"; then
            (( ok++ ))
            local after; after=$(file_size_bytes "$out")
            total_saved=$(( total_saved + before - after ))
        else
            (( fail++ ))
        fi
    done

    local msg="Total:    $count
Success:  $ok
Skipped:  $skip
Failed:   $fail
Saved:    $(bytes_to_human "$total_saved")"

    dlg_info "Batch Complete" "$msg"
    notify "Batch done! $ok/$count videos. Saved $(bytes_to_human "$total_saved")"
}

mode_history() {
    [[ ! -s "$LOG_FILE" ]] && { dlg_info "No History" "No compressions logged yet."; return; }

    local lines; lines=$(tail -10 "$LOG_FILE" | tac)
    dlg_info "Last 10 Compressions" "$lines"
}

mode_settings() {
    local choice; choice=$(dlg_radio "Settings" \
"View current config,\
Save current as defaults,\
Reset to factory defaults,\
Toggle hardware encoder,\
Compression history,\
About $APP_NAME") || return
    [[ -z "$choice" ]] && return

    case "$choice" in
        "View current config")
            reload_config
            dlg_info "Current Config" \
"Preset:          ${PRESET:-moderate}
Resolution:      ${RESOLUTION:-original}
Audio:           ${AUDIO:-128k}
Subtitles:       ${SUBTITLE:-remove}
Speed:           ${SPEED:-medium}
Suffix:          ${SUFFIX:-_compressed}
Delete original: ${DELETE_ORIGINAL:-no}
HW accel:        ${HW_ACCEL:-no}

Encoder:         $(choose_encoder)
Config file:     $CONFIG_FILE"
            ;;

        "Save current as defaults")
            dlg_confirm "Save Defaults?" \
                "Save current wizard settings as your permanent defaults?" || return
            # Wizard settings aren't saved unless user explicitly saves; this
            # saves whatever is currently in CONFIG_FILE (already written by wizard)
            dlg_info "Saved" "Current settings saved as defaults."
            ;;

        "Reset to factory defaults")
            dlg_confirm "Reset?" "Restore ALL settings to factory defaults?" || return
            _write_defaults
            source "$CONFIG_FILE"
            dlg_info "Done" "Settings restored to factory defaults."
            ;;

        "Toggle hardware encoder")
            reload_config
            local new_val="yes"; [[ "${HW_ACCEL:-no}" == "yes" ]] && new_val="no"

            if [[ "$new_val" == "yes" ]] && ! has_encoder "h264_mediacodec"; then
                dlg_info "Not Available" \
"h264_mediacodec encoder is not available on this device.

Hardware acceleration requires a device with
MediaCodec H.264 support.

Staying on software encoder."
                return
            fi

            HW_ACCEL="$new_val"
            sed -i "s/^HW_ACCEL=.*/HW_ACCEL=$new_val/" "$CONFIG_FILE"
            dlg_info "Done" "Hardware encoder: $new_val\nActive encoder: $(choose_encoder)"
            ;;

        "Compression history")
            mode_history
            ;;

        "About $APP_NAME")
            dlg_info "About $APP_NAME v$VERSION" \
"$APP_NAME  -  Smart Video Compression
Version $VERSION

Built for Termux on Android.
Optimised for screen recordings.

Technology:
  • Encoders: libx265 / libx264 / h264_mediacodec
  • Interface: termux-dialog
  • Notifications: termux-api

Features:
  • Real-time progress bar
  • Target file size (2-pass)
  • Batch folder compression
  • Quick 45s preview test
  • Compression history log
  • Hardware encoder support

Config dir:
  $CONFIG_DIR"
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════
# MAIN MENU
# ═══════════════════════════════════════════════════════════════

main_menu() {
    while true; do
        local choice; choice=$(dlg_radio "$APP_NAME v$VERSION" \
"Single Video,Batch Folder,Quick Test (45s preview),Video Info,Settings,Exit") || {
            dlg_confirm "Exit" "Exit $APP_NAME?" && break
            continue
        }
        [[ -z "$choice" ]] && { dlg_confirm "Exit" "Exit $APP_NAME?" && break; continue; }

        case "$choice" in
            "Single Video")      mode_single ;;
            "Batch Folder")      mode_batch ;;
            "Quick Test"*)       mode_quick_test ;;
            "Video Info")        mode_info ;;
            "Settings")          mode_settings ;;
            "Exit")              break ;;
        esac
    done
}

# ═══════════════════════════════════════════════════════════════
# ENTRY POINT
# ═══════════════════════════════════════════════════════════════

clear
echo -e "${BOLD}${CYAN}"
echo "  ╔══════════════════════════════════╗"
echo "  ║   EasyCompressor  v${VERSION}        ║"
echo "  ║   Smart Video Compression        ║"
echo "  ╚══════════════════════════════════╝"
echo -e "${NC}"

check_dependencies
init_config
main_menu

echo -e "\n  ${GREEN}Goodbye!${NC}\n"
