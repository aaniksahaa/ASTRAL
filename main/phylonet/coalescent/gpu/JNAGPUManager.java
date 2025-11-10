package phylonet.coalescent.gpu;

import com.sun.jna.Library;
import com.sun.jna.Native;
import com.sun.jna.Pointer;
import com.sun.jna.Structure;

import phylonet.coalescent.Logging;

/**
 * JNA-based GPU Manager - Stelar-style approach
 * This provides hassle-free GPU support using JNA instead of JOCL
 */
public class JNAGPUManager {
    
    public enum GPUBackend {
        JNA_CUDA,       // JNA-based CUDA (Stelar-style)
        CPU_ONLY        // No GPU acceleration
    }
    
    private static GPUBackend currentBackend = GPUBackend.CPU_ONLY;
    private static boolean initialized = false;
    private static String lastError = "";
    private static AstralGPULib gpuLib;
    
    /**
     * JNA interface for ASTRAL GPU operations (similar to Stelar's approach)
     */
    public interface AstralGPULib extends Library {
        // Structure for bipartition data
        @Structure.FieldOrder({"cluster1", "cluster2", "bitsetSize"})
        public static class Bipartition extends Structure {
            public Pointer cluster1;
            public Pointer cluster2;
            public int bitsetSize;
            
            public Bipartition() {
                super();
            }
        }
        
        // GPU weight calculation function
        void launchWeightCalculation(
            Bipartition[] candidates,
            Bipartition[] geneTreeBips,
            int[] frequencies,
            double[] weights,
            int numCandidates,
            int numGeneTreeBips,
            int bitsetSize
        );
        
        // Test function to verify GPU availability
        int testGPUAvailability();
        
        // Get GPU device count
        int getGPUDeviceCount();
        
        // Get GPU device name
        String getGPUDeviceName(int deviceIndex);
    }
    
    /**
     * Initialize GPU support using JNA (Stelar-style approach)
     */
    public static boolean initializeGPU(boolean cpuOnly, String gpuSelection) {
        Logging.log("=== JNA GPU Manager (Stelar-style) Initialization ===");
        Logging.log("CPU-only mode: " + cpuOnly);
        Logging.log("GPU selection: " + gpuSelection);
        
        if (initialized) {
            Logging.log("GPU already initialized, current backend: " + currentBackend);
            return currentBackend != GPUBackend.CPU_ONLY;
        }
        
        if (cpuOnly) {
            Logging.log("GPU disabled by user request (CPU-only mode)");
            currentBackend = GPUBackend.CPU_ONLY;
            initialized = true;
            return false;
        }
        
        // Try JNA-based GPU initialization (Stelar approach)
        if (tryInitializeJNAGPU()) {
            currentBackend = GPUBackend.JNA_CUDA;
            initialized = true;
            Logging.log("GPU initialized successfully using JNA backend (Stelar-style)");
            return true;
        }
        
        // No GPU available
        currentBackend = GPUBackend.CPU_ONLY;
        initialized = true;
        Logging.log("GPU acceleration not available. Using CPU-only computation.");
        Logging.log("GPU initialization details: " + lastError);
        return false;
    }
    
    /**
     * Try to initialize JNA-based GPU (Stelar-style approach)
     */
    private static boolean tryInitializeJNAGPU() {
        try {
            Logging.log("Attempting JNA-based GPU initialization (Stelar approach)...");
            
            // Set up library paths like Stelar does
            setupJNALibraryPaths();
            
            // Try to load GPU library
            String[] possibleLibNames = {
                "astral_gpu",           // Custom ASTRAL GPU library
                "weight_calc",          // Stelar-style library name
                "cudart",              // CUDA runtime
                "cuda"                 // Generic CUDA
            };
            
            for (String libName : possibleLibNames) {
                try {
                    Logging.log("Trying to load GPU library: " + libName);
                    gpuLib = Native.load(libName, AstralGPULib.class);
                    
                    // Test if GPU is available
                    int result = gpuLib.testGPUAvailability();
                    if (result == 0) {
                        Logging.log("GPU library '" + libName + "' loaded successfully");
                        
                        // Get GPU device information
                        int deviceCount = gpuLib.getGPUDeviceCount();
                        Logging.log("Found " + deviceCount + " GPU device(s)");
                        
                        for (int i = 0; i < deviceCount; i++) {
                            String deviceName = gpuLib.getGPUDeviceName(i);
                            Logging.log("  Device " + i + ": " + deviceName);
                        }
                        
                        return true;
                    } else {
                        Logging.log("GPU library '" + libName + "' loaded but GPU not available (code: " + result + ")");
                    }
                } catch (UnsatisfiedLinkError e) {
                    Logging.log("Could not load library '" + libName + "': " + e.getMessage());
                    continue;
                }
            }
            
            lastError = "No compatible GPU library could be loaded";
            return false;
            
        } catch (Exception e) {
            lastError = "JNA GPU initialization failed: " + e.getMessage();
            Logging.log("JNA GPU Exception: " + e.getClass().getSimpleName() + ": " + e.getMessage());
            return false;
        }
    }
    
    /**
     * Set up library paths for JNA (Stelar-style)
     */
    private static void setupJNALibraryPaths() {
        String[] possiblePaths = {
            System.getProperty("user.dir") + "/cuda",
            System.getProperty("user.dir") + "/lib",
            System.getProperty("user.dir") + "/lib-enhanced",
            "/usr/local/cuda/lib64",
            "/opt/cuda/lib64",
            "/usr/lib/x86_64-linux-gnu",
            "/usr/lib64"
        };
        
        // Set library path for JNA (like Stelar does)
        StringBuilder jnaPath = new StringBuilder();
        for (String path : possiblePaths) {
            if (jnaPath.length() > 0) {
                jnaPath.append(":");
            }
            jnaPath.append(path);
        }
        
        System.setProperty("jna.library.path", jnaPath.toString());
        System.setProperty("jna.platform.library.path", jnaPath.toString());
        
        Logging.log("JNA library path: " + jnaPath.toString());
    }
    
    /**
     * Get current GPU backend
     */
    public static GPUBackend getCurrentBackend() {
        return currentBackend;
    }
    
    /**
     * Check if GPU is available
     */
    public static boolean isGPUAvailable() {
        return currentBackend != GPUBackend.CPU_ONLY;
    }
    
    /**
     * Get last error message
     */
    public static String getLastError() {
        return lastError;
    }
    
    /**
     * Get GPU library instance
     */
    public static AstralGPULib getGPULib() {
        return gpuLib;
    }
    
    /**
     * Reset initialization state
     */
    public static void reset() {
        initialized = false;
        currentBackend = GPUBackend.CPU_ONLY;
        lastError = "";
        gpuLib = null;
    }
}
