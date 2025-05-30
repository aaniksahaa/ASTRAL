package phylonet.coalescent;


import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Map.Entry;
import java.util.Stack;
import java.util.concurrent.LinkedBlockingQueue;

import phylonet.tree.model.TNode;
import phylonet.tree.model.Tree;
import phylonet.tree.model.sti.STITreeCluster;
import phylonet.util.BitSet;

/**
 * Core component for computing tripartition weights in the ASTRAL-MP algorithm.
 * 
 * This class implements the fundamental weight calculation described in Equations 1-2 of the
 * research paper, which forms the foundation of ASTRAL's quartet-based scoring method.
 * 
 * **Theoretical Foundation:**
 * For a tripartition T = (A, B, C) representing three disjoint subsets of taxa, the weight
 * calculation determines how strongly the gene trees support each of the three possible
 * quartet topologies for any four taxa a∈A, b∈B, c∈C, d∈D (where D represents the remaining taxa).
 * 
 * **Weight Computation (Equations 1-2):**
 * 
 * For each gene tree g and tripartition T, the algorithm computes:
 * 1. **Individual Gene Tree Contribution**: For each quartet (a,b,c,d), determines which of the
 *    three possible topologies ((a,b)|(c,d)), ((a,c)|(b,d)), or ((a,d)|(b,c)) is displayed in gene tree g
 * 
 * 2. **Aggregated Weight**: Sums contributions across all gene trees to get the frequency of
 *    each quartet topology: w(q|G) = Σ over gene trees g: I(q, g)
 * 
 * 3. **Normalized Scoring**: The tripartition weight represents how much the quartet topology
 *    displayed by the species tree is supported relative to alternative topologies
 * 
 * **Algorithmic Implementation:**
 * The class provides multiple algorithms for weight calculation:
 * 
 * - **CondensedTraversalWeightCalculator**: Memory-efficient approach using compressed tree
 *   representations (polytrees) as described in ASTRAL-III optimizations
 * 
 * - **TraversalWeightCalculator**: Traditional ASTRAL-II approach that traverses gene trees
 *   directly to count quartet topology frequencies
 * 
 * **Parallelization Support:**
 * The weight calculation is designed to work with ASTRAL-MP's parallelization framework
 * (Section 2.4.1), allowing tripartition weights to be computed concurrently across
 * multiple threads or compute units.
 * 
 * **Performance Optimizations:**
 * - Polynomial-time algorithms that avoid explicit quartet enumeration
 * - Efficient tree traversal methods that compute weights in O(n²) time per gene tree
 * - Support for vectorized computations (AVX2) and GPU acceleration (OpenCL)
 * 
 * The weight calculator is essential for the dynamic programming algorithm, as it provides
 * the quartet scores needed to evaluate each potential species tree partition during the
 * bottom-up tree construction process.
 * 
 * @author smirarab
 * @see Section 2.1 of the research paper for weight calculation theory
 * @see Section 2.4.1 for parallelization strategies
 * @see Equations 1-2 for mathematical foundation
 */
class WQWeightCalculator extends AbstractWeightCalculatorConsumer<Tripartition> {
	//public static boolean HAS_NOT = true;
	//public static boolean WRITE_OR_DEBUG = false;
	AbstractInference<Tripartition> inference;
	private WQDataCollection dataCollection;
	WeightCalculatorAlgorithm algorithm;
	private TraversalWeightCalculator tmpalgorithm;

	public WQWeightCalculator(AbstractInference<Tripartition> inference, LinkedBlockingQueue<Long> queue2) {
		super(false, queue2);
		this.dataCollection = (WQDataCollection) inference.dataCollection;
		this.inference = (WQInferenceConsumer) inference;

		//this.algorithm = new TraversalWeightCalculator();
		this.algorithm = new CondensedTraversalWeightCalculator();
		tmpalgorithm = new TraversalWeightCalculator();
		Logging.log("Using polytree-based weight calculation.");
		//tmpalgorithm.setupGeneTrees((WQInference) inference);


	}

