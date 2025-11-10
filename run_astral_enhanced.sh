#!/bin/bash

# Enhanced ASTRAL Runner Script with Robust GPU Support
# This script runs ASTRAL with improved GPU initialization and fallback mechanisms
# Usage: ./run_astral_enhanced.sh -i input_file.tre [-o output_file.tre] [other_options]

# Define ASTRAL root directory (current working directory)
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

# Build classpath (with absolute paths, but current directory as "." for compiled classes)
CLASSPATH=".:${MAIN_JAR}:${COLT_JAR}:${JSAP_JAR}:${JOCL_JAR}:${JNA_JAR}:${JNA_PLATFORM_JAR}"

# Enhanced library path setup for robust GPU support
JAVA_LIBRARY_PATH="${LIB_DIR}"
JNA_LIBRARY_PATH="${CUDA_DIR}:${LIB_DIR}:/usr/local/cuda/lib64:/opt/cuda/lib64"

# Add CUDA directories to library path if they exist
if [ -d "/usr/local/cuda/lib64" ]; then
    JAVA_LIBRARY_PATH="${JAVA_LIBRARY_PATH}:/usr/local/cuda/lib64"
fi
if [ -d "/opt/cuda/lib64" ]; then
    JAVA_LIBRARY_PATH="${JAVA_LIBRARY_PATH}:/opt/cuda/lib64"
fi
if [ -d "${CUDA_DIR}" ]; then
    JAVA_LIBRARY_PATH="${JAVA_LIBRARY_PATH}:${CUDA_DIR}"
fi

# Function to check GPU availability
check_gpu_support() {
    echo "=== GPU Support Check ==="
    
    # Check OpenCL
    echo "Checking OpenCL support..."
    if command -v clinfo >/dev/null 2>&1; then
        echo "  ✓ clinfo available"
        clinfo -l 2>/dev/null | head -5
    else
        echo "  ⚠ clinfo not available"
    fi
    
    # Check for OpenCL library
    if [ -f "/usr/lib/x86_64-linux-gnu/libOpenCL.so.1" ] || [ -f "/usr/lib64/libOpenCL.so.1" ] || [ -f "/usr/local/lib/libOpenCL.so" ]; then
        echo "  ✓ libOpenCL.so found"
    else
        echo "  ⚠ libOpenCL.so not found - OpenCL may not work"
    fi
    
    # Check CUDA
    echo "Checking CUDA support..."
    if command -v nvidia-smi >/dev/null 2>&1; then
        echo "  ✓ nvidia-smi available"
        nvidia-smi -L 2>/dev/null | head -3
    else
        echo "  ⚠ nvidia-smi not available"
    fi
    
    # Check our CUDA library
    if [ -f "${CUDA_DIR}/libweight_calc.so" ]; then
        echo "  ✓ Custom CUDA library available: ${CUDA_DIR}/libweight_calc.so"
    else
        echo "  ⚠ Custom CUDA library not found: ${CUDA_DIR}/libweight_calc.so"
    fi
    
    echo "=========================="
    echo
}

# Print usage if no arguments
if [ $# -eq 0 ]; then
    echo "Enhanced ASTRAL Runner Script"
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
    echo "  $0 -i inputs/in200.tr -o out.tr"
    echo "  $0 -i inputs/gene_trees.tre -o species_tree.tre -C"
    echo "  $0 -i inputs/gene_trees.tre -o species_tree.tre -T 8 -G 1"
    echo ""
    echo "GPU Support:"
    echo "  This enhanced version provides robust GPU support with automatic fallback."
    echo "  It tries OpenCL first, then falls back to CUDA, then CPU-only if needed."
    echo ""
    exit 0
fi

# Check for help flag
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    check_gpu_support
    exit 0
fi

# Print configuration
echo "Enhanced ASTRAL Configuration:"
echo "============================="
echo "ASTRAL_ROOT:        ${ASTRAL_ROOT}"
echo "MAIN_DIR:           ${MAIN_DIR}"
echo "LIB_DIR:            ${LIB_DIR}"
echo "CUDA_DIR:           ${CUDA_DIR}"
echo "CLASSPATH:          ${CLASSPATH}"
echo "JAVA_LIBRARY_PATH:  ${JAVA_LIBRARY_PATH}"
echo "JNA_LIBRARY_PATH:   ${JNA_LIBRARY_PATH}"
echo ""

# Check if compiled classes exist
if [ ! -f "${MAIN_DIR}/phylonet/coalescent/CommandLine.class" ]; then
    echo "Error: Compiled classes not found. Please compile first:"
    echo "cd ${MAIN_DIR}"
    echo "javac -g -classpath ${MAIN_JAR}:${COLT_JAR}:${JSAP_JAR}:${JOCL_JAR} phylonet/util/BitSet*.java phylonet/coalescent/*.java phylonet/tree/model/sti/*.java phylonet/tree/io/NewickWriter.java phylonet/coalescent/gpu/*.java"
    exit 1
fi

# Check if all required JAR files exist
for jar in "${MAIN_JAR}" "${COLT_JAR}" "${JSAP_JAR}" "${JOCL_JAR}" "${JNA_JAR}" "${JNA_PLATFORM_JAR}"; do
    if [ ! -f "$jar" ]; then
        echo "Error: Required JAR file not found: $jar"
        exit 1
    fi
done

# Show GPU support status
check_gpu_support

# Run ASTRAL with all provided arguments
echo "Running Enhanced ASTRAL with arguments: $@"
echo "============================================"

# Change to main directory to match your working command pattern
cd "${MAIN_DIR}"

# Execute ASTRAL with enhanced library path configuration
java -Xms2g -Xmx8g \
     -Djava.library.path="${JAVA_LIBRARY_PATH}" \
     -Djna.library.path="${JNA_LIBRARY_PATH}" \
     -Djna.debug_load=false \
     -Djna.platform.library.path="${JNA_LIBRARY_PATH}" \
     -classpath "${CLASSPATH}" \
     phylonet.coalescent.CommandLine "$@"

# Capture exit code
exit_code=$?

echo ""
echo "Enhanced ASTRAL finished with exit code: $exit_code"

# Show final GPU status
if [ $exit_code -eq 0 ]; then
    echo "✓ Execution completed successfully"
else
    echo "⚠ Execution completed with warnings/errors"
fi

exit $exit_code
