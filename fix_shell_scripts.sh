#!/bin/bash
# Script to fix line endings in shell scripts
# Converts CRLF (Windows) to LF (Unix) and makes scripts executable

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "🔧 Fixing shell script line endings..."
echo ""

# Find all .sh files in the deploy directory
sh_files=$(find "$SCRIPT_DIR" -name "*.sh" -type f)

if [ -z "$sh_files" ]; then
    echo "❌ No shell scripts found in $SCRIPT_DIR"
    exit 1
fi

fixed_count=0
executable_count=0

# Process each shell script
while IFS= read -r file; do
    if [ -f "$file" ]; then
        echo "📝 Processing: $(basename "$file")"
        
        # Check if file has CRLF line endings
        if file "$file" | grep -q "CRLF"; then
            # Convert CRLF to LF (works on macOS and Linux)
            if [[ "$OSTYPE" == "darwin"* ]]; then
                # macOS
                sed -i '' 's/\r$//' "$file"
            else
                # Linux
                sed -i 's/\r$//' "$file"
            fi
            echo "   ✅ Fixed line endings (CRLF → LF)"
            ((fixed_count++))
        else
            echo "   ℹ️  Already has Unix line endings"
        fi
        
        # Make executable if not already
        if [ ! -x "$file" ]; then
            chmod +x "$file"
            echo "   ✅ Made executable"
            ((executable_count++))
        else
            echo "   ℹ️  Already executable"
        fi
        
        echo ""
    fi
done <<< "$sh_files"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✨ Summary:"
echo "   • Fixed line endings: $fixed_count file(s)"
echo "   • Made executable: $executable_count file(s)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✅ All shell scripts are now ready to use!"

