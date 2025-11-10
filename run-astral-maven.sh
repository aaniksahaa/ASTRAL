#!/bin/bash

# Maven-Enhanced ASTRAL Runner Script
# This script runs ASTRAL with Maven-managed dependencies and enhanced GPU support

# Define ASTRAL root directory (current working directory)
ASTRAL_ROOT=$(pwd)

# Define paths based on ASTRAL_ROOT
MAIN_DIR="${ASTRAL_ROOT}/main"
LIB_ENHANCED_DIR="${ASTRAL_ROOT}/lib-enhanced"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to check system GPU support
check_gpu_support() {
    echo -e "${BLUE}=== Enhanced GPU Support Check ===${NC}"
    
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
    
    # Check enhanced libraries
    echo "Checking Maven-enhanced libraries..."
    if [ -d "$LIB_ENHANCED_DIR" ]; then
        for lib in "$LIB_ENHANCED_DIR"/*.so "$LIB_ENHANCED_DIR"/*.dll "$LIB_ENHANCED_DIR"/*.dylib; do
            if [ -f "$lib" ]; then
                echo -e "  ${GREEN}✓${NC} $(basename "$lib")"
            fi
        done
        
        # Check for key JAR files
        key_jars=("jocl" "jna" "jsap" "colt" "main")
        for jar_name in "${key_jars[@]}"; do
            if ls "$LIB_ENHANCED_DIR"/*"$jar_name"*.jar 1> /dev/null 2>&1; then
                echo -e "  ${GREEN}✓${NC} $jar_name library available"
            else
                echo -e "  ${YELLOW}⚠${NC} $jar_name library not found"
            fi
        done
    else
        echo -e "  ${RED}✗${NC} Enhanced library directory not found: $LIB_ENHANCED_DIR"
    fi
    
    echo -e "${BLUE}=================================${NC}"
    echo
}

# Print usage if no arguments
if [ $# -eq 0 ]; then
    echo -e "${BLUE}Maven-Enhanced ASTRAL Runner${NC}"
    echo "============================"
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
    echo -e "${BLUE}Enhanced Features:${NC}"
    echo "  • Robust GPU support with enhanced error handling"
    echo "  • Maven-managed dependencies for cross-platform compatibility"
    echo "  • Automatic library path detection and setup"
    echo "  • Improved OpenCL initialization with detailed diagnostics"
    echo ""
    exit 0
fi

# Check for help flag
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    check_gpu_support
    exit 0
fi

# Check if enhanced libraries exist
if [ ! -d "$LIB_ENHANCED_DIR" ]; then
    echo -e "${RED}Error: Enhanced library directory not found: $LIB_ENHANCED_DIR${NC}"
    echo "Please run ./setup-maven-deps.sh first to set up Maven dependencies"
    exit 1
fi

# Build classpath from enhanced libraries
CLASSPATH="."
for jar in "${LIB_ENHANCED_DIR}"/*.jar; do
    if [ -f "$jar" ]; then
        CLASSPATH="$CLASSPATH:$jar"
    fi
done

# Check if compiled classes exist
if [ ! -f "${MAIN_DIR}/phylonet/coalescent/CommandLine.class" ]; then
    echo -e "${RED}Error: Compiled classes not found. Please compile first:${NC}"
    echo "./compile-astral-maven.sh"
    exit 1
fi

# Set up enhanced library paths for better GPU support
JAVA_LIBRARY_PATH="$LIB_ENHANCED_DIR"
if [ -d "/usr/lib/x86_64-linux-gnu" ]; then
    JAVA_LIBRARY_PATH="$JAVA_LIBRARY_PATH:/usr/lib/x86_64-linux-gnu"
fi
if [ -d "/usr/lib64" ]; then
    JAVA_LIBRARY_PATH="$JAVA_LIBRARY_PATH:/usr/lib64"
fi
if [ -d "/usr/local/cuda/lib64" ]; then
    JAVA_LIBRARY_PATH="$JAVA_LIBRARY_PATH:/usr/local/cuda/lib64"
fi

# Print configuration
echo -e "${BLUE}Maven-Enhanced ASTRAL Configuration:${NC}"
echo "===================================="
echo "ASTRAL_ROOT:        ${ASTRAL_ROOT}"
echo "MAIN_DIR:           ${MAIN_DIR}"
echo "LIB_ENHANCED:       ${LIB_ENHANCED_DIR}"
echo "CLASSPATH:          ${CLASSPATH}"
echo "JAVA_LIBRARY_PATH:  ${JAVA_LIBRARY_PATH}"
echo ""

# Show GPU support status
check_gpu_support

# Run ASTRAL with all provided arguments
echo -e "${YELLOW}Running Maven-Enhanced ASTRAL with arguments: $@${NC}"
echo "=================================================="

# Change to main directory to match working command pattern
cd "${MAIN_DIR}"

# Execute ASTRAL with enhanced configuration
java -Xms2g -Xmx8g \
     -Djava.library.path="$JAVA_LIBRARY_PATH" \
     -classpath "$CLASSPATH" \
     phylonet.coalescent.CommandLine "$@"

# Capture exit code
exit_code=$?

echo ""
if [ $exit_code -eq 0 ]; then
    echo -e "${GREEN}✓ Maven-Enhanced ASTRAL completed successfully${NC}"
else
    echo -e "${YELLOW}⚠ Maven-Enhanced ASTRAL completed with exit code: $exit_code${NC}"
fi

echo -e "${BLUE}Enhanced features used:${NC}"
echo "  • Robust GPU initialization with detailed error reporting"
echo "  • Maven-managed dependencies for reliable library loading"
echo "  • Cross-platform native library path management"

exit $exit_code
