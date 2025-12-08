#!/bin/bash
# =========================================================
# Albion Online PCAP Extractor v3
# Splits tshark verbose output into manageable chunks
# =========================================================

CHUNK_SIZE=500

# Get script directory (where output will be saved)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
OUT_DIR="$SCRIPT_DIR/output"

show_header() {
    clear
    echo "════════════════════════════════════════════════════════════"
    echo "       ALBION ONLINE PCAP EXTRACTOR v3"
    echo "       Packets per chunk: $CHUNK_SIZE"
    echo "       Output directory: $OUT_DIR"
    echo "════════════════════════════════════════════════════════════"
    echo
}

# =========================================================
# Function: Split existing text file (FIXED)
# =========================================================
split_txt_file() {
    show_header
    echo "=== SPLIT EXISTING .TXT FILE ==="
    echo
    echo -n "Enter full path to the .txt dump file: "
    read -r TXT_FILE
    
    # Expand ~ to home directory
    TXT_FILE="${TXT_FILE/#\~/$HOME}"
    
    if [ ! -f "$TXT_FILE" ]; then
        echo "Error: File not found → $TXT_FILE"
        return 1
    fi
    
    TOTAL_PACKETS=$(grep -c "^Frame [0-9]*:" "$TXT_FILE")
    FILE_SIZE=$(du -h "$TXT_FILE" | cut -f1)
    EXPECTED_CHUNKS=$((TOTAL_PACKETS / CHUNK_SIZE + 1))
    
    echo
    echo "File: $TXT_FILE"
    echo "Size: $FILE_SIZE"
    echo "Total packets found: $TOTAL_PACKETS"
    echo "Expected chunks: $EXPECTED_CHUNKS files"
    echo "Output directory: $OUT_DIR"
    echo
    read -p "Continue? [Y/n] " CONFIRM
    [[ "$CONFIRM" =~ ^[Nn] ]] && return 0
    
    mkdir -p "$OUT_DIR"
    BASE_NAME=$(basename "$TXT_FILE" .txt)
    
    echo
    echo "Splitting into chunks of $CHUNK_SIZE packets..."
    rm -f "$OUT_DIR/${BASE_NAME}_chunk_"*.txt
    
    # Use csplit-like approach with awk - more reliable
    awk -v max="$CHUNK_SIZE" -v dir="$OUT_DIR" -v base="$BASE_NAME" '
    BEGIN {
        pkt = 0
        chunk = 1
        outfile = sprintf("%s/%s_chunk_%03d.txt", dir, base, chunk)
        printf "   → %s_chunk_%03d.txt ", base, chunk
    }
    
    /^Frame [0-9]+:/ {
        pkt++
        
        # Check if we need a new file
        if (pkt > max) {
            close(outfile)
            printf "(500 packets)\n"
            pkt = 1
            chunk++
            outfile = sprintf("%s/%s_chunk_%03d.txt", dir, base, chunk)
            printf "   → %s_chunk_%03d.txt ", base, chunk
        }
    }
    
    {
        print $0 >> outfile
    }
    
    END {
        close(outfile)
        printf "(%d packets)\n", pkt
        printf "\n✓ Done! %d chunk(s) created.\n", chunk
    }
    ' "$TXT_FILE"
    
    echo
    echo "════════════════════════════════════════════════════════════"
    echo "FILES CREATED:"
    echo "════════════════════════════════════════════════════════════"
    ls -lh "$OUT_DIR/${BASE_NAME}_chunk_"*.txt 2>/dev/null
    echo
    echo "Total size:"
    du -sh "$OUT_DIR" 2>/dev/null
}