	abstract class WeightCalculatorAlgorithm {
		/**
		 * Core mathematical function implementing the quartet scoring formula from the research paper.
		 * 
		 * This function computes the contribution of a specific quartet configuration to the
		 * overall tripartition weight. For three groups of taxa (representing sides of a tripartition),
		 * it calculates how many valid quartets can be formed with the given distribution.
		 * 
		 * **Mathematical Foundation:**
		 * For a quartet formed by taking one taxon from each of three tripartition parts
		 * (a taxa from side A, b taxa from side B, c taxa from side C), the function
		 * computes the weighted contribution based on the combinatorial possibilities.
		 * 
		 * **Formula Implementation:**
		 * F(a, b, c) = (a + b + c - 3) × a × b × c
		 * 
		 * This formula accounts for:
		 * - The number of ways to choose one taxon from each of the three sides
		 * - The weighting factor that reflects the relative support for the quartet topology
		 * - Adjustment for the constraint that we need exactly four taxa total
		 * 
		 * **Usage in Weight Calculation:**
		 * This function is called repeatedly during gene tree traversal to accumulate
		 * quartet scores. Each call corresponds to evaluating a specific quartet configuration
		 * found in a gene tree and determining its contribution to the tripartition weight.
		 * 
		 * @param a Number of taxa from tripartition side A in the current quartet context
		 * @param b Number of taxa from tripartition side B in the current quartet context  
		 * @param c Number of taxa from tripartition side C in the current quartet context
		 * @return The weighted quartet contribution for this configuration
		 * @throws RuntimeException if any side has negative taxa count (invalid input)
		 */
		long F(long a, long b, long c) {
			if (a < 0 || b < 0 || c < 0) {
				throw new RuntimeException(
						"negative side not expected: " + a + " " + b + " " + c);
			}
			long ret = (a + b + c - 3);
			ret *= a * b * c;
			return ret;
		}

		abstract Long calculateWeight(Tripartition t);
		abstract void setupGeneTrees(WQInferenceConsumer inference);
		
		Long[] calculateWeight(Tripartition [] trips) {
			int r = 0;
			Long [] rets = new Long[trips.length];
			for (Tripartition trip: trips) {
				rets[r++] = calculateWeight(trip);
			}
			return rets;
		}
	}

	/**
	 * Memory-efficient weight calculation algorithm using compressed polytree representation.
	 * 
	 * This implementation represents an advanced optimization introduced in ASTRAL-III that
	 * significantly reduces memory usage while maintaining the same computational accuracy
	 * as traditional weight calculation methods.
	 * 
	 * **Polytree Representation:**
	 * Instead of storing complete gene tree structures, this algorithm converts gene trees
	 * into a compressed integer representation called a "polytree":
	 * 
	 * - **Positive integers**: Represent leaf nodes, with values corresponding to taxon indices
	 * - **Negative integers**: Represent internal nodes, with absolute values indicating the number of children
	 * - **Integer.MIN_VALUE**: Acts as a delimiter separating different gene trees in the sequence
	 * 
	 * **Memory Efficiency Benefits:**
	 * 1. **Reduced Memory Footprint**: Eliminates redundant tree structure storage
	 * 2. **Cache Performance**: Improves CPU cache utilization due to compact representation
	 * 3. **Vectorization Ready**: The integer format enables efficient vectorized operations (AVX2)
	 * 4. **GPU Compatible**: Can be easily transferred to GPU memory for OpenCL acceleration
	 * 
	 * **Algorithm Performance:**
	 * This approach maintains O(n²) time complexity per gene tree while dramatically reducing
	 * memory requirements, making it suitable for large-scale phylogenomic datasets with
	 * thousands of gene trees.
	 * 
	 * **Integration with ASTRAL-MP:**
	 * The compressed representation is particularly beneficial for the parallelization strategies
	 * described in Section 2.4.1, as the compact data structures can be efficiently distributed
	 * across multiple compute units (CPU threads or GPU cores).
	 * 
	 * **Compatibility:**
	 * Despite the different internal representation, this algorithm produces identical weight
	 * calculations to the traditional TraversalWeightCalculator, ensuring mathematical
	 * equivalence while offering superior performance characteristics.
	 * 
	 * @author chaoszhang
	 * @see Section 2.4.1 for parallelization benefits
	 * @see ASTRAL-III paper for detailed polytree algorithm description
	 */
	class CondensedTraversalWeightCalculator extends WeightCalculatorAlgorithm {
		Polytree polytree;

		@Override
		Long[] calculateWeight(Tripartition[] trip) {
			return polytree.WQWeightByTraversal(trip);
		}
		
		@Override
		Long calculateWeight(Tripartition t) {
			return polytree.WQWeightByTraversal(t);
		}

