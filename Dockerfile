# ASTRAL Docker Image
# This image includes OpenCL support and all native libraries for GPU acceleration
FROM ubuntu:22.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Set working directory
WORKDIR /astral

# Install system dependencies
# Note: apt-get update is required to refresh package lists
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Java runtime (using Java 21 to match compiled classes)
    openjdk-21-jdk \
    # OpenCL support
    ocl-icd-opencl-dev \
    opencl-headers \
    clinfo \
    # Intel OpenCL runtime (for Intel GPUs/CPUs)
    intel-opencl-icd \
    # NVIDIA OpenCL support (will work if NVIDIA drivers are available)
    nvidia-opencl-dev \
    # AMD OpenCL support
    mesa-opencl-icd \
    # Build tools (in case we need to compile native libraries)
    build-essential \
    gcc \
    g++ \
    make \
    # Utilities
    wget \
    curl \
    unzip \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Set JAVA_HOME
ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
ENV PATH=$PATH:$JAVA_HOME/bin

# Create OpenCL ICD directory and ensure proper permissions
RUN mkdir -p /etc/OpenCL/vendors && \
    echo "libnvidia-opencl.so.1" > /etc/OpenCL/vendors/nvidia.icd && \
    echo "libintelocl.so" > /etc/OpenCL/vendors/intel.icd && \
    echo "libmesaopencl.so.1" > /etc/OpenCL/vendors/mesa.icd && \
    # Create symlinks for common OpenCL library locations
    mkdir -p /usr/local/cuda/lib64 && \
    # Ensure OpenCL library can be found
    ldconfig

# Copy ASTRAL files
COPY . /astral/

# Ensure lib directory has proper permissions and create symlinks if needed
RUN chmod -R 755 /astral/lib/ && \
    # Create a fallback OpenCL library if none exists
    if [ ! -f /usr/lib/x86_64-linux-gnu/libOpenCL.so ]; then \
        ln -s /usr/lib/x86_64-linux-gnu/libOpenCL.so.1 /usr/lib/x86_64-linux-gnu/libOpenCL.so 2>/dev/null || true; \
    fi

# Set library path for native libraries
ENV LD_LIBRARY_PATH=/astral/lib:/usr/lib/x86_64-linux-gnu:/usr/local/cuda/lib64:/usr/local/nvidia/lib:/usr/local/nvidia/lib64:$LD_LIBRARY_PATH

# Make scripts executable
RUN chmod +x /astral/run_astral.sh /astral/make.sh 2>/dev/null || true

# Test native library loading (optional, for debugging)
RUN java -Djava.library.path=/astral/lib -jar /astral/native_library_tester.jar 2>/dev/null || echo "Native library test completed (may show warnings, this is normal)"

# Create a wrapper script for easier execution
RUN echo '#!/bin/bash\n\
# ASTRAL Docker Wrapper\n\
cd /astral/main\n\
\n\
# Check if OpenCL is available\n\
echo "=== OpenCL Information ==="\n\
clinfo 2>/dev/null || echo "OpenCL info not available (this is normal if no GPU is present)"\n\
echo "========================"\n\
echo\n\
\n\
# Run ASTRAL with proper library paths and classpath\n\
exec java -Djava.library.path=/astral/lib -classpath ".:/astral/lib/main.jar:/astral/lib/colt.jar:/astral/lib/JSAP-2.1.jar:/astral/lib/jocl-2.0.0.jar" phylonet.coalescent.CommandLine "$@"\n\
' > /astral/astral_docker.sh && chmod +x /astral/astral_docker.sh

# Create a CPU-only wrapper for machines without GPU support
RUN echo '#!/bin/bash\n\
# ASTRAL Docker Wrapper (CPU-only)\n\
cd /astral/main\n\
echo "Running ASTRAL in CPU-only mode..."\n\
exec java -Djava.library.path=/astral/lib -classpath ".:/astral/lib/main.jar:/astral/lib/colt.jar:/astral/lib/JSAP-2.1.jar:/astral/lib/jocl-2.0.0.jar" phylonet.coalescent.CommandLine -C "$@"\n\
' > /astral/astral_cpu.sh && chmod +x /astral/astral_cpu.sh

# Set default command
ENTRYPOINT ["/astral/astral_docker.sh"]
CMD ["--help"]

# Expose any ports if needed (none for ASTRAL)
# EXPOSE 8080

# Add labels for metadata
LABEL maintainer="ASTRAL User"
LABEL description="ASTRAL phylogenetic tree inference with GPU support"
LABEL version="5.15.5"
