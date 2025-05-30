package phylonet.coalescent;

import java.text.DecimalFormat;
import java.text.DecimalFormatSymbols;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedList;
import java.util.List;
import java.util.Set;
import java.util.Stack;
import java.util.concurrent.LinkedBlockingQueue;

import phylonet.coalescent.IClusterCollection.VertexPair;
import phylonet.tree.model.MutableTree;
import phylonet.tree.model.TNode;
import phylonet.tree.model.Tree;
import phylonet.tree.model.sti.STINode;
import phylonet.tree.model.sti.STITree;
import phylonet.tree.model.sti.STITreeCluster;
import phylonet.tree.model.sti.STITreeCluster.Vertex;
import phylonet.tree.util.Collapse;

/**
 * Abstract base class for ASTRAL-MP phylogenetic inference implementations.
 * 
 * This class provides the core dynamic programming framework that implements the fundamental
 * ASTRAL algorithm described in the research paper. The dynamic programming approach follows
 * Equation 3 from the paper, which finds the species tree that maximizes the weighted quartet score:
 * 
 * Score(S) = Σ over all quartets q: w(q|G) * I(q, S)
 * 
 * where w(q|G) is the weight of quartet q given gene trees G (computed using Equations 1-2),
 * and I(q, S) is an indicator function for whether quartet q is displayed in species tree S.
 * 
 * The algorithm constructs a search space X from bipartitions present in gene trees and uses
 * dynamic programming to efficiently explore this exponentially large space. This approach makes
 * the NP-hard problem of finding the optimal species tree tractable for datasets with hundreds
 * of taxa.
 * 
 * Key components:
 * - Dynamic programming over clusters (bottom-up tree construction)
 * - Tripartition weight calculation for quartet scoring
 * - Search space restriction using gene tree bipartitions
 * - Support for both rooted and unrooted tree inference
 * 
 * This abstract class is extended by specific implementations like WQInferenceConsumer
 * that add parallelization and optimization strategies described in Section 2.4 of the paper.
 * 
 * Type parameter T corresponds to tripartitions in ASTRAL - the fundamental unit for
 * quartet-based scoring as described in Section 2.1 of the research paper.
 * 
 * @author smirarab
 * @param <T> The tripartition type used for quartet scoring
 */

public abstract class AbstractInference<T> implements Cloneable{
	
	protected List<Tree> trees;
	protected List<Tree> extraTrees = null;
	protected List<Tree> toRemoveExtraTrees = null;
	protected boolean removeExtraTree;

	Collapse.CollapseDescriptor cd = null;
	
	AbstractDataCollection<T> dataCollection;
	AbstractWeightCalculator<T> weightCalculator;
	
	Boolean done = false;
	protected Options options;
	DecimalFormat df;

	
	private LinkedBlockingQueue<Long> queueWeightResults;
	private LinkedBlockingQueue<Iterable<VertexPair>> queueClusterResolutions;

	double estimationFactor = 0;

	public AbstractInference(Options options, List<Tree> trees,
			List<Tree> extraTrees, List<Tree> toRemoveExtraTrees) {
		super();
		this.options = options;
		this.trees = trees;
		this.extraTrees = extraTrees;
		this.removeExtraTree = options.isRemoveExtraTree();
		this.toRemoveExtraTrees = toRemoveExtraTrees;
		
		this.initDF();

	}


	private void initDF() {
		df = new DecimalFormat();
		df.setMaximumFractionDigits(2);
		DecimalFormatSymbols dfs = DecimalFormatSymbols.getInstance();
		dfs.setDecimalSeparator('.');
		df.setDecimalFormatSymbols(dfs);
	}
	
	public boolean isRooted() {
		return options.isRooted();
	}

	
	protected Collapse.CollapseDescriptor doCollapse(List<Tree> trees) {
		Collapse.CollapseDescriptor cd = Collapse.collapse(trees);
		return cd;
	}
	
	protected void restoreCollapse(List<Solution> sols, Collapse.CollapseDescriptor cd) {
		for (Solution sol : sols) {
			Tree tr = sol._st;
			Collapse.expand(cd, (MutableTree) tr);
			for (TNode node : tr.postTraverse())
				if (((STINode) node).getData() == null)
					((STINode) node).setData(Integer.valueOf(0));
		}
	}


