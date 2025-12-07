#!/bin/bash
# =========================================================
# Albion Online PCAP Extractor
# 1) Generate clean game traffic index only
# 2) Split full detailed dump into chunks only
# 3) Do both (recommended & default)
# =========================================================

CHUNK_SIZE=500
IP_FILTER="ip.addr == 5.188.125.56 or ip.addr == 5.188.125.14 or ip.addr == 5.188.125.47"

PCAP_FILE="${1:-/tmp/albion.pcapng}"

# Ask for file if not exists
if [ ! -f "$PCAP_FILE" ]; then
    echo -n "Enter full path to the .pcapng file (or press ENTER for /tmp/albion.pcapng): "
    read -r ANSWER
    PCAP_FILE="${ANSWER:-/tmp/albion.pcapng}"
fi

if [ ! -f "$PCAP_FILE" ]; then
    echo "Error: File not found → $PCAP_FILE"
    exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
OUT_DIR="$SCRIPT_DIR/output"
mkdir -p "$OUT_DIR"
BASE_NAME=$(basename "$PCAP_FILE" .pcapng)

clear
echo "════════════════════════════════════════════════════"
echo "       ALBION ONLINE PCAP EXTRACTOR"
echo "       File: $(basename "$PCAP_FILE")"
echo "       Packets per chunk: $CHUNK_SIZE"
echo "════════════════════════════════════════════════════"
echo
echo "What do you want to do?"
echo "   1) Generate only the clean game traffic index"
echo "   2) Split only the full detailed dump ($CHUNK_SIZE packets per file)"
echo "   3) Do both – index + split (RECOMMENDED & default)"
echo
read -p "Choose 1, 2 or 3 (default = 3): " CHOICE
CHOICE="${CHOICE:-3}"

# =========================================================
# Option 1 or 3 → Clean game traffic index
# =========================================================
if [[ "$CHOICE" == "1" || "$CHOICE" == "3" ]]; then
    echo
    echo "Generating clean game traffic index..."
    tshark -r "$PCAP_FILE" -Y "$IP_FILTER" > "$OUT_DIR/${BASE_NAME}_game_traffic_index.txt"
    LINES=$(wc -l < "$OUT_DIR/${BASE_NAME}_game_traffic_index.txt")
    echo "→ ${BASE_NAME}_game_traffic_index.txt created ($LINES lines)"
fi

# =========================================================
# Option 2 or 3 → Split full dump into chunks
# =========================================================
if [[ "$CHOICE" == "2" || "$CHOICE" == "3" ]]; then
    echo
    echo "Splitting full detailed dump into chunks of $CHUNK_SIZE packets..."
    rm -f "$OUT_DIR/${BASE_NAME}_chunk_"*.txt

    tshark -r "$PCAP_FILE" -V 2>/dev/null | \
    awk -v max="$CHUNK_SIZE" -v dir="$OUT_DIR" -v base="$BASE_NAME" '
        /^Frame [0-9]+:/ {
            if (NR > 1) { print prev >> outfile; close(outfile) }
            if (++count > max) {
                count = 1
                part++
                outfile = sprintf("%s/%s_chunk_%03d.txt", dir, base, part)
                printf "   → %s_chunk_%03d.txt (packets %d - %d)\n", base, part, (part-1)*max+1, part*max
            } else if (count == 1) {
                part++
                outfile = sprintf("%s/%s_chunk_%03d.txt", dir, base, part)
                printf "   → %s_chunk_%03d.txt (packets %d - ", base, part, (part-1)*max+1
            }
        }
        { prev = $0 }
        END {
            if (NR > 0) {
                print prev >> outfile
                close(outfile)
                printf "%d)\n", (part-1)*max + count - 1
            }
            printf "Done! %d chunk(s) created.\n", part
        }'
fi

echo
echo "════════════════════════════════════════════════════"
echo "ALL DONE!"
echo "Files created in: $OUT_DIR"
ls -lh "$OUT_DIR/${BASE_NAME}"*{index,chunk}* 2>/dev/null | head -10
[ "$(ls "$OUT_DIR/${BASE_NAME}_chunk_"*.txt 2>/dev/null | wc -l)" -gt 10 ] && echo "... and more chunk files"
echo "════════════════════════════════════════════════════"
