package phylonet.coalescent.gpu;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;

import org.jocl.*;
import static org.jocl.CL.*;

// JNA imports removed - focusing on OpenCL robustness instead of CUDA fallback

import phylonet.coalescent.Logging;
import phylonet.coalescent.Threading;

/**
 * Unified GPU Manager that handles both JOCL (OpenCL) and JNA (CUDA) approaches.
 * This provides a robust fallback mechanism when OpenCL is not available.
 */
public class GPUManager {
    
    public enum GPUBackend {
        JOCL_OPENCL,    // ASTRAL approach using JOCL/OpenCL with enhanced error handling
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
    
    // Enhanced OpenCL diagnostics
    private static String[] detectedPlatforms;
    private static String[] detectedDevices;
    
    /**
     * Initialize GPU support with robust fallback mechanism
     */
    public static boolean initializeGPU(boolean cpuOnly, String gpuSelection) {
        Logging.log("=== Enhanced GPUManager.initializeGPU() called ===");
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
        
        // Try enhanced JOCL/OpenCL initialization with better error handling
        if (tryInitializeEnhancedJOCL(gpuSelection)) {
            currentBackend = GPUBackend.JOCL_OPENCL;
            initialized = true;
            Logging.log("GPU initialized successfully using enhanced JOCL/OpenCL backend");
            return true;
        }
        
        // No GPU available - provide detailed diagnostics
        currentBackend = GPUBackend.CPU_ONLY;
        initialized = true;
        Logging.log("GPU acceleration not available. Using CPU-only computation.");
        Logging.log("GPU initialization details: " + lastError);
        return false;
    }
    
