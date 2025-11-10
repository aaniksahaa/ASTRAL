#!/bin/bash

# Maven-Enhanced ASTRAL Compilation Script
# This script compiles ASTRAL using Maven-managed dependencies with the existing structure

# Define ASTRAL root directory (absolute path)
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

# Print header
echo -e "${BLUE}Maven-Enhanced ASTRAL Compilation Script${NC}"
echo "========================================"
echo ""

# Check if enhanced libraries exist
if [ ! -d "${LIB_ENHANCED_DIR}" ]; then
    echo -e "${RED}Error: Enhanced library directory not found: ${LIB_ENHANCED_DIR}${NC}"
    echo "Please run ./setup-maven-deps.sh first to set up Maven dependencies"
    exit 1
fi

# Build classpath from enhanced libraries
CLASSPATH=""
for jar in "${LIB_ENHANCED_DIR}"/*.jar; do
    if [ -f "$jar" ]; then
        if [ -z "$CLASSPATH" ]; then
            CLASSPATH="$jar"
        else
            CLASSPATH="$CLASSPATH:$jar"
        fi
    fi
done

if [ -z "$CLASSPATH" ]; then
    echo -e "${RED}Error: No JAR files found in ${LIB_ENHANCED_DIR}${NC}"
    exit 1
fi

# Print configuration
echo -e "${YELLOW}Configuration:${NC}"
echo "ASTRAL_ROOT:     ${ASTRAL_ROOT}"
echo "MAIN_DIR:        ${MAIN_DIR}"
echo "LIB_ENHANCED:    ${LIB_ENHANCED_DIR}"
echo "CLASSPATH:       ${CLASSPATH}"
echo ""

# Check if main directory exists
if [ ! -d "${MAIN_DIR}" ]; then
    echo -e "${RED}Error: Main source directory not found: ${MAIN_DIR}${NC}"
    exit 1
fi

# Show available libraries
echo -e "${YELLOW}Available enhanced libraries:${NC}"
ls -la "${LIB_ENHANCED_DIR}"/*.jar 2>/dev/null || echo "No JAR files found"
echo ""

# Change to main directory
echo -e "${YELLOW}Changing to main directory: ${MAIN_DIR}${NC}"
cd "${MAIN_DIR}" || {
    echo -e "${RED}Error: Could not change to main directory: ${MAIN_DIR}${NC}"
    exit 1
}

# Clean previous compilation
echo ""
echo -e "${YELLOW}Cleaning previous compilation...${NC}"
find . -name "*.class" -type f -delete 2>/dev/null || true
echo "Previous .class files removed."

# Compile Java source files with enhanced dependencies
echo ""
echo -e "${YELLOW}Compiling ASTRAL with Maven-enhanced dependencies...${NC}"
echo "Command: javac -g -classpath ${CLASSPATH} phylonet/util/BitSet*.java phylonet/coalescent/*.java phylonet/coalescent/gpu/*.java phylonet/tree/model/sti/*.java phylonet/tree/io/NewickWriter.java"
echo ""

javac -g -classpath "${CLASSPATH}" \
    phylonet/util/BitSet*.java \
    phylonet/coalescent/*.java \
    phylonet/coalescent/gpu/*.java \
    phylonet/tree/model/sti/*.java \
    phylonet/tree/io/NewickWriter.java

# Check compilation result
if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ Compilation successful!${NC}"
    echo ""
    
    # Verify that key class files were created
    echo -e "${YELLOW}Verifying compiled classes...${NC}"
    key_classes=(
        "phylonet/coalescent/CommandLine.class"
        "phylonet/coalescent/gpu/GPUManager.class"
        "phylonet/util/BitSet.class"
        "phylonet/tree/model/sti/STITreeCluster.class"
        "phylonet/tree/io/NewickWriter.class"
    )
    
    all_found=true
    for class_file in "${key_classes[@]}"; do
        if [ -f "$class_file" ]; then
            echo -e "  ${GREEN}✓${NC} Found: $class_file"
        else
            echo -e "  ${RED}✗${NC} Missing: $class_file"
            all_found=false
        fi
    done
    
    if [ "$all_found" = true ]; then
        echo ""
        echo -e "${GREEN}🎉 All key classes compiled successfully!${NC}"
        echo ""
        echo -e "${BLUE}You can now run Maven-Enhanced ASTRAL using:${NC}"
        echo "  ${ASTRAL_ROOT}/run-astral-maven.sh -i input_file.tre -o output_file.tre"
        echo ""
        
        # Count total compiled classes
        class_count=$(find . -name "*.class" -type f | wc -l)
        echo "Total compiled classes: $class_count"
        
        # Show enhanced features
        echo ""
        echo -e "${BLUE}Enhanced Features:${NC}"
        echo -e "  ${GREEN}✓${NC} Robust GPU Manager with enhanced OpenCL error handling"
        echo -e "  ${GREEN}✓${NC} Maven-managed dependencies (JOCL, JNA, JSAP, Colt)"
        echo -e "  ${GREEN}✓${NC} Cross-platform compatibility"
        echo -e "  ${GREEN}✓${NC} Automatic library path management"
        echo ""
        
        exit 0
    else
        echo ""
        echo -e "${YELLOW}⚠️  Warning: Some key classes are missing. Compilation may have failed partially.${NC}"
        exit 1
    fi
else
    echo ""
    echo -e "${RED}✗ Compilation failed!${NC}"
    echo ""
    echo -e "${YELLOW}Common issues:${NC}"
    echo "1. Check that enhanced libraries are set up: ./setup-maven-deps.sh"
    echo "2. Ensure Java is installed and accessible"
    echo "3. Verify that source files are not corrupted"
    echo "4. Check for syntax errors in the Java source code"
    echo ""
    exit 1
fi
