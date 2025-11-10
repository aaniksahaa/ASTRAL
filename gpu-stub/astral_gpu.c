#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Structure for bipartition data
typedef struct {
    void* cluster1;
    void* cluster2;
    int bitsetSize;
} Bipartition;

// Test function to verify GPU availability
int testGPUAvailability() {
    // For now, return 1 (GPU not available) to gracefully fall back to CPU
    // This can be enhanced later to actually detect GPU
    printf("JNA GPU stub: testGPUAvailability called\n");
    return 1; // Return 1 = GPU not available (graceful fallback)
}

// Get GPU device count
int getGPUDeviceCount() {
    printf("JNA GPU stub: getGPUDeviceCount called\n");
    return 0; // No GPU devices available in stub
}

// Get GPU device name
const char* getGPUDeviceName(int deviceIndex) {
    printf("JNA GPU stub: getGPUDeviceName called for device %d\n", deviceIndex);
    return "GPU Stub Device";
}

// GPU weight calculation function (stub)
void launchWeightCalculation(
    Bipartition* candidates,
    Bipartition* geneTreeBips,
    int* frequencies,
    double* weights,
    int numCandidates,
    int numGeneTreeBips,
    int bitsetSize
) {
    printf("JNA GPU stub: launchWeightCalculation called (not implemented)\n");
    // This is a stub - actual implementation would go here
    // For now, just return without doing anything
}
