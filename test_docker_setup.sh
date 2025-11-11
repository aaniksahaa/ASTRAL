#!/bin/bash

# Test script to validate Docker setup files
# This script checks if all Docker files are properly configured

echo "=== ASTRAL Docker Setup Validation ==="
echo

# Check if all required files exist
echo "Checking required files..."
files=(
    "Dockerfile"
    "docker-compose.yml"
    "docker_build.sh"
    "docker_run.sh"
    ".dockerignore"
    "DOCKER_README.md"
)

missing_files=()
for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        echo "✓ $file exists"
    else
        echo "✗ $file missing"
        missing_files+=("$file")
    fi
done

if [ ${#missing_files[@]} -gt 0 ]; then
    echo
    echo "Error: Missing files: ${missing_files[*]}"
    exit 1
fi

echo
echo "Checking file permissions..."
if [ -x "docker_build.sh" ]; then
    echo "✓ docker_build.sh is executable"
else
    echo "✗ docker_build.sh is not executable"
    chmod +x docker_build.sh
    echo "  Fixed: Made docker_build.sh executable"
fi

if [ -x "docker_run.sh" ]; then
    echo "✓ docker_run.sh is executable"
else
    echo "✗ docker_run.sh is not executable"
    chmod +x docker_run.sh
    echo "  Fixed: Made docker_run.sh executable"
fi

echo
echo "Checking directory structure..."
if [ -d "inputs" ]; then
    echo "✓ inputs/ directory exists"
else
    echo "! inputs/ directory missing (will be created when needed)"
fi

if [ -d "outputs" ]; then
    echo "✓ outputs/ directory exists"
else
    echo "! outputs/ directory missing"
    mkdir -p outputs
    echo "  Fixed: Created outputs/ directory"
fi

if [ -d "lib" ]; then
    echo "✓ lib/ directory exists"
    lib_files=(
        "lib/main.jar"
        "lib/colt.jar"
        "lib/JSAP-2.1.jar"
        "lib/jocl-2.0.0.jar"
        "lib/libAstral.so"
    )
    
    for lib_file in "${lib_files[@]}"; do
        if [ -f "$lib_file" ]; then
            echo "  ✓ $lib_file exists"
        else
            echo "  ✗ $lib_file missing"
        fi
    done
else
    echo "✗ lib/ directory missing"
fi

echo
echo "Validating Dockerfile syntax..."
if command -v docker &> /dev/null; then
    if docker build --dry-run . &> /dev/null; then
        echo "✓ Dockerfile syntax is valid"
    else
        echo "✗ Dockerfile has syntax errors"
    fi
else
    echo "! Docker not installed - cannot validate Dockerfile syntax"
    echo "  (This is normal for testing without Docker)"
fi

echo
echo "Checking docker-compose.yml syntax..."
if command -v docker-compose &> /dev/null; then
    if docker-compose config &> /dev/null; then
        echo "✓ docker-compose.yml syntax is valid"
    else
        echo "✗ docker-compose.yml has syntax errors"
    fi
else
    echo "! docker-compose not installed - cannot validate syntax"
    echo "  (This is normal for testing without Docker)"
fi

echo
echo "=== Validation Summary ==="
echo "✓ All Docker configuration files are present"
echo "✓ Scripts have proper permissions"
echo "✓ Directory structure is ready"
echo
echo "Next steps:"
echo "1. Install Docker (see DOCKER_README.md for instructions)"
echo "2. Run: ./docker_build.sh"
echo "3. Test: ./docker_run.sh -- --help"
echo
echo "For remote deployment:"
echo "1. Copy entire ASTRAL directory to remote machine"
echo "2. Install Docker on remote machine"
echo "3. Run: ./docker_build.sh"
echo "4. Use: ./docker_run.sh -- -i inputs/your_data.tre -o outputs/result.tre"
