#!/bin/bash

# Setup JNA GPU for ASTRAL (Stelar-style approach)
# This script ensures the JNA GPU library is available in all the right places

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Setting up JNA GPU for ASTRAL (Stelar-style) ===${NC}"
echo

ASTRAL_ROOT=$(pwd)
echo -e "${BLUE}ASTRAL Root: ${ASTRAL_ROOT}${NC}"

# Ensure we have the GPU stub library
if [ ! -f "gpu-stub/libastral_gpu.so" ]; then
    echo -e "${YELLOW}GPU stub library not found. Creating it...${NC}"
    ./create-jna-gpu-stub.sh
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to create GPU stub library${NC}"
        exit 1
    fi
fi

# Copy GPU library to all possible locations
echo -e "${YELLOW}Copying GPU library to all possible locations...${NC}"

# Create directories if they don't exist
mkdir -p cuda
mkdir -p lib
mkdir -p lib-enhanced
mkdir -p main/cuda
mkdir -p main/lib
mkdir -p main/lib-enhanced

# Copy the library to all locations
cp gpu-stub/libastral_gpu.so cuda/
cp gpu-stub/libastral_gpu.so lib/
cp gpu-stub/libastral_gpu.so lib-enhanced/
cp gpu-stub/libastral_gpu.so main/cuda/
cp gpu-stub/libastral_gpu.so main/lib/
cp gpu-stub/libastral_gpu.so main/lib-enhanced/

echo -e "${GREEN}✓ GPU library copied to all locations${NC}"

# Verify library locations
echo -e "${BLUE}Verifying GPU library locations:${NC}"
for dir in cuda lib lib-enhanced main/cuda main/lib main/lib-enhanced; do
    if [ -f "${dir}/libastral_gpu.so" ]; then
        echo -e "${GREEN}  ✓ ${dir}/libastral_gpu.so${NC}"
    else
        echo -e "${RED}  ✗ ${dir}/libastral_gpu.so${NC}"
    fi
done

# Recompile ASTRAL with JNA support
echo -e "${YELLOW}Recompiling ASTRAL with JNA GPU support...${NC}"
./compile-astral-maven.sh
if [ $? -ne 0 ]; then
    echo -e "${RED}Compilation failed${NC}"
    exit 1
fi

echo -e "${GREEN}✓ JNA GPU setup complete${NC}"
echo
echo -e "${BLUE}Now you can test with:${NC}"
echo "  ./run-astral-maven.sh -i inputs/in200.tr -o main/out.tr"
echo
echo -e "${BLUE}This should show:${NC}"
echo "  • JNA GPU Manager initialization"
echo "  • Graceful fallback to CPU if GPU not available"
echo "  • No JOCL errors"
