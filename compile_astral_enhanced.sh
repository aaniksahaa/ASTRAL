#!/bin/bash

# Enhanced ASTRAL Compilation Script with GPU Support
# This script compiles ASTRAL Java source code including the new GPU manager
# Usage: ./compile_astral_enhanced.sh

# Define ASTRAL root directory (absolute path)
ASTRAL_ROOT=$(pwd)

# Define paths based on ASTRAL_ROOT
MAIN_DIR="${ASTRAL_ROOT}/main"
LIB_DIR="${ASTRAL_ROOT}/lib"
CUDA_DIR="${ASTRAL_ROOT}/cuda"

# Required JAR files (using absolute paths based on ASTRAL_ROOT)
MAIN_JAR="${LIB_DIR}/main.jar"
COLT_JAR="${LIB_DIR}/colt.jar"
JSAP_JAR="${LIB_DIR}/JSAP-2.1.jar"
JOCL_JAR="${LIB_DIR}/jocl-2.0.0.jar"
JNA_JAR="${LIB_DIR}/jna-5.13.0.jar"
JNA_PLATFORM_JAR="${LIB_DIR}/jna-platform-5.13.0.jar"

# Build classpath for compilation
CLASSPATH="${MAIN_JAR}:${COLT_JAR}:${JSAP_JAR}:${JOCL_JAR}:${JNA_JAR}:${JNA_PLATFORM_JAR}"

# Print header
echo "Enhanced ASTRAL Compilation Script"
echo "=================================="
echo ""

# Print configuration
echo "Configuration:"
echo "ASTRAL_ROOT: ${ASTRAL_ROOT}"
echo "MAIN_DIR:    ${MAIN_DIR}"
echo "LIB_DIR:     ${LIB_DIR}"
echo "CUDA_DIR:    ${CUDA_DIR}"
echo "CLASSPATH:   ${CLASSPATH}"
echo ""

# Check if ASTRAL_ROOT exists
if [ ! -d "${ASTRAL_ROOT}" ]; then
    echo "Error: ASTRAL root directory not found: ${ASTRAL_ROOT}"
    echo "Please update the ASTRAL_ROOT variable in this script to point to your ASTRAL installation."
    exit 1
fi

# Check if main directory exists
if [ ! -d "${MAIN_DIR}" ]; then
    echo "Error: Main source directory not found: ${MAIN_DIR}"
    exit 1
fi

# Check if all required JAR files exist
echo "Checking required JAR files..."
for jar in "${MAIN_JAR}" "${COLT_JAR}" "${JSAP_JAR}" "${JOCL_JAR}" "${JNA_JAR}" "${JNA_PLATFORM_JAR}"; do
    if [ ! -f "$jar" ]; then
        echo "Error: Required JAR file not found: $jar"
        exit 1
    else
        echo "  ✓ Found: $(basename "$jar")"
    fi
done
echo ""

# Check if Java source files exist
echo "Checking Java source files..."
source_files=(
    "${MAIN_DIR}/phylonet/util/BitSet.java"
    "${MAIN_DIR}/phylonet/coalescent/CommandLine.java"
    "${MAIN_DIR}/phylonet/tree/model/sti/STITreeCluster.java"
    "${MAIN_DIR}/phylonet/tree/io/NewickWriter.java"
    "${MAIN_DIR}/phylonet/coalescent/gpu/GPUManager.java"
)

for file in "${source_files[@]}"; do
    if [ ! -f "$file" ]; then
        echo "Error: Required Java source file not found: $file"
        exit 1
    else
        echo "  ✓ Found: $(basename "$file")"
    fi
done
echo ""

# Check for JNA support (needed for CUDA fallback)
echo "Checking JNA support..."
if java -cp "${CLASSPATH}" -c "com.sun.jna.Native" 2>/dev/null; then
    echo "  ✓ JNA classes available in classpath"
else
    echo "  ⚠ JNA classes not found in classpath - CUDA fallback may not work"
    echo "    Consider adding JNA JAR files to lib directory for enhanced GPU support"
fi
echo ""

# Build CUDA library if possible
if [ -d "${CUDA_DIR}" ] && [ -f "${CUDA_DIR}/Makefile" ]; then
    echo "Building CUDA library..."
    cd "${CUDA_DIR}"
    if make clean && make; then
        echo "  ✓ CUDA library built successfully"
        if [ -f "libweight_calc.so" ]; then
            echo "  ✓ libweight_calc.so created"
        fi
    else
        echo "  ⚠ CUDA library build failed - GPU fallback may not work"
        echo "    This is not critical; OpenCL may still work"
    fi
    cd "${ASTRAL_ROOT}"
    echo ""
fi

# Change to main directory
echo "Changing to main directory: ${MAIN_DIR}"
cd "${MAIN_DIR}" || {
    echo "Error: Could not change to main directory: ${MAIN_DIR}"
    exit 1
}

# Clean previous compilation (optional)
echo ""
echo "Cleaning previous compilation..."
find . -name "*.class" -type f -delete 2>/dev/null || true
echo "Previous .class files removed."

# Compile Java source files
echo ""
echo "Compiling Java source files with enhanced GPU support..."
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
    echo "✓ Compilation successful!"
    echo ""
    
    # Verify that key class files were created
    echo "Verifying compiled classes..."
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
            echo "  ✓ Found: $class_file"
        else
            echo "  ✗ Missing: $class_file"
            all_found=false
        fi
    done
    
    if [ "$all_found" = true ]; then
        echo ""
        echo "🎉 All key classes compiled successfully!"
        echo ""
        echo "You can now run Enhanced ASTRAL using:"
        echo "  ${ASTRAL_ROOT}/run_astral_enhanced.sh -i input_file.tre -o output_file.tre"
        echo ""
        echo "Or use the original runner:"
        echo "  ${ASTRAL_ROOT}/run_astral.sh -i input_file.tre -o output_file.tre"
        echo ""
        
        # Count total compiled classes
        class_count=$(find . -name "*.class" -type f | wc -l)
        echo "Total compiled classes: $class_count"
        
        # Show GPU support summary
        echo ""
        echo "GPU Support Summary:"
        echo "==================="
        if [ -f "phylonet/coalescent/gpu/GPUManager.class" ]; then
            echo "  ✓ Enhanced GPU Manager compiled"
        fi
        if [ -f "${ASTRAL_ROOT}/cuda/libweight_calc.so" ]; then
            echo "  ✓ CUDA fallback library available"
        else
            echo "  ⚠ CUDA fallback library not available"
        fi
        echo "  ✓ OpenCL support available (if system libraries present)"
        echo ""
        
        exit 0
    else
        echo ""
        echo "⚠️  Warning: Some key classes are missing. Compilation may have failed partially."
        exit 1
    fi
else
    echo ""
    echo "✗ Compilation failed!"
    echo ""
    echo "Common issues:"
    echo "1. Check that all JAR files are present in ${LIB_DIR}/"
    echo "2. Ensure Java is installed and accessible"
    echo "3. Verify that source files are not corrupted"
    echo "4. Check for syntax errors in the Java source code"
    echo "5. For GPU support issues, ensure JNA libraries are available"
    echo ""
    exit 1
fi