	//TODO: Check whether this is in the right class
	public void mapNames() {
		HashMap<String, Integer> taxonOccupancy = new HashMap<String, Integer>();
		if ((trees == null) || (trees.size() == 0)) {
			throw new IllegalArgumentException("empty or null list of trees");
		}
        for (Tree tr : trees) {
            String[] leaves = tr.getLeaves();
            for (int i = 0; i < leaves.length; i++) {
                GlobalMaps.taxonIdentifier.taxonId(leaves[i]);
                taxonOccupancy.put(leaves[i], Utils.increment(taxonOccupancy.get(leaves[i])));
            }
        }
        
        GlobalMaps.taxonNameMap.checkMapping(trees);

		Logging.log("Number of taxa: " + GlobalMaps.taxonIdentifier.taxonCount()+
		        " (" + GlobalMaps.taxonNameMap.getSpeciesIdMapper().getSpeciesCount() +" species)");
		Logging.log("Taxa: " + GlobalMaps.taxonNameMap.getSpeciesIdMapper().getSpeciesNames());
		Logging.log("Taxon occupancy: " + taxonOccupancy.toString());
	}

	/**
	 * Scores a given species tree using the ASTRAL quartet-based scoring method.
	 * 
	 * This method implements the core scoring function from Equation 3 of the research paper:
	 * Score(S) = Σ over all quartets q: w(q|G) * I(q, S)
	 * 
	 * For each quartet of taxa, it:
	 * 1. Computes the quartet weight w(q|G) based on gene tree frequencies (Equations 1-2)
	 * 2. Determines if the quartet topology is displayed in the species tree S (indicator I(q, S))
	 * 3. Accumulates the weighted score across all possible quartets
	 * 
	 * The scoring process is essential for:
	 * - Evaluating candidate species trees during dynamic programming
	 * - Computing the final optimality score of the inferred tree
	 * - Comparing alternative phylogenetic hypotheses
	 * 
	 * This abstract method is implemented by specific inference classes like WQInferenceConsumer
	 * which may use parallelization strategies described in Section 2.4.1 of the paper.
	 * 
	 * @param scorest The species tree to score
	 * @param initialize Whether to initialize data structures before scoring
	 * @return The quartet-based score of the species tree
	 */
	public abstract double scoreSpeciesTreeWithGTLabels(Tree scorest, boolean initialize) ;

	/**
	 * Core dynamic programming algorithm that implements the ASTRAL species tree inference method.
	 * 
	 * This method implements the fundamental dynamic programming approach described in the research paper
	 * that efficiently searches the exponentially large space of possible species trees. The algorithm
	 * follows these key steps from the paper:
	 * 
	 * 1. **Bottom-up Construction**: Starting from individual taxa, builds increasingly larger clusters
	 *    by considering all valid combinations from the search space X
	 * 
	 * 2. **Optimal Substructure**: For each cluster C, computes the optimal score by considering all
	 *    possible ways to partition C into two subclusters (C1, C2) and finding:
	 *    Score(C) = max over all valid partitions: Score(C1) + Score(C2) + quartet_score(C1, C2, rest)
	 * 
	 * 3. **Search Space Restriction**: Only considers bipartitions present in the search space X,
	 *    which is constructed from gene tree bipartitions plus heuristic additions. This restriction
	 *    makes the NP-hard problem tractable while maintaining statistical consistency.
	 * 
	 * 4. **Quartet-based Scoring**: Uses tripartition weights (computed via Equations 1-2) to
	 *    evaluate how well each potential species tree partition is supported by the gene trees.
	 * 
	 * The dynamic programming ensures that each subproblem is solved only once, achieving
	 * polynomial-time complexity in the size of the search space X rather than exponential
	 * complexity in the number of taxa.
	 * 
	 * This implementation supports the parallelization strategies described in Section 2.4.1,
	 * where computation tasks can be distributed across multiple threads or compute units.
	 * 
	 * @param clusters The collection of clusters forming the search space X
	 * @return List of optimal solutions (typically one, but may include ties)
	 */
	List<Solution> findTreesByDP(IClusterCollection clusters) {

		Vertex all = (Vertex) clusters.getTopVertex();

		Logging.log("Size of largest cluster: " +all.getCluster().getClusterSize());

		// Create and execute the main computation task for the root cluster
		// This triggers the recursive dynamic programming computation
		AbstractComputeMinCostTask<T> allTask = newComputeMinCostTask(this,all);
		allTask.compute();
		
		// Extract the optimal solution from the computed results
		List<Solution> solutions = processSolutions(all);
        
		return (List<Solution>) (List<Solution>) solutions;
	}


