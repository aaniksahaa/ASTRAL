#!/bin/bash

# Create JNA GPU Library Stub for ASTRAL
# This creates a simple GPU library that can be loaded by JNA without CUDA dependencies

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Creating JNA GPU Library Stub ===${NC}"
echo

# Create a simple C library that provides the GPU interface
mkdir -p gpu-stub

cat > gpu-stub/astral_gpu.c << 'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Structure for bipartition data
typedef struct {
    void* cluster1;
    void* cluster2;
    int bitsetSize;
} Bipartition;

// Test function to verify GPU availability
int testGPUAvailability() {
    // For now, return 1 (GPU not available) to gracefully fall back to CPU
    // This can be enhanced later to actually detect GPU
    printf("JNA GPU stub: testGPUAvailability called\n");
    return 1; // Return 1 = GPU not available (graceful fallback)
}

// Get GPU device count
int getGPUDeviceCount() {
    printf("JNA GPU stub: getGPUDeviceCount called\n");
    return 0; // No GPU devices available in stub
}

// Get GPU device name
const char* getGPUDeviceName(int deviceIndex) {
    printf("JNA GPU stub: getGPUDeviceName called for device %d\n", deviceIndex);
    return "GPU Stub Device";
}

// GPU weight calculation function (stub)
void launchWeightCalculation(
    Bipartition* candidates,
    Bipartition* geneTreeBips,
    int* frequencies,
    double* weights,
    int numCandidates,
    int numGeneTreeBips,
    int bitsetSize
) {
    printf("JNA GPU stub: launchWeightCalculation called (not implemented)\n");
    // This is a stub - actual implementation would go here
    // For now, just return without doing anything
}
EOF

echo -e "${GREEN}✓ Created GPU stub source code${NC}"

# Create Makefile
cat > gpu-stub/Makefile << 'EOF'
# Makefile for ASTRAL JNA GPU Stub Library

CC = gcc
CFLAGS = -O3 -fPIC -shared -Wall
TARGET = libastral_gpu.so
SOURCE = astral_gpu.c

all: $(TARGET)

$(TARGET): $(SOURCE)
	$(CC) $(CFLAGS) -o $(TARGET) $(SOURCE)

clean:
	rm -f $(TARGET)

install: $(TARGET)
	cp $(TARGET) ../lib-enhanced/
	cp $(TARGET) ../cuda/ 2>/dev/null || mkdir -p ../cuda && cp $(TARGET) ../cuda/

.PHONY: all clean install
EOF

echo -e "${GREEN}✓ Created Makefile${NC}"

# Build the library
cd gpu-stub
echo -e "${YELLOW}Building JNA GPU stub library...${NC}"
make clean
make

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ GPU stub library built successfully${NC}"
    
    # Install the library
    make install
    echo -e "${GREEN}✓ GPU stub library installed${NC}"
    
    # List the created library
    echo -e "${BLUE}Created library:${NC}"
    ls -la libastral_gpu.so
    
    cd ..
    echo -e "${GREEN}✓ JNA GPU stub setup complete${NC}"
    echo
    echo -e "${BLUE}The stub library provides:${NC}"
    echo "  • JNA-compatible interface"
    echo "  • Graceful GPU detection (returns 'not available')"
    echo "  • No CUDA dependencies"
    echo "  • Clean fallback to CPU computation"
    echo
    echo -e "${BLUE}Now compile and test:${NC}"
    echo "  ./compile-astral-maven.sh"
    echo "  ./run-astral-maven.sh -i ../inputs/in200.tr -o ./out.tr"
else
    echo -e "${RED}✗ Failed to build GPU stub library${NC}"
    cd ..
    exit 1
fi
