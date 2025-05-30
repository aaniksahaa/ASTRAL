/**
 * OpenCL kernel for GPU-accelerated tripartition weight calculation in ASTRAL-MP.
 * 
 * This kernel implements the core mathematical computations from Equations 1-2 of the research
 * paper on massively parallel GPU hardware, achieving significant speedup over CPU-only
 * implementations for large phylogenomic datasets.
 * 
 * **Parallel Computation Strategy:**
 * Each work item (GPU thread) processes one tripartition independently, allowing simultaneous
 * weight calculation for hundreds or thousands of tripartitions across GPU cores. This
 * embarrassingly parallel approach is ideal for the ASTRAL algorithm's computation pattern.
 * 
 * **Mathematical Implementation:**
 * The kernel performs the same quartet-based weight calculation as the CPU version:
 * - Traverses gene trees encoded as integer sequences
 * - Maintains taxon count stacks for tripartition sides
 * - Computes quartet contributions using optimized F functions
 * - Accumulates weights across all gene trees
 * 
 * **Memory Access Optimization:**
 * - Uses global memory for input data (gene trees, tripartitions, taxon clusters)
 * - Employs local/private memory for computational stacks and intermediate values
 * - Minimizes memory bandwidth requirements through efficient data layouts
 * - Leverages GPU memory coalescing for optimal performance
 * 
 * **Architecture Considerations:**
 * - Designed for SIMD (Single Instruction, Multiple Data) execution model
 * - Optimized for high arithmetic intensity (computation-to-memory ratio)
 * - Handles divergent control flow efficiently (polytomy vs binary node processing)
 * - Supports large-scale parallel execution (thousands of concurrent work items)
 * 
 * **Integration with ASTRAL-MP:**
 * This GPU acceleration is part of the comprehensive parallelization strategy described
 * in Section 2.4.1, complementing CPU multithreading and vectorization optimizations
 * to maximize computational throughput on heterogeneous computing systems.
 * 
 * @see Section 2.4.1 for parallelization framework
 * @see Equations 1-2 for mathematical foundation
 * @author ASTRAL-MP development team
 */

__constant sampler_t sampler =
      CLK_NORMALIZED_COORDS_FALSE
    | CLK_ADDRESS_CLAMP_TO_EDGE
    | CLK_FILTER_NEAREST;

/**
 * Core quartet scoring function implementing the mathematical formula from the research paper.
 * 
 * This function computes the contribution of a specific quartet configuration to the overall
 * tripartition weight, following the same mathematical foundation as the CPU implementation.
 * 
 * The formula F(a, b, c) = (a + b + c - 3) × a × b × c accounts for:
 * - Combinatorial choices of taxa from each tripartition side
 * - Weighting factors for quartet topology support
 * - Constraint that exactly four taxa form each quartet
 * 
 * @param a Number of taxa from tripartition side A
 * @param b Number of taxa from tripartition side B  
 * @param c Number of taxa from tripartition side C
 * @return Quartet contribution weight for this configuration
 */
inline long F(long a, long b, long c) {
	return ((a + b + c - 3))*a*b*c;
}

/**
 * Optimized function for computing multiple quartet combinations simultaneously.
 * 
 * This function efficiently calculates all six possible quartet topologies that can be
 * formed from three groups of taxa, implementing the core quartet enumeration logic
 * required for accurate tripartition weight computation.
 * 
 * The function handles the combinatorial complexity of quartet formation by evaluating
 * all valid topology combinations in a single optimized computation, reducing the
 * number of function calls and improving GPU kernel performance.
 * 
 * @param a1,a2,a3 Taxa counts for tripartition side A in different subtree contexts
 * @param b1,b2,b3 Taxa counts for tripartition side B in different subtree contexts
 * @param c1,c2,c3 Taxa counts for tripartition side C in different subtree contexts
 * @return Combined weight for all quartet topologies
 */
inline long FF(long a1, long a2, long a3, long b1, long b2, long b3, long c1, long c2, long c3) {
	return a1*((a1 + b2 + c3 - 3)*b2*c3 + (a1 + b3 + c2 - 3)*b3*c2) + a2*((a2 + b1 + c3 - 3)*b1*c3 + (a2 + b3 + c1 - 3)*b3*c1) + a3*((a3 + b1 + c2 - 3)*b1*c2 + (a3 + b2 + c1 - 3)*b2*c1);
}

/**
 * Structure representing a tripartition in GPU memory.
 * 
 * Each tripartition consists of three disjoint clusters of taxa, represented as
 * bitsets stored in global GPU memory. This structure provides efficient access
 * to tripartition data during weight calculation.
 */
