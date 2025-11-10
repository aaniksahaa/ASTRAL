#!/bin/bash

# Maven-based ASTRAL Runner Script
# This script runs ASTRAL using the Maven-built JAR with proper library path management

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ASTRAL_JAR="target/astral-5.15.5.jar"
NATIVE_DIR="target/native"

# Function to check system GPU support
check_gpu_support() {
    echo -e "${BLUE}=== GPU Support Check ===${NC}"
    
    # Check OpenCL
    echo "Checking OpenCL support..."
    if command -v clinfo >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} clinfo available"
        clinfo -l 2>/dev/null | head -5 || echo "  No OpenCL platforms found"
    else
        echo -e "  ${YELLOW}⚠${NC} clinfo not available"
    fi
    
    # Check for OpenCL library
    opencl_found=false
    for path in "/usr/lib/x86_64-linux-gnu/libOpenCL.so.1" "/usr/lib64/libOpenCL.so.1" "/usr/local/lib/libOpenCL.so" "/lib/x86_64-linux-gnu/libOpenCL.so.1"; do
        if [ -f "$path" ]; then
            echo -e "  ${GREEN}✓${NC} libOpenCL.so found at $path"
            opencl_found=true
            break
        fi
    done
    if [ "$opencl_found" = false ]; then
        echo -e "  ${YELLOW}⚠${NC} libOpenCL.so not found - OpenCL may not work"
    fi
    
    # Check CUDA
    echo "Checking CUDA support..."
    if command -v nvidia-smi >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} nvidia-smi available"
        nvidia-smi -L 2>/dev/null | head -3 || echo "  No NVIDIA GPUs found"
    else
        echo -e "  ${YELLOW}⚠${NC} nvidia-smi not available"
    fi
    
    # Check native libraries
    echo "Checking ASTRAL native libraries..."
    if [ -d "$NATIVE_DIR" ]; then
        for lib in "$NATIVE_DIR"/*.so "$NATIVE_DIR"/*.dll "$NATIVE_DIR"/*.dylib; do
            if [ -f "$lib" ]; then
                echo -e "  ${GREEN}✓${NC} $(basename "$lib")"
            fi
        done
    else
        echo -e "  ${YELLOW}⚠${NC} Native library directory not found: $NATIVE_DIR"
    fi
    
    echo -e "${BLUE}=========================${NC}"
    echo
}

# Print usage if no arguments
if [ $# -eq 0 ]; then
    echo -e "${BLUE}Maven-based ASTRAL Runner${NC}"
    echo "========================="
    echo "Usage: $0 -i input_file.tre [-o output_file.tre] [other_options]"
    echo ""
    echo "Common options:"
    echo "  -i FILE    Input gene trees file (required)"
    echo "  -o FILE    Output species tree file (recommended)"
    echo "  -C         CPU-only mode (disable GPU)"
    echo "  -T N       Number of CPU threads"
    echo "  -G LIST    GPU indices to use (comma-separated)"
    echo "  -t N       Branch annotation level (0-4, 8, 10, 16, 32)"
    echo ""
    echo "Examples:"
    echo "  $0 -i gene_trees.tre -o species_tree.tre"
    echo "  $0 -i gene_trees.tre -o species_tree.tre -C"
    echo "  $0 -i gene_trees.tre -o species_tree.tre -T 8 -G 1"
    echo ""
    exit 0
fi

# Check for help flag
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    check_gpu_support
    exit 0
fi

# Check if ASTRAL JAR exists
if [ ! -f "$ASTRAL_JAR" ]; then
    echo -e "${RED}Error: ASTRAL JAR not found: $ASTRAL_JAR${NC}"
    echo "Please run ./build-maven.sh first to build ASTRAL"
    exit 1
fi

# Print configuration
echo -e "${BLUE}Maven ASTRAL Configuration:${NC}"
echo "=========================="
echo "ASTRAL JAR:    $ASTRAL_JAR"
echo "Native libs:   $NATIVE_DIR"
echo "Working dir:   $(pwd)"
echo ""

# Set up library paths for better GPU support
JAVA_LIBRARY_PATH="$NATIVE_DIR"
if [ -d "/usr/lib/x86_64-linux-gnu" ]; then
    JAVA_LIBRARY_PATH="$JAVA_LIBRARY_PATH:/usr/lib/x86_64-linux-gnu"
fi
if [ -d "/usr/lib64" ]; then
    JAVA_LIBRARY_PATH="$JAVA_LIBRARY_PATH:/usr/lib64"
fi
if [ -d "/usr/local/cuda/lib64" ]; then
    JAVA_LIBRARY_PATH="$JAVA_LIBRARY_PATH:/usr/local/cuda/lib64"
fi

# Show GPU support status
check_gpu_support

# Run ASTRAL
echo -e "${YELLOW}Running Maven ASTRAL with arguments: $@${NC}"
echo "=========================================="

# Execute ASTRAL with enhanced configuration
java -Xms2g -Xmx8g \
     -Djava.library.path="$JAVA_LIBRARY_PATH" \
     -jar "$ASTRAL_JAR" "$@"

# Capture exit code
exit_code=$?

echo ""
if [ $exit_code -eq 0 ]; then
    echo -e "${GREEN}✓ ASTRAL completed successfully${NC}"
else
    echo -e "${YELLOW}⚠ ASTRAL completed with exit code: $exit_code${NC}"
fi

exit $exit_code
