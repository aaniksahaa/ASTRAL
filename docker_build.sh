#!/bin/bash

# ASTRAL Docker Build Script
# This script builds the Docker image for ASTRAL

set -e  # Exit on any error

echo "=== Building ASTRAL Docker Image ==="
echo "This may take several minutes..."
echo

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed. Please install Docker first."
    exit 1
fi

# Check if we're in the ASTRAL directory
if [ ! -f "Dockerfile" ]; then
    echo "Error: Dockerfile not found. Please run this script from the ASTRAL directory."
    exit 1
fi

# Create necessary directories
echo "Creating output directories..."
mkdir -p outputs data

# Build the Docker image
echo "Building Docker image..."
docker build -t astral:latest .

# Check if build was successful
if [ $? -eq 0 ]; then
    echo
    echo "=== Build Successful! ==="
    echo "Docker image 'astral:latest' has been created."
    echo
    echo "To test the installation, run:"
    echo "  ./docker_run.sh --help"
    echo
    echo "To run with your data:"
    echo "  ./docker_run.sh -i inputs/your_input.tre -o outputs/output.tre"
    echo
else
    echo
    echo "=== Build Failed! ==="
    echo "Please check the error messages above."
    exit 1
fi
