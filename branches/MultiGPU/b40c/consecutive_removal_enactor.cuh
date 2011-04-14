/******************************************************************************
 * 
 * Copyright 2010-2011 Duane Merrill
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License. 
 * 
 * For more information, see our Google Code project site: 
 * http://code.google.com/p/back40computing/
 * 
 ******************************************************************************/

/******************************************************************************
 * Tuned ConsecutiveRemoval Enactor
 ******************************************************************************/

#pragma once

#include <b40c/util/arch_dispatch.cuh>
#include <b40c/util/cta_work_distribution.cuh>
#include <b40c/consecutive_removal/enactor.cuh>
#include <b40c/consecutive_removal/problem_config_tuned.cuh>
#include <b40c/consecutive_removal/problem_type.cuh>

namespace b40c {

/******************************************************************************
 * ConsecutiveRemovalEnactor Declaration
 ******************************************************************************/

/**
 * Tuned consecutive removal enactor class.
 */
class ConsecutiveRemovalEnactor : public consecutive_removal::Enactor
{
public:

	//---------------------------------------------------------------------
	// Helper Structures (need to be public for cudafe)
	//---------------------------------------------------------------------

	template <typename T, typename SizeT> 							struct Storage;
	template <typename ProblemType> 								struct Detail;
	template <consecutive_removal::ProbSizeGenre PROB_SIZE_GENRE> 	struct ConfigResolver;

protected:

	//---------------------------------------------------------------------
	// Members
	//---------------------------------------------------------------------

	// Typedefs for base classes
	typedef consecutive_removal::Enactor BaseEnactorType;

	// Befriend our base types: they need to call back into a
	// protected methods (which are templated, and therefore can't be virtual)
	friend BaseEnactorType;


	//-----------------------------------------------------------------------------
	// ConsecutiveRemoval Operation
	//-----------------------------------------------------------------------------

    /**
	 * Performs a consecutive removal pass
	 */
	template <typename TunedConfig>
	cudaError_t EnactPass(
		typename TunedConfig::T *d_dest,
		typename TunedConfig::SizeT *d_num_compacted,
		typename TunedConfig::T *d_src,
		util::CtaWorkDistribution<typename TunedConfig::SizeT> &work,
		int spine_elements);


public:

	/**
	 * Constructor.
	 */
	ConsecutiveRemovalEnactor() : BaseEnactorType::Enactor() {}


	/**
	 * Enacts a consecutive removal on the specified device data using the specified
	 * granularity configuration  (Enactor::Enact)
	 */
	using BaseEnactorType::Enact;


	/**
	 * Enacts a consecutive removal operation on the specified device data using the
	 * enumerated tuned granularity configuration
	 *
	 * @param d_dest
	 * 		Pointer to result location
	 * @param d_elements_compacted
	 * 		Pointer to result count
	 * @param d_src
	 * 		Pointer to array of elements to be compacted
	 * @param num_elements
	 * 		Number of elements to compact
	 * @param max_grid_size
	 * 		Optional upper-bound on the number of CTAs to launch.
	 *
	 * @return cudaSuccess on success, error enumeration otherwise
	 */
	template <
		consecutive_removal::ProbSizeGenre PROB_SIZE_GENRE,
		typename T,
		typename SizeT>
	cudaError_t Enact(
		T *d_dest,
		SizeT *d_num_compacted,
		T *d_src,
		SizeT num_elements,
		int max_grid_size = 0);


	/**
	 * Enacts a consecutive removal operation on the specified device data using
	 * a heuristic for selecting granularity configuration based upon
	 * problem size.
	 *
	 * @param d_dest
	 * 		Pointer to result location
	 * @param d_src
	 * 		Pointer to array of elements to be compacted
	 * @param d_elements_compacted
	 * 		Pointer to result count
	 * @param num_elements
	 * 		Number of elements to compact
	 * @param max_grid_size
	 * 		Optional upper-bound on the number of CTAs to launch.
	 *
	 * @return cudaSuccess on success, error enumeration otherwise
	 */
	template <
		typename T,
		typename SizeT>
	cudaError_t Enact(
		T *d_dest,
		SizeT *d_num_compacted,
		T *d_src,
		SizeT num_elements,
		int max_grid_size = 0);

};



/******************************************************************************
 * Helper structures
 ******************************************************************************/

/**
 * Type for encapsulating operational details regarding an invocation
 */
template <typename ProblemType>
struct ConsecutiveRemovalEnactor::Detail
{
	typedef ProblemType Problem;
	
	ConsecutiveRemovalEnactor *enactor;
	int max_grid_size;

	// Constructor
	Detail(ConsecutiveRemovalEnactor *enactor, int max_grid_size = 0) :
		enactor(enactor), max_grid_size(max_grid_size) {}
};


/**
 * Type for encapsulating storage details regarding an invocation
 */
template <typename T, typename SizeT>
struct ConsecutiveRemovalEnactor::Storage
{
	T *d_dest;
	SizeT *d_num_compacted;
	T *d_src;
	SizeT num_elements;