		/**
		 * Converts gene trees into compressed polytree representation for efficient weight calculation.
		 * 
		 * This method transforms the input gene trees into a memory-efficient integer-based format
		 * that enables fast tripartition weight computation while supporting vectorization and
		 * parallel processing optimizations.
		 * 
		 * **Encoding Scheme:**
		 * - Positive numbers: Leaf nodes (taxon indices)
		 * - Negative numbers: Internal nodes (number of children as absolute value)
		 * - Integer.MIN_VALUE: Tree delimiters for separating different gene trees
		 * 
		 * **Performance Impact:**
		 * The polytree representation enables:
		 * - Reduced memory allocation and garbage collection overhead
		 * - Better CPU cache locality during weight calculations
		 * - Vectorized operations using AVX2 instructions (if available)
		 * - Efficient data transfer for GPU acceleration via OpenCL
		 * 
		 * @param inference The inference context containing gene trees and data collection
		 */
		@Override
		void setupGeneTrees(WQInferenceConsumer inference) {
			//Logging.log("Using polytree-based weight calculation.");
			polytree = new Polytree(inference.trees, dataCollection);
		}


	}


	/**
	 * Traditional weight calculation algorithm from ASTRAL-II using direct gene tree traversal.
	 * 
	 * This implementation represents the original ASTRAL-II approach for computing tripartition
	 * weights by directly traversing gene tree structures and accumulating quartet scores.
	 * While less memory-efficient than the CondensedTraversalWeightCalculator, it provides
	 * a clear reference implementation of the weight calculation algorithm.
	 * 
	 * **Algorithm Overview:**
	 * The algorithm traverses each gene tree bottom-up using a stack-based approach:
	 * 
	 * 1. **Leaf Processing**: For each leaf, determines which tripartition side it belongs to
	 * 2. **Internal Node Processing**: Combines counts from child nodes and computes quartet contributions
	 * 3. **Polytomy Handling**: Special logic for nodes with more than two children
	 * 4. **Weight Accumulation**: Sums quartet scores across all gene trees
	 * 
	 * **Mathematical Foundation:**
	 * For each internal node in a gene tree, the algorithm:
	 * - Computes the distribution of taxa across tripartition sides in left and right subtrees
	 * - Calculates the quartet contribution using the F function for each valid quartet
	 * - Accumulates weights that represent support for the species tree topology
	 * 
	 * **Stack-Based Traversal:**
	 * Uses a computational stack to track taxon counts for each tripartition side:
	 * - stack[i][0]: Count of taxa from tripartition side A
	 * - stack[i][1]: Count of taxa from tripartition side B  
	 * - stack[i][2]: Count of taxa from tripartition side C
	 * 
	 * **Quartet Score Computation:**
	 * At each internal node, computes all possible quartet topologies by considering:
	 * - Taxa from left subtree vs. right subtree
	 * - Taxa from current subtree vs. remaining taxa in the gene tree
	 * - All combinations that form valid quartet configurations
	 * 
	 * **Polytomy Support:**
	 * Handles multifurcating gene trees by considering all pairwise combinations
	 * of children, ensuring that quartet scores are correctly computed even when
	 * gene trees are not fully resolved.
	 * 
	 * **Performance Characteristics:**
	 * - Time Complexity: O(n²) per gene tree, where n is the number of taxa
	 * - Space Complexity: O(n) for the computational stack and working arrays
	 * - Memory Usage: Higher than polytree approach due to explicit tree storage
	 * 
	 * This algorithm serves as the computational foundation for ASTRAL's quartet-based
	 * scoring method and demonstrates the direct implementation of Equations 1-2 from
	 * the research paper.
	 * 
	 * @author smirarab
	 * @see Section 2.1 for theoretical foundation of quartet scoring
	 * @see Equations 1-2 for mathematical basis of weight calculation
	 */
	class TraversalWeightCalculator extends WeightCalculatorAlgorithm {

		int [] geneTreesAsInts;

