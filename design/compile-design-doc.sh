#!/bin/bash
# Compile modular design document into a single markdown file
# Usage: ./compile-design-doc.sh > complete-design.md

set -euo pipefail

SECTIONS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/sections" && pwd)"

# Process all markdown files in sorted order
for section_file in $(ls "${SECTIONS_DIR}"/*.md | sort); do
    cat "$section_file"
    echo ""

    # Add separator after major sections
    basename=$(basename "$section_file")
    if [[ "$basename" =~ ^(02-|04-|05-00-|05-4-|06-00-|06-4-|07-|08-) ]]; then
        echo "---"
        echo ""
    fi
done

echo "*Document compiled from modular sections on $(date)*"
