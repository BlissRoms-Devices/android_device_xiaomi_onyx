#!/vendor/bin/sh
#
# MiSyS runs as uid camera under init's hardcoded umask 077, so the MIVI
# watermark templates it writes to /data/vendor/camera/watermarks land as
# 0600/2700. The camera provider runs as cameraserver and is only in the
# camera *group*, so it cannot read them and MiuiCamera silently drops the
# watermark from the saved JPEG (no avc denial - pure DAC).
#
# MiSyS also counts up: every capture asks for the next mivi_<N>.json, and
# open(O_CREAT|O_TRUNC) only sets the mode on a brand-new name, so a chmod
# always lands after the shot it was meant to save. Pre-creating the next AHEAD
# names makes every capture truncate a file that is already readable; the
# per-directory .window marker keeps that window tied to MiSyS's sequence
# instead of growing on every pass.
#
# Runs as uid camera on purpose: the owner may always chmod its own files, so no
# CAP_FOWNER/CAP_CHOWN is needed (a vendor domain may not be granted those).
#
WM=/data/vendor/camera/watermarks
FN=/data/vendor/camera/fonts
AHEAD=${AHEAD:-16}
CAP=${CAP:-128}

umask 022
[ -d "$WM" ] || exit 0

for d in "$WM" "$FN"; do
    [ -d "$d" ] || continue
    find "$d" -type d ! -perm -o+rx -exec chmod 2755 {} + 2>/dev/null
    find "$d" -type f ! -perm -o+r -exec chmod 0644 {} + 2>/dev/null
done

for dir in "$WM"/*/*/; do
    [ -d "$dir" ] || continue

    max=0
    for f in "$dir"mivi_*.json; do
        [ -e "$f" ] || continue
        b=${f%.json}
        b=${b##*/}
        n=${b#mivi_}
        case "$n" in ''|*[!0-9]*) continue ;; esac
        [ "$n" -gt "$max" ] && max=$n
    done
    [ "$max" -gt 0 ] || continue

    win="${dir}.window"
    ref=$(cat "$win" 2>/dev/null)
    case "$ref" in ''|*[!0-9]*) ref=0 ;; esac
    [ "$max" -le "$ref" ] && continue

    hi=$((max + AHEAD))
    [ "$hi" -gt "$CAP" ] && hi=$CAP
    [ "$hi" -le "$ref" ] && continue
    src="${dir}mivi_${max}.json"
    i=$((max + 1))
    while [ "$i" -le "$hi" ]; do
        if [ ! -e "${dir}mivi_${i}.json" ]; then
            if cp -f "$src" "${dir}mivi_${i}.json" 2>/dev/null; then
                chmod 0644 "${dir}mivi_${i}.json"
            fi
        fi
        i=$((i + 1))
    done
    printf '%s\n' "$hi" > "$win" 2>/dev/null
    chmod 0644 "$win" 2>/dev/null
done

exit 0