		public int maxHeight;

		
		/**
		 * Computes the tripartition weight by traversing gene trees and accumulating quartet scores.
		 * 
		 * This method implements the core weight calculation algorithm from Equations 1-2 of the
		 * research paper. It traverses each gene tree using a stack-based bottom-up approach,
		 * computing quartet contributions at each internal node.
		 * 
		 * **Algorithm Steps:**
		 * 1. Initialize data structures for tracking taxon counts per tripartition side
		 * 2. For each gene tree, traverse nodes in postorder (leaves to root)
		 * 3. At each internal node, compute quartet scores using the F function
		 * 4. Accumulate weights across all gene trees to get final tripartition weight
		 * 
		 * **Stack Management:**
		 * The stack tracks taxon counts for each tripartition side at each tree level.
		 * When combining child nodes, it computes all valid quartet configurations.
		 * 
		 * @param trip The tripartition for which to compute the weight
		 * @return The accumulated weight representing gene tree support for this tripartition
		 */
		Long calculateWeight(Tripartition trip) {

			// Data structures for tracking taxon counts during tree traversal
			int[][] stack = new int[GlobalMaps.taxonIdentifier.taxonCount() + 2][3];

			// Arrays for handling polytomies (nodes with >2 children)
			int[][] overlap = new int[GlobalMaps.taxonIdentifier.taxonCount() +1][3];
			int[][] overlapind = new int[GlobalMaps.taxonIdentifier.taxonCount() +1][3];

			
			long weight = 0; // Accumulated tripartition weight across all gene trees
			int[] allsides = null; // Total taxa count per tripartition side in current gene tree
			Iterator<STITreeCluster> tit = dataCollection.treeAllClusters.iterator();
			boolean newTree = true;
			int top = 0; // Stack pointer - first empty position on stack
			
			for (Integer gtb : this.geneTreesAsInts) {
				if (newTree) {
					// Initialize for new gene tree: compute taxon distribution across tripartition sides
					STITreeCluster all = tit.next();
					allsides = new int[] {
							trip.cluster1.getBitSet().intersectionSize(all.getBitSet()),
							trip.cluster2.getBitSet().intersectionSize(all.getBitSet()),
							trip.cluster3.getBitSet().intersectionSize(all.getBitSet())};
					newTree = false;
				}
				
				if (gtb >= 0) { 
					// LEAF NODE PROCESSING
					// Determine which tripartition side this taxon belongs to
					if (trip.cluster1.getBitSet().get(gtb)) {
						stack[top][0] = 1;
						stack[top][1] = 0;
						stack[top][2] = 0;
					} else if (trip.cluster2.getBitSet().get(gtb)) {
						stack[top][0] = 0;
						stack[top][1] = 1;
						stack[top][2] = 0;
					} else if (trip.cluster3.getBitSet().get(gtb)) {
						stack[top][0] = 0;
						stack[top][1] = 0;
						stack[top][2] = 1;
					} else { 
						// Missing data case: taxon not in any tripartition side
						stack[top][0] = 0;
						stack[top][1] = 0;
						stack[top][2] = 0;
					}
					top++;
				} else if (gtb == Integer.MIN_VALUE) { 
					// TREE DELIMITER: Start processing next gene tree
					top = 0;
					newTree = true;
				} else if (gtb == -2) { 
					// BINARY INTERNAL NODE PROCESSING
					// Combine counts from left and right children
					top--;
					int newSides0 = stack[top][0] + stack[top - 1][0];
					int newSides1 = stack[top][1] + stack[top - 1][1];
					int newSides2 = stack[top][2] + stack[top - 1][2];

					// Compute complementary counts (taxa not in current subtree)
					int side3s0 = allsides[0] - newSides0;
					int side3s1 = allsides[1] - newSides1;
					int side3s2 = allsides[2] - newSides2;

					// QUARTET SCORE COMPUTATION: Apply F function to all valid quartet combinations
					// Each term represents a different quartet topology configuration
					weight += F(stack[top][0], stack[top - 1][1], side3s2)
							+ F(stack[top][0], stack[top - 1][2], side3s1)
							+ F(stack[top][1], stack[top - 1][0], side3s2)
							+ F(stack[top][1], stack[top - 1][2], side3s0)
							+ F(stack[top][2], stack[top - 1][0], side3s1)
							+ F(stack[top][2], stack[top - 1][1], side3s0);

					// Update stack with combined counts for parent node
					stack[top - 1][0] = newSides0;
					stack[top - 1][1] = newSides1;
					stack[top - 1][2] = newSides2;
				} else { 
					// POLYTOMY PROCESSING: Handle nodes with more than 2 children
					// This section implements quartet scoring for multifurcating nodes


					int [] nzc = {0,0,0}; // Count of non-zero children per tripartition side
					int [] newSides = {0,0,0}; // Total taxa per side in all children
					
					// Collect taxon counts from all children of the polytomy
					for (int side = 0; side < 3; side++) {
						for (int i = top - 1; i >= top + gtb; i--) {
							if (stack[i][side] > 0) {
								newSides[side] += stack[i][side];
								overlap[nzc[side]][side] = stack[i][side]; 
								overlapind[nzc[side]++][side] = i;
							}
						}
						// Compute taxa not in any child (for quartet completion)
						stack[top][side] = allsides[side] - newSides[side];

						if (stack[top][side] > 0) {
							overlap[nzc[side]][side] = stack[top][side]; 
							overlapind[nzc[side]++][side] = top;
						}
						stack[top + gtb][side] = newSides[side];
					}

					// POLYTOMY QUARTET CALCULATION: Consider all pairwise combinations of children
					for (int i = nzc[0] - 1; i >= 0; i--) {
						for (int j = nzc[1] - 1; j >= 0; j--) {
							if (overlapind[i][0] != overlapind[j][1])
								for (int k = nzc[2] - 1; k >= 0; k--) {
									if ((overlapind[i][0] != overlapind[k][2]) 
											&& (overlapind[j][1] != overlapind[k][2]))
										weight += F(overlap[i][0], overlap[j][1], overlap[k][2]);
								}
						}

						top = top + gtb + 1;

					} // End of polytomy section

				}
			}

			return (weight);
		}

