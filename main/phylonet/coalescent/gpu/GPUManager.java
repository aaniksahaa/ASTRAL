package phylonet.coalescent.gpu;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;

import org.jocl.*;
import static org.jocl.CL.*;

import com.sun.jna.Library;
import com.sun.jna.Native;
import com.sun.jna.Structure;

import phylonet.coalescent.Logging;
import phylonet.coalescent.Threading;

/**
 * Unified GPU Manager that handles both JOCL (OpenCL) and JNA (CUDA) approaches.
 * This provides a robust fallback mechanism when OpenCL is not available.
 */
public class GPUManager {
    
    public enum GPUBackend {
        JOCL_OPENCL,    // Original ASTRAL approach using JOCL/OpenCL
        JNA_CUDA,       // Stelar-style approach using JNA/CUDA
        CPU_ONLY        // No GPU acceleration
    }
    
    private static GPUBackend currentBackend = GPUBackend.CPU_ONLY;
    private static boolean initialized = false;
    private static String lastError = "";
    
    // JOCL/OpenCL related fields (original ASTRAL approach)
    private static cl_context_properties contextProperties;
    private static cl_context[] context;
    private static cl_device_id[] usedDevices;
    private static String[] deviceVendors;
    
    // JNA/CUDA related fields (Stelar-style approach)
    private static CudaWeightCalcLib cudaLib;
    
    /**
     * JNA interface for CUDA-based weight calculation (Stelar-style)
     */
    public interface CudaWeightCalcLib extends Library {
        // Structure for bipartition data
        @Structure.FieldOrder({"cluster1", "cluster2", "bitsetSize"})
        public static class Bipartition extends Structure {
            public com.sun.jna.Pointer cluster1;
            public com.sun.jna.Pointer cluster2;
            public int bitsetSize;
            
            public Bipartition() {
                super();
            }
        }
        
        // CUDA weight calculation function
        void launchWeightCalculation(
            Bipartition[] candidates,
            Bipartition[] geneTreeBips,
            int[] frequencies,
            double[] weights,
            int numCandidates,
            int numGeneTreeBips,
            int bitsetSize
        );
        
        // Test function to verify CUDA availability
        int testCudaAvailability();
    }
    
    /**
     * Initialize GPU support with robust fallback mechanism
     */
    public static boolean initializeGPU(boolean cpuOnly, String gpuSelection) {
        if (initialized) {
            return currentBackend != GPUBackend.CPU_ONLY;
        }
        
        if (cpuOnly) {
            Logging.log("GPU disabled by user request (CPU-only mode)");
            currentBackend = GPUBackend.CPU_ONLY;
            initialized = true;
            return false;
        }
        
        // Try JOCL/OpenCL first (original ASTRAL approach)
        if (tryInitializeJOCL(gpuSelection)) {
            currentBackend = GPUBackend.JOCL_OPENCL;
            initialized = true;
            Logging.log("GPU initialized successfully using JOCL/OpenCL backend");
            return true;
        }
        
        // Fallback to JNA/CUDA (Stelar-style approach)
        if (tryInitializeCUDA()) {
            currentBackend = GPUBackend.JNA_CUDA;
            initialized = true;
            Logging.log("GPU initialized successfully using JNA/CUDA backend (fallback)");
            return true;
        }
        
        // No GPU available
        currentBackend = GPUBackend.CPU_ONLY;
        initialized = true;
        Logging.log("Warning: No GPU backend available. Using CPU-only computation.");
        Logging.log("Last error: " + lastError);
        return false;
    }
    