struct cl_Tripartition {
	__global const long * cluster1;  // Bitset for tripartition side A
	__global const long * cluster2;  // Bitset for tripartition side B
	__global const long * cluster3;  // Bitset for tripartition side C
};

/**
 * Efficient population count function using GPU-specific assembly instructions.
 * 
 * Computes the number of set bits in a 64-bit integer using optimized GPU
 * hardware instructions, essential for fast bitset intersection computations.
 * 
 * @param i 64-bit integer to count bits in
 * @return Number of set bits (population count)
 */
inline uint popcnt(const ulong i) {
        uint n;
        asm("popc.b64 %0, %1;" : "=r"(n) : "l" (i));
        return n;
}

/**
 * Computes intersection size between two bitsets using vectorized operations.
 * 
 * This function efficiently calculates how many taxa are common between two
 * clusters by performing bitwise AND operations and population counting across
 * the entire bitset representation.
 * 
 * @param input1 First bitset (cluster)
 * @param input2 Second bitset (cluster)  
 * @return Size of intersection (number of common taxa)
 */
inline int bitIntersectionSize(__global const long* input1, __global const long* input2) {
	int out = 0;
	for (int i = 0; i < SPECIES_WORD_LENGTH; i++) {
		out += popcnt(input1[i]&input2[i * WORK_GROUP_SIZE]);
	}
	return out;
}

/**
 * Main OpenCL kernel for parallel tripartition weight calculation.
 * 
 * This kernel implements the core ASTRAL weight calculation algorithm on GPU hardware,
 * processing multiple tripartitions simultaneously across GPU cores. Each work item
 * computes the weight for one tripartition by traversing all gene trees and accumulating
 * quartet scores.
 * 
 * **Algorithm Flow:**
 * 1. Initialize data structures for current tripartition
 * 2. For each gene tree in the input sequence:
 *    a. Track taxon distribution across tripartition sides
 *    b. Process leaf nodes, internal nodes, and polytomies appropriately
 *    c. Compute quartet contributions using F and FF functions
 *    d. Accumulate weight contributions
 * 3. Store final tripartition weight in output array
 * 
 * **Memory Layout:**
 * - Gene trees encoded as compressed integer sequences
 * - Tripartitions stored as interleaved bitsets for coalesced access
 * - Output weights written to contiguous array
 * 
 * **Performance Characteristics:**
 * - High arithmetic intensity suitable for GPU acceleration
 * - Minimal inter-thread communication requirements
 * - Efficient memory access patterns for GPU architectures
 * - Scalable across different GPU hardware configurations
 * 
 * @param geneTreesAsInts Compressed gene tree representations
 * @param geneTreesAsIntsLength Total length of gene tree sequence
 * @param allArray Taxon clusters for each gene tree
 * @param tripartitions1glob,tripartitions2glob,tripartitions3glob Tripartition bitsets
 * @param weightArray Output array for computed weights
 */
