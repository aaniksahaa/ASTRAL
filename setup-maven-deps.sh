#!/bin/bash

# ASTRAL Maven Dependency Setup Script
# This script uses Maven to download dependencies but keeps the existing ASTRAL structure

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== ASTRAL Maven Dependency Setup ===${NC}"
echo

# Check if Maven is installed
if ! command -v mvn &> /dev/null; then
    echo -e "${RED}Error: Maven is not installed or not in PATH${NC}"
    echo "Please install Maven first:"
    echo "  Ubuntu/Debian: sudo apt install maven"
    echo "  CentOS/RHEL: sudo yum install maven"
    echo "  macOS: brew install maven"
    exit 1
fi

echo -e "${YELLOW}Using Maven to download enhanced dependencies...${NC}"

# Use Maven to download dependencies
mvn -f pom-simple.xml dependency:copy-dependencies

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to download dependencies with Maven${NC}"
    exit 1
fi

# Create enhanced lib directory structure
echo -e "${YELLOW}Setting up enhanced library structure...${NC}"
mkdir -p lib-enhanced

# Copy original ASTRAL libraries
cp lib/*.jar lib-enhanced/ 2>/dev/null || true
cp lib/*.so lib/*.dll lib/*.dylib lib-enhanced/ 2>/dev/null || true

# Copy Maven-downloaded dependencies
cp lib-maven/*.jar lib-enhanced/ 2>/dev/null || true

echo -e "${GREEN}✓ Enhanced library setup complete!${NC}"
echo
echo -e "${BLUE}Enhanced libraries available in lib-enhanced/:${NC}"
ls -la lib-enhanced/
echo
echo -e "${BLUE}You can now use the enhanced compilation and run scripts:${NC}"
echo "  ./compile-astral-maven.sh"
echo "  ./run-astral-maven.sh -i input.tre -o output.tre"
