#!/bin/bash

# Check arguments
if [ $# -eq 0 ]; then
    echo ""
    echo "Error, no input file supplied"
    echo ""
    echo "Usage:"
    echo "        $0 <input ASM file>"
    echo ""
    exit 1
fi
INPUT_FILE_PATH="$1"

# Paths etc
DASM_DIR="/Users/philip/Development/Atari2600/tools"
DASM="$DASM_DIR/dasm"
VCS_INCLUDE_DIR="$DASM_DIR"


LISTING_EXTENSION="lst"
BINARY_EXTENSION="bin"

FILENAME=`basename $INPUT_FILE_PATH`
PROG_NAME=${FILENAME%.*}

LISTING_NAME="$PROG_NAME.$LISTING_EXTENSION"
OUTPUT_NAME="$PROG_NAME.$BINARY_EXTENSION"

echo "Building: $PROG_NAME"
echo ""
echo "Listing name: $LISTING_NAME"
echo "      Binary: $OUTPUT_NAME"
echo ""

# Clean up old files
rm "$LISTING_NAME"
rm "$OUTPUT_NAME"

# Build new ROM
$DASM "$INPUT_FILE_PATH" -f3 -v4 -I"$VCS_INCLUDE_DIR" -l"$LISTING_NAME" -o"$OUTPUT_NAME"