__kernel void calcWeight(
	__global const short* geneTreesAsInts,
	int geneTreesAsIntsLength,
	__global const long* allArray,
	__global const long* tripartitions1glob,
	__global const long* tripartitions2glob,
	__global const long* tripartitions3glob,
	__global long* weightArray
){
	long weight = 0;  // Accumulated tripartition weight
	struct cl_Tripartition trip;
	int idx = get_global_id(0);  // Unique work item identifier
	
	int allsides[3];  // Total taxa per tripartition side in current gene tree

	int newTree = 1;     // Flag indicating start of new gene tree
	int counter = 0;     // Position in gene tree sequence
	int treeCounter = 0; // Current gene tree index

	// Computational stack for tracking taxon counts during tree traversal
	long stack[STACK_SIZE * 3];

	long sx [3];      // Working arrays for polytomy computations
	long sxy [3];
	long tempWeight;  // Temporary weight accumulator

	int top = 0;      // Stack pointer
	short geneInt = 0; // Current gene tree element

	// Main loop: process all elements in the gene tree sequence
	while(counter < geneTreesAsIntsLength){
		geneInt = geneTreesAsInts[counter];
		counter++;
		
		if (newTree) {
			// Initialize for new gene tree: compute taxon distribution
			newTree = 0;

			allsides[0] = bitIntersectionSize(&allArray[treeCounter * SPECIES_WORD_LENGTH], tripartitions1glob + idx);
			allsides[1] = bitIntersectionSize(&allArray[treeCounter * SPECIES_WORD_LENGTH], tripartitions2glob + idx);
			allsides[2] = bitIntersectionSize(&allArray[treeCounter * SPECIES_WORD_LENGTH], tripartitions3glob + idx);

			treeCounter++;
		}
		if (geneInt >= 0) {
			// LEAF NODE: Determine tripartition membership for this taxon
			stack[top * 3] = ((tripartitions1glob[idx + (SPECIES_WORD_LENGTH - 1 - geneInt / LONG_BIT_LENGTH) * WORK_GROUP_SIZE])>>(geneInt % LONG_BIT_LENGTH)) & 1;
			stack[top * 3 + 1] = ((tripartitions2glob[idx + (SPECIES_WORD_LENGTH - 1 - geneInt / LONG_BIT_LENGTH) * WORK_GROUP_SIZE])>>(geneInt % LONG_BIT_LENGTH)) & 1;
			stack[top * 3 + 2] = ((tripartitions3glob[idx + (SPECIES_WORD_LENGTH - 1 - geneInt / LONG_BIT_LENGTH) * WORK_GROUP_SIZE])>>(geneInt % LONG_BIT_LENGTH)) & 1;
			top++;
		}
		else if (geneInt == INT_MIN) {
			// TREE DELIMITER: Start processing next gene tree
			top = 0;
			newTree = 1;
		}
		else if (geneInt == -2) {
			// BINARY INTERNAL NODE: Combine children and compute quartet scores
			top--;
			int topminus1 = top - 1;
			long topa[3];
			long topminus1a[3];
			
			topa[0] = stack[top * 3];
			topa[1] = stack[top * 3 + 1];
			topa[2] = stack[top * 3 + 2];

			topminus1a[0] = stack[topminus1 * 3];
			topminus1a[1] = stack[topminus1 * 3 + 1];
			topminus1a[2] = stack[topminus1 * 3 + 2];

			// Combine counts from left and right children
			long newSides0 = topa[0] + topminus1a[0];
			long newSides1 = topa[1] + topminus1a[1];
			long newSides2 = topa[2] + topminus1a[2];
			
			// Compute complementary counts (taxa outside current subtree)
			long side3s0 = allsides[0] - newSides0;
			long side3s1 = allsides[1] - newSides1;
			long side3s2 = allsides[2] - newSides2;

			// Compute quartet contributions using optimized FF function
			weight += FF(topa[0], topa[1], topa[2], topminus1a[0], topminus1a[1], topminus1a[2], side3s0, side3s1, side3s2);	

			// Update stack with combined counts
			stack[topminus1 * 3] = newSides0;
			stack[topminus1 * 3 + 1] = newSides1;
			stack[topminus1 * 3 + 2] = newSides2;

		}
		else { 
			// POLYTOMY: Handle multifurcating nodes with optimized quartet enumeration
			tempWeight = 0;	

			sxy[0] = 0;
			sxy[1] = 0;
			sxy[2] = 0;
			
			long newSides[3];

			// Compute taxa not in any child of the polytomy
			for(int side = 0; side < 3; side++) {
                        	stack[top * 3 + side] = allsides[side];
				for(int i = top - 1; i>= top + geneInt; i--) {
                        		stack[top * 3 + side] -= stack[i * 3 + side];
				}
			}
			
			// Precompute cross-products for efficient quartet calculation
			for(int i = top; i>= top + geneInt; i--) {
				newSides[0] = stack[i * 3];
				newSides[1] = stack[i * 3 + 1];
				newSides[2] = stack[i * 3 + 2];

				sxy[0] += newSides[1] * newSides[2];
				sxy[1] += newSides[0] * newSides[2];
				sxy[2] += newSides[0] * newSides[1];
			}
			
			// Compute quartet contributions for all polytomy children
			for(int i = top; i >= top + geneInt; i--) {
				newSides[0] = stack[i * 3];
				newSides[1] = stack[i * 3 + 1];
				newSides[2] = stack[i * 3 + 2];
				
				// Apply polytomy-specific quartet scoring formula
				tempWeight += ((allsides[1] - newSides[1]) * (allsides[2] - newSides[2]) - sxy[0] + newSides[1] * newSides[2]) * newSides[0] * (newSides[0] - 1) +
						((allsides[0] - newSides[0]) * (allsides[2] - newSides[2]) - sxy[1] + newSides[0] * newSides[2]) * newSides[1] * (newSides[1] - 1) +
						((allsides[0] - newSides[0]) * (allsides[1] - newSides[1]) - sxy[2] + newSides[0] * newSides[1]) * newSides[2] * (newSides[2] - 1);
			}

			// Update stack with combined polytomy counts
			for(int side = 0; side < 3; side++) {
				stack[(top + geneInt) * 3 + side] = allsides[side] - stack[top * 3 + side];
			}
			weight += tempWeight;
			top = top + geneInt + 1;
		}
	}

	// Store final computed weight for this tripartition
	weightArray[idx] = weight;
}
