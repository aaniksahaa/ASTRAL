#!/bin/bash

# ASTRAL Docker Run Script
# This script runs ASTRAL in a Docker container

set -e  # Exit on any error

# Default settings
DOCKER_IMAGE="astral:latest"
MEMORY="4g"
CPUS="4"
GPU_SUPPORT="auto"  # auto, nvidia, none
CPU_ONLY=false

# Function to show usage
show_usage() {
    echo "ASTRAL Docker Runner"
    echo "==================="
    echo
    echo "Usage: $0 [docker_options] -- [astral_options]"
    echo
    echo "Docker Options:"
    echo "  --memory MEM     Set memory limit (default: 4g)"
    echo "  --cpus N         Set CPU limit (default: 4)"
    echo "  --gpu TYPE       GPU support: auto|nvidia|none (default: auto)"
    echo "  --cpu-only       Force CPU-only mode (disable GPU)"
    echo "  --interactive    Run in interactive mode"
    echo "  --help           Show this help"
    echo
    echo "ASTRAL Options (after --):"
    echo "  -i FILE          Input gene trees file"
    echo "  -o FILE          Output species tree file"
    echo "  -C               CPU-only mode"
    echo "  -T N             Number of threads"
    echo "  -G LIST          GPU indices"
    echo "  --help           Show ASTRAL help"
    echo
    echo "Examples:"
    echo "  $0 -- --help"
    echo "  $0 -- -i inputs/in200.tr -o outputs/out.tre"
    echo "  $0 --memory 8g --cpus 8 -- -i inputs/large.tre -o outputs/result.tre"
    echo "  $0 --cpu-only -- -i inputs/in200.tr -o outputs/out.tre -C"
    echo "  $0 --gpu nvidia -- -i inputs/in200.tr -o outputs/out.tre -G 0,1"
    echo
}

# Parse arguments
DOCKER_ARGS=()
ASTRAL_ARGS=()
PARSING_ASTRAL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            show_usage
            exit 0
            ;;
        --memory)
            MEMORY="$2"
            shift 2
            ;;
        --cpus)
            CPUS="$2"
            shift 2
            ;;
        --gpu)
            GPU_SUPPORT="$2"
            shift 2
            ;;
        --cpu-only)
            CPU_ONLY=true
            shift
            ;;
        --interactive)
            DOCKER_ARGS+=("-it")
            shift
            ;;
        --)
            PARSING_ASTRAL=true
            shift
            ;;
        *)
            if [ "$PARSING_ASTRAL" = true ]; then
                ASTRAL_ARGS+=("$1")
            else
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
            fi
            shift
            ;;
    esac
done

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed. Please install Docker first."
    exit 1
fi

# Function to run docker with sudo if needed
run_docker() {
    if docker ps &> /dev/null; then
        docker "$@"
    else
        echo "Note: Using sudo for Docker commands due to permission requirements"
        sudo docker "$@"
    fi
}

# Check if image exists
if ! run_docker image inspect "$DOCKER_IMAGE" &> /dev/null; then
    echo "Error: Docker image '$DOCKER_IMAGE' not found."
    echo "Please run './docker_build.sh' first to build the image."
    exit 1
fi

# Create output directory if it doesn't exist
mkdir -p outputs

# Build Docker run command
DOCKER_CMD=(
    "run" "--rm"
    "-v" "$(pwd)/inputs:/astral/inputs:ro"
    "-v" "$(pwd)/outputs:/astral/outputs:rw"
    "-v" "$(pwd)/data:/astral/data:ro"
    "-e" "JAVA_OPTS=-Xmx${MEMORY}"
    "--memory=${MEMORY}"
    "--cpus=${CPUS}"
)

# Add Docker args (like -it for interactive)
DOCKER_CMD+=("${DOCKER_ARGS[@]}")

# Handle GPU support
if [ "$CPU_ONLY" = true ]; then
    echo "Running in CPU-only mode..."
    DOCKER_CMD+=("--entrypoint" "/astral/astral_cpu.sh")
elif [ "$GPU_SUPPORT" = "nvidia" ]; then
    echo "Enabling NVIDIA GPU support..."
    DOCKER_CMD+=("--runtime=nvidia" "-e" "NVIDIA_VISIBLE_DEVICES=all")
