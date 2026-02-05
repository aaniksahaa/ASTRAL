#!/bin/bash

# ASTRAL Runner Script
# This script runs ASTRAL using relative paths from the current directory
# NOTE: This script must be run from the ASTRAL root directory
# Usage: ./run_astral.sh -i input_file.tre [-o output_file.tre] [other_options]

# ./run_astral.sh -i ../inputs/in200.tr -o ./out.tr
# ./run_astral.sh -i ../inputs/1kp-2.tre -o ./out.tr

# Define ASTRAL root directory (current working directory)
ASTRAL_ROOT=$(pwd)

# Define paths based on ASTRAL_ROOT
MAIN_DIR="${ASTRAL_ROOT}/main"
LIB_DIR="${ASTRAL_ROOT}/lib"

# Required JAR files (using absolute paths based on ASTRAL_ROOT)
MAIN_JAR="${LIB_DIR}/main.jar"
COLT_JAR="${LIB_DIR}/colt.jar"
JSAP_JAR="${LIB_DIR}/JSAP-2.1.jar"
JOCL_JAR="${LIB_DIR}/jocl-2.0.0.jar"

# Build classpath (with absolute paths, but current directory as "." for compiled classes)
CLASSPATH=".:${MAIN_JAR}:${COLT_JAR}:${JSAP_JAR}:${JOCL_JAR}"

# Check if compiled classes exist
if [ ! -f "${MAIN_DIR}/phylonet/coalescent/CommandLine.class" ]; then
    echo "Error: Compiled classes not found. Please compile first:"
    echo "cd ${MAIN_DIR}"
    echo "javac -g -classpath ${MAIN_JAR}:${COLT_JAR}:${JSAP_JAR}:${JOCL_JAR} phylonet/util/BitSet*.java phylonet/coalescent/*.java phylonet/tree/model/sti/*.java phylonet/tree/io/NewickWriter.java"
    exit 1
fi

# Check if all required JAR files exist
for jar in "${MAIN_JAR}" "${COLT_JAR}" "${JSAP_JAR}" "${JOCL_JAR}"; do
    if [ ! -f "$jar" ]; then
        echo "Error: Required JAR file not found: $jar"
        exit 1
    fi
done

# Print usage if no arguments
if [ $# -eq 0 ]; then
    echo "ASTRAL Runner Script"
    echo "==================="
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
    exit 0
fi

# Print configuration
echo "ASTRAL Configuration:"
echo "===================="
echo "ASTRAL_ROOT: ${ASTRAL_ROOT}"
echo "MAIN_DIR:    ${MAIN_DIR}"
echo "LIB_DIR:     ${LIB_DIR}"
echo "CLASSPATH:   ${CLASSPATH}"
echo ""

# Run ASTRAL with all provided arguments
echo "Running ASTRAL with arguments: $@"
echo "================================"

# Change to main directory to match your working command pattern
cd "${MAIN_DIR}"

# Execute ASTRAL (following your exact working pattern)
java -classpath "${CLASSPATH}" phylonet.coalescent.CommandLine "$@"

# Capture exit code
exit_code=$?

echo ""
echo "ASTRAL finished with exit code: $exit_code"
exit $exit_code