		/***
		 * Each gene tree is represented as a list of integers, using positive numbers
		 * for leaves, where the number gives the index of the leaf. 
		 * We use negative numbers for internal nodes, where the value gives the number of children. 
		 * Minus infinity is used for separating different genes. 
		 */
		@Override
		void setupGeneTrees(WQInferenceConsumer inference) {
			//Logging.log("Using tree-based weight calculation.");
			List<Integer> temp = new ArrayList<Integer>(); 

			Stack<Integer> stackHeight = new Stack<Integer>();
			maxHeight = 0;
			for (Tree tr :  inference.trees) {
				/**
				 * Traverse tree and 1) build geneTreesAsInts, 2) compute maxHeight
				 */

				for (TNode node : tr.postTraverse()) {
					if (node.isLeaf()) {                        
						temp.add(GlobalMaps.taxonIdentifier.taxonId(node.getName()));
						stackHeight.push(0);
					} else {
						temp.add(-node.getChildCount());
						int h = 0;
						for (int i = 0; i < node.getChildCount(); i++) {
							int childheight = stackHeight.pop();
							if(childheight > h)
								h = childheight;
						}
						h++;
						stackHeight.push(h);
					}
					if (node.isRoot()) {
						temp.add(Integer.MIN_VALUE);
						stackHeight.clear();
					}
					if(stackHeight.size()>maxHeight) {
						maxHeight = stackHeight.size();
					}
				}

				//Logging.log(tr);
			}
			geneTreesAsInts = new int[temp.size()];
			int i = 0;
			for (int v : temp) {
				geneTreesAsInts[i++] = v;
			}

		}

		public int[] geneTreesAsInts() {

			return this.geneTreesAsInts;
		}


	}

	/***
	 * This is for ASTRAL-I
	 * @author smirarab
	 *
	 */
	class SetWeightCalculator extends WeightCalculatorAlgorithm {

		Tripartition [] finalTripartitions = null;
		int [] finalCounts = null;

		Long calculateWeight(Tripartition trip) {
				long weight = 0l;
				for (int i = 0; i < this.finalCounts.length; i++) {
					weight += sharedQuartetCount(trip,
							this.finalTripartitions[i])
							* this.finalCounts[i];
				}
				return weight;
		}


		private void addTripartition(STITreeCluster l_cluster,
				STITreeCluster r_cluster, STITreeCluster remaining, TNode node,
				Map<Tripartition, Integer> geneTreeTripartitonCount) {

			Tripartition trip = new Tripartition(l_cluster, r_cluster, remaining);
			geneTreeTripartitonCount.put(trip,
					geneTreeTripartitonCount.containsKey(trip) ? 
							geneTreeTripartitonCount.get(trip) + 1 : 1);
		}