elif [ "$GPU_SUPPORT" = "auto" ]; then
    # Try to detect GPU support
    if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
        # Check if nvidia-docker runtime is available
        if run_docker info 2>/dev/null | grep -q "nvidia"; then
            echo "NVIDIA GPU detected with nvidia-docker runtime, enabling GPU support..."
            DOCKER_CMD+=("--runtime=nvidia" "-e" "NVIDIA_VISIBLE_DEVICES=all")
        else
            echo "NVIDIA GPU detected, using device passthrough and library mounting..."
            # Pass through NVIDIA devices directly
            for device in /dev/nvidia*; do
                if [ -e "$device" ]; then
                    echo "Adding device: $device"
                    DOCKER_CMD+=("--device=$device:$device")
                fi
            done
            
            # Mount NVIDIA libraries from host
            echo "Mounting NVIDIA libraries from host..."
            
            # Mount specific OpenCL libraries
            OPENCL_LIBS=(
                "/usr/lib/x86_64-linux-gnu/libOpenCL.so"
                "/usr/lib/x86_64-linux-gnu/libOpenCL.so.1"
                "/usr/lib/x86_64-linux-gnu/libOpenCL.so.1.0.0"
                "/usr/lib/x86_64-linux-gnu/libnvidia-opencl.so.1"
                "/usr/lib/x86_64-linux-gnu/libnvidia-opencl.so.580.95.05"
            )
            
            for lib in "${OPENCL_LIBS[@]}"; do
                if [ -f "$lib" ]; then
                    echo "Mounting OpenCL library: $lib"
                    DOCKER_CMD+=("-v" "$lib:$lib:ro")
                fi
            done
            
            # Mount only NVIDIA-specific libraries to avoid glibc conflicts
            echo "Mounting additional NVIDIA dependencies..."
            
            # Find and mount NVIDIA-specific libraries only
            NVIDIA_LIBS=(
                "/usr/lib/x86_64-linux-gnu/libnvidia-ml.so.1"
                "/usr/lib/x86_64-linux-gnu/libnvidia-cfg.so.1"
                "/usr/lib/x86_64-linux-gnu/libnvidia-compiler.so.580.95.05"
                "/usr/lib/x86_64-linux-gnu/libnvidia-ptxjitcompiler.so.1"
            )
            
            for lib in "${NVIDIA_LIBS[@]}"; do
                if [ -f "$lib" ]; then
                    echo "Mounting NVIDIA library: $lib"
                    DOCKER_CMD+=("-v" "$lib:$lib:ro")
                fi
            done
            
            # Also try to find any other nvidia libraries dynamically
            for lib in /usr/lib/x86_64-linux-gnu/libnvidia-*.so*; do
                if [ -f "$lib" ] && [[ ! "$lib" =~ (libc|libm|libdl|libpthread|librt) ]]; then
                    echo "Mounting additional NVIDIA library: $lib"
                    DOCKER_CMD+=("-v" "$lib:$lib:ro")
                fi
            done
            
            # Add device access for Intel/AMD GPUs if available
            if [ -d "/dev/dri" ]; then
                DOCKER_CMD+=("--device=/dev/dri:/dev/dri")
            fi
            
            # Set environment variables for NVIDIA
            DOCKER_CMD+=("-e" "NVIDIA_VISIBLE_DEVICES=all")
            DOCKER_CMD+=("-e" "NVIDIA_DRIVER_CAPABILITIES=compute,utility")
        fi
    else
        echo "No NVIDIA GPU detected, running with OpenCL fallback..."
        # Add device access for Intel/AMD GPUs if available
        if [ -d "/dev/dri" ]; then
            DOCKER_CMD+=("--device=/dev/dri:/dev/dri")
        fi
    fi
fi

# Add image name
DOCKER_CMD+=("$DOCKER_IMAGE")

# Add ASTRAL arguments
DOCKER_CMD+=("${ASTRAL_ARGS[@]}")

# Show the command being executed (for debugging)
echo "Executing: run_docker ${DOCKER_CMD[*]}"
echo "=========================="

# Execute the command using our wrapper function
run_docker "${DOCKER_CMD[@]}"