    /**
     * Try to initialize enhanced JOCL/OpenCL with better error handling and diagnostics
     */
    private static boolean tryInitializeEnhancedJOCL(String gpuSelection) {
        try {
            // Set up library paths for better OpenCL discovery
            setupOpenCLLibraryPaths();
            
            final int platformIndex = 0;
            final long deviceType = CL_DEVICE_TYPE_ALL;
            
            // Enable exceptions for better error reporting
            CL.setExceptionsEnabled(true);
            
            Logging.log("Attempting OpenCL initialization...");
            
            // Obtain the number of platforms
            int numPlatformsArray[] = new int[1];
            clGetPlatformIDs(0, null, numPlatformsArray);
            int numPlatforms = numPlatformsArray[0];
            
            if (numPlatforms == 0) {
                lastError = "No OpenCL platforms found. Check if OpenCL drivers are installed.";
                return false;
            }
            
            Logging.log("Found " + numPlatforms + " OpenCL platform(s)");
            
            // Obtain platform IDs and log details
            cl_platform_id platforms[] = new cl_platform_id[numPlatforms];
            clGetPlatformIDs(platforms.length, platforms, null);
            
            // Store platform info for diagnostics
            detectedPlatforms = new String[numPlatforms];
            for (int i = 0; i < numPlatforms; i++) {
                String platformName = getString(platforms[i], CL_PLATFORM_NAME);
                String platformVendor = getString(platforms[i], CL_PLATFORM_VENDOR);
                detectedPlatforms[i] = platformName + " (" + platformVendor + ")";
                Logging.log("Platform " + i + ": " + detectedPlatforms[i]);
            }
            
            if (platformIndex >= numPlatforms) {
                lastError = "Platform index " + platformIndex + " not available. Only " + numPlatforms + " platform(s) found.";
                return false;
            }
            
            cl_platform_id platform = platforms[platformIndex];
            
            // Initialize the context properties
            contextProperties = new cl_context_properties();
            contextProperties.addProperty(CL_CONTEXT_PLATFORM, platform);
            
            // Obtain the number of devices for the platform
            int numDevicesArray[] = new int[1];
            clGetDeviceIDs(platform, deviceType, 0, null, numDevicesArray);
            int numDevices = numDevicesArray[0];
            
            if (numDevices == 0) {
                lastError = "No OpenCL devices found on platform: " + detectedPlatforms[platformIndex];
                return false;
            }
            
            Logging.log("Found " + numDevices + " OpenCL device(s) on platform " + platformIndex);
            
            // Obtain device IDs
            cl_device_id devices[] = new cl_device_id[numDevices];
            clGetDeviceIDs(platform, deviceType, numDevices, devices, null);
            Arrays.sort(devices, new Comparator<cl_device_id>() {
                @Override
                public int compare(cl_device_id arg0, cl_device_id arg1) {
                    return getString(arg0, CL_DEVICE_NAME).compareTo(getString(arg1, CL_DEVICE_NAME));
                }
            });
            
            // Store device info for diagnostics
            detectedDevices = new String[numDevices];
            Logging.log("Detected OpenCL GPU devices:");
            for (int i = 0; i < numDevices; i++) {
                String deviceName = getString(devices[i], CL_DEVICE_NAME);
                String deviceVendor = getString(devices[i], CL_DEVICE_VENDOR);
                String deviceTypeStr = getDeviceTypeString(devices[i]);
                detectedDevices[i] = deviceName + " (" + deviceVendor + ", " + deviceTypeStr + ")";
                Logging.log("  Device " + (i + 1) + " of " + numDevices + ": " + detectedDevices[i]);
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
            Logging.log("OpenCL Exception: " + e.getClass().getSimpleName() + ": " + e.getMessage());
            e.printStackTrace();
            return false;
        } catch (Error e) {
            lastError = "JOCL/OpenCL initialization error: " + e.getMessage();
            Logging.log("OpenCL Error: " + e.getClass().getSimpleName() + ": " + e.getMessage());
            e.printStackTrace();
            return false;
        }
    }
    
    /**
     * Set up library paths to help OpenCL discovery
     */
    private static void setupOpenCLLibraryPaths() {
        // System OpenCL library locations (prioritize system libraries over bundled ones)
        String[] systemPaths = {
            "/usr/lib/x86_64-linux-gnu",
            "/usr/lib64",
            "/usr/local/lib",
            "/usr/local/lib64",
            "/opt/cuda/lib64",
            "/usr/local/cuda/lib64"
        };
        
        // Get current library path
        String currentPath = System.getProperty("java.library.path", "");
        
        // Build new path with system libraries first (higher priority)
        StringBuilder newPath = new StringBuilder();
        
        // Add system paths first
        for (String path : systemPaths) {
            if (newPath.length() > 0) {
                newPath.append(":");
            }
            newPath.append(path);
        }
        
        // Add current path (including bundled libraries) after system paths
        if (!currentPath.isEmpty()) {
            newPath.append(":").append(currentPath);
        }
        
        // Update library path
        System.setProperty("java.library.path", newPath.toString());
        
        Logging.log("Enhanced library path (system libraries prioritized): " + newPath.toString());
        
        // Also try to force reload of native libraries
        try {
            // Clear any cached library mappings
            java.lang.reflect.Field fieldSysPath = ClassLoader.class.getDeclaredField("sys_paths");
            fieldSysPath.setAccessible(true);
            fieldSysPath.set(null, null);
            Logging.log("Native library cache cleared for fresh loading");
        } catch (Exception e) {
            Logging.log("Could not clear native library cache: " + e.getMessage());
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
     * Get string property from OpenCL platform
     */
    private static String getString(cl_platform_id platform, int paramName) {
        long size[] = new long[1];
        clGetPlatformInfo(platform, paramName, 0, null, size);
        byte buffer[] = new byte[(int) size[0]];
        clGetPlatformInfo(platform, paramName, buffer.length, org.jocl.Pointer.to(buffer), null);
        return new String(buffer, 0, buffer.length - 1);
    }
    
    /**
     * Get device type as human-readable string
     */
    private static String getDeviceTypeString(cl_device_id device) {
        long[] deviceType = new long[1];
        clGetDeviceInfo(device, CL_DEVICE_TYPE, 8, org.jocl.Pointer.to(deviceType), null);
        
        switch ((int) deviceType[0]) {
            case (int) CL_DEVICE_TYPE_CPU:
                return "CPU";
            case (int) CL_DEVICE_TYPE_GPU:
                return "GPU";
            case (int) CL_DEVICE_TYPE_ACCELERATOR:
                return "Accelerator";
            case (int) CL_DEVICE_TYPE_DEFAULT:
                return "Default";
            default:
                return "Unknown (0x" + Long.toHexString(deviceType[0]) + ")";
        }
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
     * Get detected platforms for diagnostics
     */
    public static String[] getDetectedPlatforms() {
        return detectedPlatforms;
    }
    
    /**
     * Get detected devices for diagnostics
     */
    public static String[] getDetectedDevices() {
        return detectedDevices;
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
        detectedPlatforms = null;
        detectedDevices = null;
    }
}
