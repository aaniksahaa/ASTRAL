#!/bin/bash

# Fix JOCL Native Library Issues on Remote Machines
# This script resolves JOCL compatibility issues by prioritizing system OpenCL libraries

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== JOCL Native Library Fix for Remote Machines ===${NC}"
echo

# Check if we're in the right directory
if [ ! -f "run-astral-maven.sh" ]; then
    echo -e "${RED}Error: Please run this script from the ASTRAL root directory${NC}"
    exit 1
fi

# Backup the problematic JOCL native library
if [ -f "lib-enhanced/libJOCL_2_0_0-linux-x86_64.so" ]; then
    echo -e "${YELLOW}Backing up bundled JOCL native library...${NC}"
    mv lib-enhanced/libJOCL_2_0_0-linux-x86_64.so lib-enhanced/libJOCL_2_0_0-linux-x86_64.so.backup
    echo -e "${GREEN}✓ Bundled JOCL library backed up${NC}"
else
    echo -e "${YELLOW}⚠ Bundled JOCL library not found (already removed?)${NC}"
fi

# Check system OpenCL libraries
echo -e "${YELLOW}Checking system OpenCL libraries...${NC}"
opencl_found=false
for path in "/usr/lib/x86_64-linux-gnu/libOpenCL.so.1" "/usr/lib64/libOpenCL.so.1" "/usr/local/lib/libOpenCL.so"; do
    if [ -f "$path" ]; then
        echo -e "${GREEN}✓ Found system OpenCL: $path${NC}"
        opencl_found=true
    fi
done

if [ "$opencl_found" = false ]; then
    echo -e "${RED}✗ No system OpenCL libraries found${NC}"
    echo "Please install OpenCL development libraries:"
    echo "  Ubuntu/Debian: sudo apt install ocl-icd-opencl-dev"
    echo "  CentOS/RHEL: sudo yum install ocl-icd-devel"
    exit 1
fi

# Check NVIDIA OpenCL implementation
if command -v nvidia-smi >/dev/null 2>&1; then
    echo -e "${GREEN}✓ NVIDIA GPU detected${NC}"
    
    # Check if NVIDIA OpenCL is available
    if [ -f "/usr/lib/x86_64-linux-gnu/libnvidia-opencl.so.1" ]; then
        echo -e "${GREEN}✓ NVIDIA OpenCL implementation found${NC}"
    else
        echo -e "${YELLOW}⚠ NVIDIA OpenCL implementation not found${NC}"
        echo "Consider installing: sudo apt install nvidia-opencl-dev"
    fi
fi

# Recompile with the fix
echo -e "${YELLOW}Recompiling ASTRAL with JOCL fix...${NC}"
./compile-astral-maven.sh

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Compilation successful with JOCL fix${NC}"
    echo
    echo -e "${BLUE}Testing GPU initialization...${NC}"
    echo "Running: ./run-astral-maven.sh --help"
    echo
    ./run-astral-maven.sh --help
    echo
    echo -e "${BLUE}If GPU initialization works above, you can now run:${NC}"
    echo "  ./run-astral-maven.sh -i ../inputs/in200.tr -o ./out.tr"
else
    echo -e "${RED}✗ Compilation failed${NC}"
    exit 1
fi