	List<Solution> processSolutions( Vertex all) {
		List<Solution> solutions = new ArrayList<Solution>();
		try {
			if ( all._max_score == Integer.MIN_VALUE) { //Assuming we are in the consumer thread. Producer overwrites
				throw new CannotResolveException(all.getCluster().toString());
			}
		} catch (Exception e) {
			Logging.log("Was not able to build a fully resolved tree. Not" +
					"enough clusters present in input gene trees ");
			e.printStackTrace();
			System.exit(1);
		}
		
		Logging.logTimeMessage("AbstractInference 193: " );
		
		Logging.log("Total Number of elements: " + countWeights());

		List<STITreeCluster> minClusters = new LinkedList<STITreeCluster>();
		//List<Double> coals = new LinkedList<Double>();
		Stack<Vertex> minVertices = new Stack<Vertex>();
		if (all._min_rc != null) {
			minVertices.push(all._min_rc);
		}
		if (all._min_lc != null) {
			minVertices.push(all._min_lc);
		}
//		if (all._subcl != null) {
//			for (Vertex v : all._subcl) {
//				minVertices.push(v);
//			}
//		}		
		SpeciesMapper spm = GlobalMaps.taxonNameMap.getSpeciesIdMapper();
		while (!minVertices.isEmpty()) {
			Vertex pe = (Vertex) minVertices.pop();
			STITreeCluster stCluster = spm.getSTClusterForGeneCluster(pe.getCluster());

			minClusters.add(stCluster);

			if ( !GlobalMaps.taxonNameMap.getSpeciesIdMapper().isSingleSP(pe.getCluster().getBitSet()) && (pe._min_lc == null || pe._min_rc == null))
				Logging.log("hmm; this shouldn't have happened: "+ pe);
			
			if (pe._min_rc != null) {
				minVertices.push(pe._min_rc);
			}
			if (pe._min_lc != null) {
				minVertices.push(pe._min_lc);
			}
//			if (pe._min_lc != null && pe._min_rc != null) {
//				coals.add(pe._c);
//			} else {
//				coals.add(0D);
//			}
//			if (pe._subcl != null) {
//				for (Vertex v : pe._subcl) {
//					minVertices.push(v);
//				}
//			}
		}
		Solution sol = new Solution();
		if ((minClusters == null) || (minClusters.isEmpty())) {
			Logging.log("WARN: empty minClusters set.");
			STITree<Double> tr = new STITree<Double>();
			for (String s : GlobalMaps.taxonIdentifier.getAllTaxonNames()) {
				((MutableTree) tr).getRoot().createChild(s);
			}
			sol._st = tr;
		} else {
			sol._st = Utils.buildTreeFromClusters(minClusters, spm.getSTTaxonIdentifier(), false);
		}

		Long cost = getTotalCost(all);
		sol._totalCoals = cost;
		solutions.add(sol);
		Logging.logTimeMessage("AbstractInference 283: ");
			
		Logging.log("Final optimization score: " + cost);
		return solutions;
	}

	public int countWeights() {
		return weightCalculator.getCalculatedWeightCount();
	}
	
	/**
	 * Sets up data structures before starting DP
	 */
	void setup() {
		this.setupSearchSpace();
		this.initializeWeightCalculator();
		this.setupMisc();
	}
	