	// Constructor
	Storage(
		T *d_dest,
		SizeT *d_num_compacted,
		T *d_src,
		SizeT num_elements) :
			d_dest(d_dest),
			d_num_compacted(d_num_compacted),
			d_src(d_src),
			num_elements(num_elements) {}
};


/**
 * Helper structure for resolving and enacting tuning configurations
 *
 * Default specialization for problem type genres
 */
template <consecutive_removal::ProbSizeGenre PROB_SIZE_GENRE>
struct ConsecutiveRemovalEnactor::ConfigResolver
{
	/**
	 * ArchDispatch call-back with static CUDA_ARCH
	 */
	template <int CUDA_ARCH, typename StorageType, typename DetailType>
	static cudaError_t Enact(StorageType &storage, DetailType &detail)
	{
		typedef typename DetailType::Problem ProblemType;

		// Obtain tuned granularity type
		typedef consecutive_removal::TunedConfig<ProblemType, CUDA_ARCH, PROB_SIZE_GENRE> TunedConfig;

		// Invoke base class enact with type
		return detail.enactor->template EnactInternal<TunedConfig, ConsecutiveRemovalEnactor>(
			storage.d_dest,
			storage.d_num_compacted,
			storage.d_src,
			storage.num_elements,
			detail.max_grid_size);
	}
};


/**
 * Helper structure for resolving and enacting tuning configurations
 *
 * Specialization for UNKNOWN problem type to select other problem type genres
 * based upon problem size, etc.
 */
template <>
struct ConsecutiveRemovalEnactor::ConfigResolver <consecutive_removal::UNKNOWN>
{
	/**
	 * ArchDispatch call-back with static CUDA_ARCH
	 */
	template <int CUDA_ARCH, typename StorageType, typename DetailType>
	static cudaError_t Enact(StorageType &storage, DetailType &detail)
	{
		typedef typename DetailType::Problem ProblemType;

		// Obtain large tuned granularity type
		typedef consecutive_removal::TunedConfig<ProblemType, CUDA_ARCH, consecutive_removal::LARGE> LargeConfig;

		// Identity the maximum problem size for which we can saturate loads
		int saturating_load = LargeConfig::Upsweep::TILE_ELEMENTS *
			LargeConfig::Upsweep::CTA_OCCUPANCY *
			detail.enactor->SmCount();

		if (storage.num_elements < saturating_load) {

			// Invoke base class enact with small-problem config type
			typedef consecutive_removal::TunedConfig<ProblemType, CUDA_ARCH, consecutive_removal::SMALL> SmallConfig;
			return detail.enactor->template EnactInternal<SmallConfig, ConsecutiveRemovalEnactor>(
				storage.d_dest,
				storage.d_num_compacted,
				storage.d_src,
				storage.num_elements,
				detail.max_grid_size);
		}

		// Invoke base class enact with type
		return detail.enactor->template EnactInternal<LargeConfig, ConsecutiveRemovalEnactor>(
			storage.d_dest,
			storage.d_num_compacted,
			storage.d_src,
			storage.num_elements,
			detail.max_grid_size);
	}
};


/******************************************************************************
 * ConsecutiveRemovalEnactor Implementation
 ******************************************************************************/

/**
 * Performs a consecutive removal pass
 *
 * TODO: Section can be removed if CUDA Runtime is fixed to
 * properly support template specialization around kernel call sites.
 */
template <typename TunedConfig>
cudaError_t ConsecutiveRemovalEnactor::EnactPass(
	typename TunedConfig::T *d_dest,
	typename TunedConfig::SizeT *d_num_compacted,
	typename TunedConfig::T *d_src,
	util::CtaWorkDistribution<typename TunedConfig::SizeT> &work,
	int spine_elements)
{
	using namespace consecutive_removal;

	// Common problem type that can be used to reconstruct the same TunedConfig on the device
	typedef typename TunedConfig::ProblemType ProblemType;

	typedef typename TunedConfig::Upsweep Upsweep;
	typedef typename TunedConfig::Spine Spine;
	typedef typename TunedConfig::Downsweep Downsweep;
	typedef typename TunedConfig::Single Single;
	typedef typename TunedConfig::T T;
	typedef typename TunedConfig::FlagCount FlagCount;

	cudaError_t retval = cudaSuccess;
	do {
		if (work.grid_size == 1) {

			TunedSingleKernel<ProblemType, TunedConfig::PROB_SIZE_GENRE>
					<<<1, Single::THREADS, 0>>>(
				d_src, d_num_compacted, d_dest, NULL, work);

			if (DEBUG && (retval = util::B40CPerror(cudaThreadSynchronize(), "ConsecutiveRemovalEnactor SpineKernel failed ", __FILE__, __LINE__))) break;

		} else {

			int dynamic_smem[3] = 	{0, 0, 0};
			int grid_size[3] = 		{work.grid_size, 1, work.grid_size};

			// Tuning option for dynamic smem allocation
			if (TunedConfig::UNIFORM_SMEM_ALLOCATION) {

				// We need to compute dynamic smem allocations to ensure all three
				// kernels end up allocating the same amount of smem per CTA

				// Get kernel attributes
				cudaFuncAttributes upsweep_kernel_attrs, spine_kernel_attrs, downsweep_kernel_attrs;
				if (retval = util::B40CPerror(cudaFuncGetAttributes(&upsweep_kernel_attrs, TunedUpsweepKernel<ProblemType, TunedConfig::PROB_SIZE_GENRE>),
					"ConsecutiveRemovalEnactor cudaFuncGetAttributes upsweep_kernel_attrs failed", __FILE__, __LINE__)) break;
				if (retval = util::B40CPerror(cudaFuncGetAttributes(&spine_kernel_attrs, TunedSpineKernel<ProblemType, TunedConfig::PROB_SIZE_GENRE>),
					"ConsecutiveRemovalEnactor cudaFuncGetAttributes spine_kernel_attrs failed", __FILE__, __LINE__)) break;
				if (retval = util::B40CPerror(cudaFuncGetAttributes(&downsweep_kernel_attrs, TunedDownsweepKernel<ProblemType, TunedConfig::PROB_SIZE_GENRE>),
					"ConsecutiveRemovalEnactor cudaFuncGetAttributes downsweep_kernel_attrs failed", __FILE__, __LINE__)) break;

				int max_static_smem = B40C_MAX(
					upsweep_kernel_attrs.sharedSizeBytes,
					B40C_MAX(spine_kernel_attrs.sharedSizeBytes, downsweep_kernel_attrs.sharedSizeBytes));

				dynamic_smem[0] = max_static_smem - upsweep_kernel_attrs.sharedSizeBytes;
				dynamic_smem[1] = max_static_smem - spine_kernel_attrs.sharedSizeBytes;
				dynamic_smem[2] = max_static_smem - downsweep_kernel_attrs.sharedSizeBytes;
			}

			// Tuning option for spine-scan kernel grid size
			if (TunedConfig::UNIFORM_GRID_SIZE) {
				grid_size[1] = grid_size[0]; 				// We need to make sure that all kernels launch the same number of CTAs
			}

			// Upsweep scan into spine
			TunedUpsweepKernel<ProblemType, TunedConfig::PROB_SIZE_GENRE>
					<<<grid_size[0], Upsweep::THREADS, dynamic_smem[0]>>>(
				d_src, (FlagCount*) spine(), work);

			if (DEBUG && (retval = util::B40CPerror(cudaThreadSynchronize(), "ConsecutiveRemovalEnactor TunedUpsweepKernel failed ", __FILE__, __LINE__))) break;

			// Spine scan
			TunedSpineKernel<ProblemType, TunedConfig::PROB_SIZE_GENRE>
					<<<grid_size[1], Spine::THREADS, dynamic_smem[1]>>>(
				(FlagCount*) spine(), (FlagCount*) spine(), spine_elements);

			if (DEBUG && (retval = util::B40CPerror(cudaThreadSynchronize(), "ConsecutiveRemovalEnactor TunedSpineKernel failed ", __FILE__, __LINE__))) break;

			// Downsweep scan into spine
			TunedDownsweepKernel<ProblemType, TunedConfig::PROB_SIZE_GENRE>
					<<<grid_size[2], Downsweep::THREADS, dynamic_smem[2]>>>(
				d_src, d_num_compacted, d_dest, (FlagCount*) spine(), work);

			if (DEBUG && (retval = util::B40CPerror(cudaThreadSynchronize(), "ConsecutiveRemovalEnactor TunedDownsweepKernel failed ", __FILE__, __LINE__))) break;
		}
	} while (0);

	return retval;
}


/**
 * Enacts a consecutive removal operation on the specified device data using the
 * enumerated tuned granularity configuration
 */
template <
	consecutive_removal::ProbSizeGenre PROB_SIZE_GENRE,
	typename T,
	typename SizeT>
cudaError_t ConsecutiveRemovalEnactor::Enact(
	T *d_dest,
	SizeT *d_num_compacted,
	T *d_src,
	SizeT num_elements,
	int max_grid_size)
{
	typedef consecutive_removal::ProblemType<T, SizeT> Problem;
	typedef Detail<Problem> Detail;
	typedef Storage<T, SizeT> Storage;
	typedef ConfigResolver<PROB_SIZE_GENRE> Resolver;

	Detail detail(this, max_grid_size);
	Storage storage(d_dest, d_num_compacted, d_src, num_elements);

	return util::ArchDispatch<__B40C_CUDA_ARCH__, Resolver>::Enact(storage, detail, PtxVersion());
}


/**
 * Enacts a consecutive removal operation on the specified device data using the
 * LARGE granularity configuration
 */
template <
	typename T,
	typename SizeT>
cudaError_t ConsecutiveRemovalEnactor::Enact(
	T *d_dest,
	SizeT *d_num_compacted,
	T *d_src,
	SizeT num_elements,
	int max_grid_size)
{
	return Enact<consecutive_removal::UNKNOWN>(
		d_dest, d_num_compacted, d_src, num_elements, max_grid_size);
}



} // namespace b40c

