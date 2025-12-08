#!/bin/bash
# =========================================================
# Albion Online PCAP Extractor v4
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
# Function: Generate index only
# =========================================================
generate_index_only() {
    show_header
    echo "=== GENERATE PACKET INDEX ONLY ==="
    echo
    echo "This creates a summary file with one line per packet."
    echo
    echo "Do you want to apply the Albion IP filter?"
    echo "   1) Yes - Only Albion servers (5.188.125.0/24)"
    echo "   2) No  - All packets"
    echo
    read -p "Choose [1-2]: " FILTER_CHOICE
    
    if [ "$FILTER_CHOICE" = "1" ]; then
        IP_FILTER="ip.addr == 5.188.125.0/24"
        echo "Filter: $IP_FILTER"
    else
        IP_FILTER=""
        echo "No filter applied"
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
    echo "Generating packet index..."
    
    if [ -n "$IP_FILTER" ]; then
        tshark -r "$PCAP_FILE" -Y "$IP_FILTER" > "$OUT_DIR/${BASE_NAME}_index.txt" 2>/dev/null
    else
        tshark -r "$PCAP_FILE" > "$OUT_DIR/${BASE_NAME}_index.txt" 2>/dev/null
    fi
    
    TOTAL_LINES=$(wc -l < "$OUT_DIR/${BASE_NAME}_index.txt")
    FILE_SIZE=$(du -h "$OUT_DIR/${BASE_NAME}_index.txt" | cut -f1)
    
    echo
    echo "════════════════════════════════════════════════════════════"
    echo "INDEX CREATED:"
    echo "════════════════════════════════════════════════════════════"
    echo "File: ${BASE_NAME}_index.txt"
    echo "Size: $FILE_SIZE"
    echo "Packets: $TOTAL_LINES"
    echo "Location: $OUT_DIR"
    echo
    echo "Preview (first 10 lines):"
    echo "────────────────────────────────────────────────────────────"
    head -10 "$OUT_DIR/${BASE_NAME}_index.txt"
    echo "────────────────────────────────────────────────────────────"
}

# =========================================================
# Function: Analyze traffic
# =========================================================
analyze_traffic() {
    show_header
    echo "=== TRAFFIC ANALYSIS ==="
    echo
    echo "Analyze from:"
    echo "   1) Existing index file (.txt)"
    echo "   2) PCAPNG file (will generate temporary index)"
    echo
    read -p "Choose [1-2]: " SOURCE_CHOICE
    
    if [ "$SOURCE_CHOICE" = "1" ]; then
        echo
        echo -n "Enter path to index .txt file: "
        read -r INDEX_FILE
        INDEX_FILE="${INDEX_FILE/#\~/$HOME}"
        
        if [ ! -f "$INDEX_FILE" ]; then
            echo "Error: File not found → $INDEX_FILE"
            return 1
        fi
        
        TEMP_INDEX="$INDEX_FILE"
        CLEANUP_TEMP=false
    else
        echo
        echo -n "Enter path to .pcapng file [/tmp/albion.pcapng]: "
        read -r PCAP_FILE
        PCAP_FILE="${PCAP_FILE:-/tmp/albion.pcapng}"
        PCAP_FILE="${PCAP_FILE/#\~/$HOME}"
        
        if [ ! -f "$PCAP_FILE" ]; then
            echo "Error: File not found → $PCAP_FILE"
            return 1
        fi
        
        echo
        echo "Generating temporary index..."
        TEMP_INDEX="/tmp/albion_temp_index_$$.txt"
        tshark -r "$PCAP_FILE" > "$TEMP_INDEX" 2>/dev/null
        CLEANUP_TEMP=true
    fi
    
    # Count total packets
    TOTAL_PACKETS=$(wc -l < "$TEMP_INDEX")
    
    # Count Albion packets
    ALBION_PACKETS=$(grep -c "5\.188\.125\." "$TEMP_INDEX" 2>/dev/null || echo "0")
    
    # Count other packets
    OTHER_PACKETS=$((TOTAL_PACKETS - ALBION_PACKETS))
    
    # Calculate percentage
    if [ "$TOTAL_PACKETS" -gt 0 ]; then
        ALBION_PCT=$(awk "BEGIN {printf \"%.1f\", ($ALBION_PACKETS/$TOTAL_PACKETS)*100}")
        OTHER_PCT=$(awk "BEGIN {printf \"%.1f\", ($OTHER_PACKETS/$TOTAL_PACKETS)*100}")
    else
        ALBION_PCT="0.0"
        OTHER_PCT="0.0"
    fi
    
    # Display results
    echo
    echo "════════════════════════════════════════════════════════════"
    echo "                    TRAFFIC ANALYSIS"
    echo "════════════════════════════════════════════════════════════"
    echo
    echo "Albion Servers Found:"
    echo "┌──────────────────┬────────┬──────────┐"
    echo "│ IP               │ Port   │ Packets  │"
    echo "├──────────────────┼────────┼──────────┤"
    
    # Parse and count IP:Port combinations for Albion traffic
    grep "5\.188\.125\." "$TEMP_INDEX" | \
    awk '{
        for (i=1; i<=NF; i++) {
            if ($i ~ /^5\.188\.125\.[0-9]+$/) {
                ip = $i
                for (j=1; j<=NF; j++) {
                    if ($j == "4535" || $j == "5055" || $j == "5056") {
                        port = $j
                        break
                    }
                }
                key = ip "|" port
                count[key]++
                ips[key] = ip
                ports[key] = port
                break
            }
        }
    }
    END {
        for (key in count) {
            print count[key], ips[key], ports[key]
        }
    }' | sort -rn | while read cnt ip port; do
        printf "│ %-16s │ %-6s │ %8d │\n" "$ip" "$port" "$cnt"
    done
    
    echo "└──────────────────┴────────┴──────────┘"
    echo
    echo "Summary:"
    echo "  Total packets:    $TOTAL_PACKETS"
    echo "  Albion traffic:   $ALBION_PACKETS ($ALBION_PCT%)"
    echo "  Other traffic:    $OTHER_PACKETS ($OTHER_PCT%)"
    echo
    echo "════════════════════════════════════════════════════════════"
    
    # Cleanup temp file if needed
    if [ "$CLEANUP_TEMP" = true ]; then
        rm -f "$TEMP_INDEX"
    fi
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
        echo "      → Generates: index + chunks"
        echo
        echo "   3) Process .pcapng WITHOUT filter (all packets)"
        echo "      → Generates: index + chunks"
        echo
        echo "   4) Generate packet index only (summary, one line per packet)"
        echo "      → Generates: index only"
        echo
        echo "   5) Analyze traffic (show servers, ports, packet count)"
        echo "      → Generates: terminal output only (no files)"
        echo
        echo "   6) Exit"
        echo
        read -p "Choose [1-6]: " CHOICE
        
        case "$CHOICE" in
            1) split_txt_file ;;
            2) process_pcapng "yes" ;;
            3) process_pcapng "no" ;;
            4) generate_index_only ;;
            5) analyze_traffic ;;
            6) echo "Bye!"; exit 0 ;;
            *) echo "Invalid option" ;;
        esac
        
        echo
        read -p "Press ENTER to continue..."
    done
}

main_menu