	/**
	 * Constructs the search space X that defines the set of bipartitions considered during inference.
	 * 
	 * This method implements the critical search space construction described in the research paper.
	 * The search space X determines which bipartitions can be used to build species trees, directly
	 * affecting both the computational complexity and the accuracy of the inference.
	 * 
	 * **Search Space Construction Strategy:**
	 * 
	 * 1. **Gene Tree Bipartitions**: Adds all bipartitions that appear in the input gene trees.
	 *    This ensures that well-supported evolutionary relationships from individual genes
	 *    are available for the species tree construction.
	 * 
	 * 2. **ASTRAL-II Heuristics**: Applies additional heuristic rules to expand the search space
	 *    beyond just gene tree bipartitions. These heuristics help capture evolutionary
	 *    relationships that may not appear in individual gene trees but are important
	 *    for accurate species tree inference.
	 * 
	 * 3. **Optional Exact Solution**: When exact mode is enabled, adds all possible bipartitions,
	 *    guaranteeing the globally optimal solution but with exponential computational cost.
	 * 
	 * 4. **Extra Tree Integration**: Incorporates bipartitions from additional reference trees
	 *    if provided, allowing incorporation of prior phylogenetic knowledge.
	 * 
	 * 5. **Bipartition Removal**: Optionally removes bipartitions from specified trees,
	 *    useful for comparative analyses or constraint-based inference.
	 * 
	 * **Statistical Properties:**
	 * The restricted search space maintains the statistical consistency of ASTRAL while making
	 * the NP-hard problem computationally tractable. The key insight is that the optimal
	 * species tree typically uses bipartitions that appear in at least one gene tree.
	 * 
	 * **Computational Impact:**
	 * The size of X directly determines the runtime complexity of the dynamic programming algorithm.
	 * ASTRAL-MP's parallelization strategies (Section 2.4.1) become crucial when X is large.
	 * 
	 * @see Section 2.1 of the research paper for theoretical foundation
	 * @see Section 2.4.1 for parallelization of search space exploration
	 */
	private void setupSearchSpace() {
		long startTime = System.currentTimeMillis();

		// Initialize taxon mapping and core data structures
		mapNames();

		dataCollection = newCounter(newClusterCollection());
		weightCalculator = newWeightCalculator();

		/**
		 * Primary search space construction: combines gene tree bipartitions
		 * with ASTRAL-II heuristic additions to form the set X
		 */
		dataCollection.formSetX(this);
		
		

		
		// Optional exact solution mode: adds all possible bipartitions
		// Guarantees global optimum but with exponential computational cost
		if (options.isExactSolution()) {
			Logging.log("calculating all possible bipartitions ...");
		    dataCollection.addAllPossibleSubClusters(this.dataCollection.clusters.getTopVertex().getCluster());
		}

	      
		// Incorporate bipartitions from additional reference trees
		// Allows integration of prior phylogenetic knowledge
		if (extraTrees != null && extraTrees.size() > 0) {		
			Logging.log("calculating extra bipartitions from extra input trees ...");
			dataCollection.addExtraBipartitionsByInput(extraTrees,options.isExtrarooted());
			int s = this.dataCollection.clusters.getClusterCount();
			/*
			 * for (Integer c: clusters2.keySet()){ s += clusters2.get(c).size(); }
			 */
			Logging.log("Number of Clusters after additions from extra trees: "
					+ s);
		}
		
		
		// Remove bipartitions from specified trees if requested
		// Useful for comparative analyses or constraint-based inference
		if (toRemoveExtraTrees != null && toRemoveExtraTrees.size() > 0 && this.removeExtraTree) {		
			Logging.log("Removing extra bipartitions from extra input trees ...");
			dataCollection.removeExtraBipartitionsByInput(toRemoveExtraTrees,true);
			int s = this.dataCollection.clusters.getClusterCount();
			/*
			 * for (Integer c: clusters2.keySet()){ s += clusters2.get(c).size(); }
			 */
			Logging.log("Number of Clusters after deletion of extra tree bipartitions: "
					+ s);
		}
		
		
		// Debug output: display the constructed search space X
		if (this.options.isOutputSearchSpace()) {
			for (Set<Vertex> s: dataCollection.clusters.getSubClusters()) {
				for (Vertex v : s) {
					System.out.println(v.getCluster());
				}
			}
		}
		
		Logging.logTimeMessage("" );
		
		Logging.log("partitions formed in "
			+ (System.currentTimeMillis() - startTime) / 1000.0D + " secs");

		if (! this.options.isRunSearch() ) {
			System.exit(0);
		}
		
		// Obsolete 
		weightCalculator.preCalculateWeights(trees, extraTrees);

		Logging.log("Dynamic Programming starting after "
				+ (System.currentTimeMillis() - startTime) / 1000.0D + " secs");
		
	}
	
	public List<Solution> inferSpeciesTree() {
		
		List<Solution> solutions;		
		
		solutions = findTreesByDP(this.dataCollection.clusters);

		return (List<Solution>) solutions;
	}

	protected Object semiDeepCopy() {
		try {
			AbstractInference<T> clone =  (AbstractInference<T>) super.clone();
			clone.dataCollection = (AbstractDataCollection<T>) this.dataCollection.clone();
			clone.weightCalculator = (AbstractWeightCalculatorConsumer<T>) this.weightCalculator.clone();
			return clone;
		} catch (CloneNotSupportedException e) {
			e.printStackTrace();
			throw new RuntimeException("unexpected error");
		}
	}

	abstract void initializeWeightCalculator();

	abstract void setupMisc();

	abstract IClusterCollection newClusterCollection();
	
	abstract AbstractDataCollection<T> newCounter(IClusterCollection clusters);
	
	abstract AbstractWeightCalculator<T> newWeightCalculator();

	abstract AbstractComputeMinCostTask<T> newComputeMinCostTask(AbstractInference<T> dlInference,
			Vertex all);
	
	abstract Long getTotalCost(Vertex all);
	
	public double getDLbdWeigth() {
		return options.getDLbdWeigth();
	}

	
	public double getCS() {
		return options.getCS();
	}

	public double getCD() {
		return options.getCD();
	}

	
    public int getAddExtra() {
        return options.getAddExtra();
    }

	public int getBranchAnnotation() {
		return this.options.getBranchannotation();
	}

	public boolean shouldOutputCompleted() {
		
		return options.isOutputCompletedGenes();
	}

	public void setDLbdWeigth(double d) {
		options.setDLbdWeigth(d);
	}

	public LinkedBlockingQueue<Iterable<VertexPair>> getQueueClusterResolutions() {
		return queueClusterResolutions;
	}

	public void setQueueClusterResolutions(LinkedBlockingQueue<Iterable<VertexPair>> queueClusterResolutions) {
		this.queueClusterResolutions = queueClusterResolutions;
	}

	public LinkedBlockingQueue<Long> getQueueWeightResults() {
		return queueWeightResults;
	}

	public void setQueueWeightResults(LinkedBlockingQueue<Long> queueWeightResults) {
		this.queueWeightResults = queueWeightResults;
	}
}