# =========================================================
# Function: Process pcapng directly
# =========================================================
process_pcapng() {
    local USE_FILTER="$1"
    
    show_header
    if [ "$USE_FILTER" = "yes" ]; then
        echo "=== PROCESS .PCAPNG WITH FILTER ==="
        IP_FILTER="ip.addr == 5.188.125.0/24"
        echo "Filter: $IP_FILTER"
    else
        echo "=== PROCESS .PCAPNG (ALL PACKETS) ==="
    fi
    
    echo
    echo -n "Enter path to .pcapng file [/tmp/albion.pcapng]: "
    read -r PCAP_FILE
    PCAP_FILE="${PCAP_FILE:-/tmp/albion.pcapng}"
    PCAP_FILE="${PCAP_FILE/#\~/$HOME}"
    
    if [ ! -f "$PCAP_FILE" ]; then
        echo "Error: File not found → $PCAP_FILE"
        return 1
    fi
    
    mkdir -p "$OUT_DIR"
    BASE_NAME=$(basename "$PCAP_FILE" .pcapng)
    
    echo
    echo "Counting packets (this may take a moment)..."
    if [ "$USE_FILTER" = "yes" ]; then
        TOTAL_PACKETS=$(tshark -r "$PCAP_FILE" -Y "$IP_FILTER" 2>/dev/null | wc -l)
    else
        TOTAL_PACKETS=$(tshark -r "$PCAP_FILE" 2>/dev/null | wc -l)
    fi
    
    EXPECTED_CHUNKS=$((TOTAL_PACKETS / CHUNK_SIZE + 1))
    
    echo "Total packets: $TOTAL_PACKETS"
    echo "Expected chunks: $EXPECTED_CHUNKS files"
    echo "Output directory: $OUT_DIR"
    echo
    read -p "Continue? [Y/n] " CONFIRM
    [[ "$CONFIRM" =~ ^[Nn] ]] && return 0
    
    # Generate index
    echo
    echo "Generating packet index..."
    if [ "$USE_FILTER" = "yes" ]; then
        tshark -r "$PCAP_FILE" -Y "$IP_FILTER" > "$OUT_DIR/${BASE_NAME}_index.txt" 2>/dev/null
    else
        tshark -r "$PCAP_FILE" > "$OUT_DIR/${BASE_NAME}_index.txt" 2>/dev/null
    fi
    echo "→ ${BASE_NAME}_index.txt created"
    
    # Split into chunks
    echo
    echo "Splitting into chunks of $CHUNK_SIZE packets..."
    rm -f "$OUT_DIR/${BASE_NAME}_chunk_"*.txt
    
    if [ "$USE_FILTER" = "yes" ]; then
        tshark -r "$PCAP_FILE" -Y "$IP_FILTER" -V 2>/dev/null
    else
        tshark -r "$PCAP_FILE" -V 2>/dev/null
    fi | awk -v max="$CHUNK_SIZE" -v dir="$OUT_DIR" -v base="$BASE_NAME" '
    BEGIN {
        pkt = 0
        chunk = 1
        outfile = sprintf("%s/%s_chunk_%03d.txt", dir, base, chunk)
        printf "   → %s_chunk_%03d.txt ", base, chunk
    }
    
    /^Frame [0-9]+:/ {
        pkt++
        
        if (pkt > max) {
            close(outfile)
            printf "(500 packets)\n"
            pkt = 1
            chunk++
            outfile = sprintf("%s/%s_chunk_%03d.txt", dir, base, chunk)
            printf "   → %s_chunk_%03d.txt ", base, chunk
        }
    }
    
    {
        print $0 >> outfile
    }
    
    END {
        close(outfile)
        printf "(%d packets)\n", pkt
        printf "\n✓ Done! %d chunk(s) created.\n", chunk
    }
    '
    
    echo
    echo "════════════════════════════════════════════════════════════"
    echo "FILES CREATED:"
    echo "════════════════════════════════════════════════════════════"
    ls -lh "$OUT_DIR/${BASE_NAME}"*.txt 2>/dev/null | head -15
    CHUNK_COUNT=$(ls "$OUT_DIR/${BASE_NAME}_chunk_"*.txt 2>/dev/null | wc -l)
    [ "$CHUNK_COUNT" -gt 15 ] && echo "... and $((CHUNK_COUNT - 15)) more chunk files"
    echo
    du -sh "$OUT_DIR" 2>/dev/null
}

# =========================================================
# Main Menu
# =========================================================
main_menu() {
    while true; do
        show_header
        echo "What do you want to do?"
        echo
        echo "   1) Split an existing .txt dump file"
        echo "      (Use if you already have a tshark -V output file)"
        echo
        echo "   2) Process .pcapng WITH IP filter (Albion servers only)"
        echo
        echo "   3) Process .pcapng WITHOUT filter (all packets)"
        echo
        echo "   4) Exit"
        echo
        read -p "Choose [1-4]: " CHOICE
        
        case "$CHOICE" in
            1) split_txt_file ;;
            2) process_pcapng "yes" ;;
            3) process_pcapng "no" ;;
            4) echo "Bye!"; exit 0 ;;
            *) echo "Invalid option" ;;
        esac
        
        echo
        read -p "Press ENTER to continue..."
    done
}

main_menu