    /**
     * Try to initialize JOCL/OpenCL (original ASTRAL approach)
     */
    private static boolean tryInitializeJOCL(String gpuSelection) {
        try {
            final int platformIndex = 0;
            final long deviceType = CL_DEVICE_TYPE_ALL;
            
            // Enable exceptions and subsequently omit error checks
            CL.setExceptionsEnabled(true);
            
            // Obtain the number of platforms
            int numPlatformsArray[] = new int[1];
            clGetPlatformIDs(0, null, numPlatformsArray);
            int numPlatforms = numPlatformsArray[0];
            
            if (numPlatforms == 0) {
                lastError = "No OpenCL platforms found";
                return false;
            }
            
            // Obtain a platform ID
            cl_platform_id platforms[] = new cl_platform_id[numPlatforms];
            clGetPlatformIDs(platforms.length, platforms, null);
            cl_platform_id platform = platforms[platformIndex];
            
            // Initialize the context properties
            contextProperties = new cl_context_properties();
            contextProperties.addProperty(CL_CONTEXT_PLATFORM, platform);
            
            // Obtain the number of devices for the platform
            int numDevicesArray[] = new int[1];
            clGetDeviceIDs(platform, deviceType, 0, null, numDevicesArray);
            int numDevices = numDevicesArray[0];
            
            if (numDevices == 0) {
                lastError = "No OpenCL devices found";
                return false;
            }
            
            // Obtain device IDs
            cl_device_id devices[] = new cl_device_id[numDevices];
            clGetDeviceIDs(platform, deviceType, numDevices, devices, null);
            Arrays.sort(devices, new Comparator<cl_device_id>() {
                @Override
                public int compare(cl_device_id arg0, cl_device_id arg1) {
                    return getString(arg0, CL_DEVICE_NAME).compareTo(getString(arg1, CL_DEVICE_NAME));
                }
            });
            
            Logging.log("Detected OpenCL GPU devices: ");
            for (int i = 0; i < numDevices; i++) {
                String deviceName = getString(devices[i], CL_DEVICE_NAME);
                String deviceVendor = getString(devices[i], CL_DEVICE_VENDOR);
                Logging.log("Device " + (i + 1) + " of " + numDevices + ": " + deviceName + 
                           " Vendor: " + deviceVendor);
            }
            
            // Select devices based on user preference
            ArrayList<cl_device_id> usedGPUs = new ArrayList<cl_device_id>();
            if (gpuSelection != null) {
                try {
                    for (String si : gpuSelection.split(",")) {
                        int deviceIndex = Integer.parseInt(si) - 1;
                        if (deviceIndex >= 0 && deviceIndex < numDevices) {
                            if (!usedGPUs.contains(devices[deviceIndex])) {
                                usedGPUs.add(devices[deviceIndex]);
                            }
                        }
                    }
                } catch (Exception e) {
                    lastError = "Could not parse GPU selection '" + gpuSelection + "': " + e.getMessage();
                    return false;
                }
            } else {
                // Use all available devices
                for (int i = 0; i < devices.length; i++) {
                    usedGPUs.add(devices[i]);
                }
            }
            
            if (usedGPUs.isEmpty()) {
                lastError = "No valid GPU devices selected";
                return false;
            }
            
            // Set up Threading class variables (for backward compatibility)
            ArrayList<cl_device_id> usedDevicesAL = new ArrayList<cl_device_id>();
            ArrayList<String> deviceVendorsAL = new ArrayList<String>();
            for (cl_device_id d : usedGPUs) {
                deviceVendorsAL.add(getString(d, CL_DEVICE_VENDOR));
                usedDevicesAL.add(d);
                Logging.log("Will use OpenCL Device: " + getString(d, CL_DEVICE_NAME));
            }
            
            cl_device_id[] usedDevicesArray = new cl_device_id[usedDevicesAL.size()];
            usedDevicesArray = usedDevicesAL.toArray(usedDevicesArray);
            String[] deviceVendorsArray = new String[deviceVendorsAL.size()];
            deviceVendorsArray = deviceVendorsAL.toArray(deviceVendorsArray);
            cl_context[] contextArray = new cl_context[usedDevicesArray.length];
            
            for (int c = 0; c < usedDevicesArray.length; c++) {
                contextArray[c] = clCreateContext(contextProperties, 1,
                    new cl_device_id[]{usedDevicesArray[c]}, null, null, null);
            }
            
            // Set Threading variables using public setters
            Threading.setUsedDevices(usedDevicesArray);
            Threading.setDeviceVendors(deviceVendorsArray);
            Threading.setContext(contextArray);
            Threading.setContextProperties(contextProperties);
            
            return true;
            
        } catch (Exception e) {
            lastError = "JOCL/OpenCL initialization failed: " + e.getMessage();
            return false;
        } catch (Error e) {
            lastError = "JOCL/OpenCL initialization error: " + e.getMessage();
            return false;
        }
    }
    
    /**
     * Try to initialize JNA/CUDA (Stelar-style approach)
     */
    private static boolean tryInitializeCUDA() {
        try {
            // Try to load the CUDA library
            String[] possibleLibNames = {
                "weight_calc",           // Stelar-style library
                "cudart",               // CUDA runtime
                "cuda"                  // Generic CUDA
            };
            
            String[] possiblePaths = {
                System.getProperty("user.dir") + "/cuda",
                System.getProperty("user.dir") + "/lib",
                System.getProperty("user.dir") + "/stelar/cuda",
                "/usr/local/cuda/lib64",
                "/opt/cuda/lib64"
            };
            
            // Set library path for JNA
            for (String path : possiblePaths) {
                System.setProperty("jna.library.path", 
                    System.getProperty("jna.library.path", "") + ":" + path);
            }
            
            // Try to load the library
            for (String libName : possibleLibNames) {
                try {
                    cudaLib = Native.load(libName, CudaWeightCalcLib.class);
                    
                    // Test if CUDA is available
                    int result = cudaLib.testCudaAvailability();
                    if (result == 0) {
                        Logging.log("CUDA library '" + libName + "' loaded successfully");
                        return true;
                    } else {
                        Logging.log("CUDA library '" + libName + "' loaded but CUDA not available (code: " + result + ")");
                    }
                } catch (UnsatisfiedLinkError e) {
                    // Try next library name
                    continue;
                }
            }
            
            lastError = "No CUDA library could be loaded or CUDA runtime not available";
            return false;
            
        } catch (Exception e) {
            lastError = "JNA/CUDA initialization failed: " + e.getMessage();
            return false;
        }
    }
    
    /**
     * Get string property from OpenCL device
     */
    private static String getString(cl_device_id device, int paramName) {
        long size[] = new long[1];
        clGetDeviceInfo(device, paramName, 0, null, size);
        byte buffer[] = new byte[(int) size[0]];
        clGetDeviceInfo(device, paramName, buffer.length, org.jocl.Pointer.to(buffer), null);
        return new String(buffer, 0, buffer.length - 1);
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
     * Get CUDA library instance (for JNA backend)
     */
    public static CudaWeightCalcLib getCudaLib() {
        return cudaLib;
    }
    
    /**
     * Reset initialization state (for testing)
     */
    public static void reset() {
        initialized = false;
        currentBackend = GPUBackend.CPU_ONLY;
        lastError = "";
        contextProperties = null;
        context = null;
        usedDevices = null;
        deviceVendors = null;
        cudaLib = null;
    }
}
