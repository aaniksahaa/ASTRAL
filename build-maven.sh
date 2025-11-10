#!/bin/bash

# Maven-based ASTRAL Build Script
# This script builds ASTRAL using Maven for better dependency management and cross-platform compatibility

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Maven-based ASTRAL Build Script ===${NC}"
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

# Check Maven version
echo -e "${YELLOW}Checking Maven version...${NC}"
mvn --version
echo

# Check if Java is available
if ! command -v java &> /dev/null; then
    echo -e "${RED}Error: Java is not installed or not in PATH${NC}"
    exit 1
fi

# Check Java version
echo -e "${YELLOW}Checking Java version...${NC}"
java -version
echo

# Clean and compile
echo -e "${YELLOW}Cleaning previous builds...${NC}"
mvn clean
if [ $? -ne 0 ]; then
    echo -e "${RED}Maven clean failed!${NC}"
    exit 1
fi

echo -e "${YELLOW}Compiling ASTRAL with Maven...${NC}"
mvn compile
if [ $? -ne 0 ]; then
    echo -e "${RED}Maven compilation failed!${NC}"
    exit 1
fi

echo -e "${YELLOW}Packaging ASTRAL JAR...${NC}"
mvn package
if [ $? -ne 0 ]; then
    echo -e "${RED}Maven packaging failed!${NC}"
    exit 1
fi

# Check if JAR was created
if [ -f "target/astral-5.15.5.jar" ]; then
    echo -e "${GREEN}✓ ASTRAL JAR created successfully: target/astral-5.15.5.jar${NC}"
else
    echo -e "${RED}✗ ASTRAL JAR not found${NC}"
    exit 1
fi

# Copy native libraries to target directory for easy access
echo -e "${YELLOW}Setting up native libraries...${NC}"
mkdir -p target/native
cp src/main/resources/native/* target/native/ 2>/dev/null || true

echo -e "${GREEN}✓ Build completed successfully!${NC}"
echo
echo -e "${BLUE}Usage:${NC}"
echo "  Run ASTRAL: ./run-maven.sh -i input.tre -o output.tre"
echo "  Or directly: java -jar target/astral-5.15.5.jar -i input.tre -o output.tre"
echo
echo -e "${BLUE}Files created:${NC}"
echo "  target/astral-5.15.5.jar - Main executable JAR with all dependencies"
echo "  target/native/ - Native libraries for GPU support"
echo
