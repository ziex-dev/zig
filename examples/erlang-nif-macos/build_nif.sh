#!/bin/bash
# Build script for Zig NIFs on macOS
# Handles the known linker issues on macOS

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZIG_VERSION="${ZIG_VERSION:-0.14.0}"
ZIG_BIN="${ZIG_BIN:-/Users/developer/Documents/GitHub/workspaces/zig/zig-0.14/zig}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== Zig NIF Builder for macOS ==="
echo ""

# Check if Zig is available
if [ ! -f "$ZIG_BIN" ]; then
    echo -e "${RED}Error: Zig not found at $ZIG_BIN${NC}"
    echo "Set ZIG_BIN environment variable to the correct path"
    exit 1
fi

echo "Using Zig: $ZIG_BIN"
echo "Version: $($ZIG_BIN version)"
echo ""

# Detect platform
OS=$(uname -s)
ARCH=$(uname -m)
echo "Platform: $OS $ARCH"

# macOS-specific configuration
if [ "$OS" = "Darwin" ]; then
    echo -e "${YELLOW}Note: Applying macOS-specific linker flags for NIF compatibility${NC}"
    MACOS_FLAGS="-fallow-shlib-undefined"
    
    # macOS uses .so extension for NIFs (Erlang convention)
    OUTPUT_NAME="zig_test.so"
else
    MACOS_FLAGS=""
    OUTPUT_NAME="zig_test.so"
fi

# Build command
echo ""
echo "Building NIF..."
echo ""

# Use zig build-lib directly (workaround for build runner issues on macOS 26.3.1)
BUILD_CMD="$ZIG_BIN build-lib \
    -dynamic \
    -target native-macos \
    -lc \
    $MACOS_FLAGS \
    -OReleaseSafe \
    -femit-bin=$OUTPUT_NAME \
    src/main.zig"

echo "Command:"
echo "$BUILD_CMD"
echo ""

# Execute build
eval $BUILD_CMD

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ Build successful!${NC}"
    echo ""
    echo "Output: $SCRIPT_DIR/$OUTPUT_NAME"
    
    # Show library info
    if command -v file &> /dev/null; then
        echo ""
        echo "Library info:"
        file "$SCRIPT_DIR/$OUTPUT_NAME"
    fi
    
    # Show exported symbols
    if command -v nm &> /dev/null; then
        echo ""
        echo "Exported NIF symbols:"
        nm "$SCRIPT_DIR/$OUTPUT_NAME" | grep -E "T _nif|D _nif" || echo "  (No exported NIF symbols found)"
    fi
    
    echo ""
    echo -e "${GREEN}NIF is ready to load from Erlang/Elixir!${NC}"
else
    echo ""
    echo -e "${RED}✗ Build failed${NC}"
    exit 1
fi