		void setupGeneTrees(WQInferenceConsumer inference) {

			List<STITreeCluster> treeCompteleClusters = 
					((WQDataCollection)inference.dataCollection).treeAllClusters;
			List<Tree> geneTrees = inference.trees;

			Logging.log("Calculating tripartitions from gene trees ");

			Map<Tripartition, Integer> geneTreeTripartitonCount = new 
					HashMap<Tripartition, Integer>(inference.trees.size() 
							*  GlobalMaps.taxonIdentifier.taxonCount());

			int t = 0;
			for (Tree tr : geneTrees) {
				//System.err.print(".");
				Stack<STITreeCluster> stack = new Stack<STITreeCluster>();
				STITreeCluster gtAll = treeCompteleClusters.get(t++);
				BitSet gtAllBS = gtAll.getBitSet();


				for (TNode node : tr.postTraverse()) {				
					if (node.isLeaf()) {				
						STITreeCluster cluster = GlobalMaps.taxonIdentifier.getClusterForNodeName(node.getName());
						stack.add(cluster);
					} else {

						ArrayList<STITreeCluster> childbslist = new ArrayList<STITreeCluster>();
						BitSet bs = new BitSet(GlobalMaps.taxonIdentifier.taxonCount());
						for (TNode child: node.getChildren()) {
							STITreeCluster pop = stack.pop();
							childbslist.add(pop);
							bs.or(pop.getBitSet());
						}

						STITreeCluster cluster = GlobalMaps.taxonIdentifier
								.newCluster();
						;
						cluster.setCluster((BitSet) bs.clone());
						stack.add(cluster);

						STITreeCluster remaining = cluster.complementaryCluster();
						remaining.getBitSet().and(gtAllBS);
						if (remaining.getClusterSize() != 0) {
							childbslist.add(remaining);
						}

						//Logging.log(childbslist.size());
						for (int i = 0; i < childbslist.size(); i++) {
							for (int j = i+1; j < childbslist.size(); j++) {
								for (int k = j+1; k < childbslist.size(); k++) {

									addTripartition( childbslist.get(i),  childbslist.get(j), 
											childbslist.get(k), node, geneTreeTripartitonCount);
								}
							}					       
						}

					}
				}

			}

			//Logging.log("Using tripartition-based weight calculation.");

			finalTripartitions = new Tripartition[geneTreeTripartitonCount.size()];
			finalCounts = new int[geneTreeTripartitonCount.size()];
			int i = 0;
			for (Entry<Tripartition, Integer> entry : geneTreeTripartitonCount.entrySet()){
				finalTripartitions[i] = entry.getKey();
				finalCounts[i] = entry.getValue();
				i++;
			}

			if (geneTreeTripartitonCount.size() > 0) {
				long s = 0;
				for (Integer c : geneTreeTripartitonCount.values()) {
					s += c;
				}
				Logging.log("Tripartitions in gene trees (count): "
						+ geneTreeTripartitonCount.size());
				Logging.log("Tripartitions in gene trees (sum): " + s);
			}
		}

		long sharedQuartetCount(Tripartition that, Tripartition other) {

			int I0 = that.cluster1.getBitSet().intersectionSize(
					other.cluster1.getBitSet()), I1 = that.cluster1.getBitSet()
					.intersectionSize(other.cluster2.getBitSet()), I2 = that.cluster1
					.getBitSet().intersectionSize(other.cluster3.getBitSet()), I3 = that.cluster2
					.getBitSet().intersectionSize(other.cluster1.getBitSet()), I4 = that.cluster2
					.getBitSet().intersectionSize(other.cluster2.getBitSet()), I5 = that.cluster2
					.getBitSet().intersectionSize(other.cluster3.getBitSet()), I6 = that.cluster3
					.getBitSet().intersectionSize(other.cluster1.getBitSet()), I7 = that.cluster3
					.getBitSet().intersectionSize(other.cluster2.getBitSet()), I8 = that.cluster3
					.getBitSet().intersectionSize(other.cluster3.getBitSet());

			return F(I0, I4, I8) + F(I0, I5, I7) + F(I1, I3, I8)
					+ F(I1, I5, I6) + F(I2, I3, I7) + F(I2, I4, I6);
		}
	}

	public void useSetWeightsAlgorithm() {
		algorithm = new SetWeightCalculator();
	}

	/**
	 * obsolete (for now)
	 */
	public void preCalculateWeights(List<Tree> trees, List<Tree> extraTrees) {
	}

	/**
	 * Each algorithm will have its own data structure for gene trees
	 * @param wqInference
	 */
	public void setupGeneTrees(WQInferenceConsumer wqInference) {
		tmpalgorithm.setupGeneTrees(wqInference);
		this.algorithm.setupGeneTrees(wqInference);
	}

	//TODO: this is algorithm-specific should not be exposed. Fix. 
	public int[] geneTreesAsInts() {
		return (tmpalgorithm).geneTreesAsInts;
	}
	//TODO: this is algorithm-specific should not be exposed. Fix. 
	public int maxHeight() {
		return ((TraversalWeightCalculator)tmpalgorithm).maxHeight;
	}
	
	@Override
	protected Long[] calculateWeight(Tripartition[] t) {
		return this.algorithm.calculateWeight(t);
	}

	@Override
	Tripartition[] convertToSingletonArray(Tripartition t) {
		return new Tripartition[]{t};
	}



}
