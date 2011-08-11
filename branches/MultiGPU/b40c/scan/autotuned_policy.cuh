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
 * Autotuned scan policy
 ******************************************************************************/

#pragma once

#include <b40c/util/cuda_properties.cuh>
#include <b40c/util/cta_work_distribution.cuh>
#include <b40c/util/io/modified_load.cuh>
#include <b40c/util/io/modified_store.cuh>

#include <b40c/scan/upsweep/kernel.cuh>
#include <b40c/scan/spine/kernel.cuh>
#include <b40c/scan/downsweep/kernel.cuh>
#include <b40c/scan/policy.cuh>

namespace b40c {
namespace scan {


/******************************************************************************
 * Tuning classifiers to policy-genre granularity types on
 ******************************************************************************/

/**
 * Enumeration of problem-size genres that we may have tuned for
 */
enum ProbSizeGenre
{
	UNKNOWN_SIZE = -1,			// Not actually specialized on: the enactor should use heuristics to select another size genre
	SMALL_SIZE,					// Tuned @ 128KB input
	LARGE_SIZE					// Tuned @ 128MB input
};


/**
 * Enumeration of architecture-families that we have tuned for below
 */
enum ArchFamily
{
	SM20 	= 200,
	SM13	= 130,
	SM10	= 100
};


/**
 * Classifies a given CUDA_ARCH into an architecture-family
 */
template <int CUDA_ARCH>
struct ArchGenre
{
	static const ArchFamily FAMILY =	//(CUDA_ARCH < SM13) ? 	SM10 :			// Have not yet tuned configs for SM10-11
										(CUDA_ARCH < SM20) ? 	SM13 :
																SM20;
};


/**
 * Autotuning policy genre, to be specialized
 */
template <
	typename ProblemType,
	int CUDA_ARCH,
	ProbSizeGenre PROB_SIZE_GENRE,
	typename T = typename ProblemType::T,
	int T_SIZE = sizeof(T)>
struct AutotunedGenre :
	AutotunedGenre<
		ProblemType,
		ArchGenre<CUDA_ARCH>::FAMILY,
		PROB_SIZE_GENRE,
		T,
		1 << util::Log2<sizeof(T)>::VALUE>	// Round up to the nearest arch subword
{};


//-----------------------------------------------------------------------------
// SM2.0 specializations(s)
//-----------------------------------------------------------------------------

// Large problems, 1B data
template <typename ProblemType, typename T>
struct AutotunedGenre<ProblemType, SM20, LARGE_SIZE, T, 1>
	: Policy<ProblemType, SM20, util::io::ld::NONE, util::io::st::NONE, false, true, false, 11,
	  8, 7, 2, 2,
	  5, 2, 0, 5,
	  8, 7, 2, 2, 5>
{
	static const ProbSizeGenre PROB_SIZE_GENRE = LARGE_SIZE;
};

// Large problems, 2B data
template <typename ProblemType, typename T>
struct AutotunedGenre<ProblemType, SM20, LARGE_SIZE, T, 2>
	: Policy<ProblemType, SM20, util::io::ld::NONE, util::io::st::NONE, false, true, false, 10,
	  8, 7, 1, 2,
	  5, 2, 0, 5,
	  8, 6, 2, 2, 5>
{
	static const ProbSizeGenre PROB_SIZE_GENRE = LARGE_SIZE;
};

// Large problems, 4B data
template <typename ProblemType, typename T>
struct AutotunedGenre<ProblemType, SM20, LARGE_SIZE, T, 4>
	: Policy<ProblemType, SM20, util::io::ld::NONE, util::io::st::NONE, false, false, false, 11,
	  8, 7, 2, 2,
	  5, 2, 0, 5,
	  8, 9, 1, 1, 5>
{
	static const ProbSizeGenre PROB_SIZE_GENRE = LARGE_SIZE;
};

// All other large problems (tuned at 8B)
template <typename ProblemType, typename T, int T_SIZE>
struct AutotunedGenre<ProblemType, SM20, LARGE_SIZE, T, T_SIZE>
	: Policy<ProblemType, SM20, util::io::ld::NONE, util::io::st::NONE, false, false, false, 8,
	  8, 7, 0, 1,
	  5, 2, 0, 5,
	  8, 5, 1, 2, 5>
{
	static const ProbSizeGenre PROB_SIZE_GENRE = LARGE_SIZE;
};



// Small problems, 1B data
template <typename ProblemType, typename T>
struct AutotunedGenre<ProblemType, SM20, SMALL_SIZE, T, 1>
	: Policy<ProblemType, SM20, util::io::ld::NONE, util::io::st::NONE, false, false, false, 9,
	  8, 5, 2, 2,
	  5, 2, 0, 5,
	  8, 6, 2, 1, 5>
{
	static const ProbSizeGenre PROB_SIZE_GENRE = SMALL_SIZE;
};

// Small problems, 2B data
template <typename ProblemType, typename T>
struct AutotunedGenre<ProblemType, SM20, SMALL_SIZE, T, 2>
	: Policy<ProblemType, SM20, util::io::ld::NONE, util::io::st::NONE, false, false, false, 9,
	  8, 5, 2, 2,
	  5, 2, 0, 5,
	  8, 5, 2, 2, 5>
{
	static const ProbSizeGenre PROB_SIZE_GENRE = SMALL_SIZE;
};

// Small problems, 4B data
template <typename ProblemType, typename T>
struct AutotunedGenre<ProblemType, SM20, SMALL_SIZE, T, 4>
	: Policy<ProblemType, SM20, util::io::ld::NONE, util::io::st::NONE, false, false, false, 8,
	  8, 5, 2, 1,
	  5, 2, 0, 5,
	  8, 5, 2, 1, 5>
{
	static const ProbSizeGenre PROB_SIZE_GENRE = SMALL_SIZE;
};

// All other small problems (tuned at 8B)
template <typename ProblemType, typename T, int T_SIZE>
struct AutotunedGenre<ProblemType, SM20, SMALL_SIZE, T, T_SIZE>
	: Policy<ProblemType, SM20, util::io::ld::NONE, util::io::st::NONE, false, false, false, 7,
	  8, 5, 1, 1,
	  5, 2, 0, 5,
	  8, 5, 0, 2, 5>
{
	static const ProbSizeGenre PROB_SIZE_GENRE = SMALL_SIZE;
};

//-----------------------------------------------------------------------------
// SM1.3 specializations(s)
//-----------------------------------------------------------------------------

// Large problems, 1B data
template <typename ProblemType, typename T>
struct AutotunedGenre<ProblemType, SM13, LARGE_SIZE, T, 1>
	: Policy<ProblemType, SM13, util::io::ld::NONE, util::io::st::NONE, false, false, false, 12,
	  8, 8, 2, 2,
	  6, 2, 0, 5,
	  8, 8, 2, 1, 5>
{
	static const ProbSizeGenre PROB_SIZE_GENRE = LARGE_SIZE;
};

// Large problems, 2B data
template <typename ProblemType, typename T>
struct AutotunedGenre<ProblemType, SM13, LARGE_SIZE, T, 2>
	: Policy<ProblemType, SM13, util::io::ld::NONE, util::io::st::NONE, false, false, false, 10,
	  8, 7, 1, 1,
	  6, 2, 0, 5,
	  8, 6, 2, 2, 5>
{
	static const ProbSizeGenre PROB_SIZE_GENRE = LARGE_SIZE;
};

// Large problems, 4B data
template <typename ProblemType, typename T>
struct AutotunedGenre<ProblemType, SM13, LARGE_SIZE, T, 4>
	: Policy<ProblemType, SM13, util::io::ld::NONE, util::io::st::NONE, false, false, false, 8,
	  8, 7, 0, 1,
	  6, 2, 0, 5,
	  8, 7, 1, 0, 5>
{
	static const ProbSizeGenre PROB_SIZE_GENRE = LARGE_SIZE;
};

// All other Large problems
template <typename ProblemType, typename T, int T_SIZE>
struct AutotunedGenre<ProblemType, SM13, LARGE_SIZE, T, T_SIZE>
	: Policy<ProblemType, SM13, util::io::ld::NONE, util::io::st::NONE, false, false, false, 8,
	  8, 7, 1, 0,
	  6, 2, 0, 5,
	  8, 7, 1, 0, 5>
{
	static const ProbSizeGenre PROB_SIZE_GENRE = LARGE_SIZE;
};



// Small problems, 1B data
template <typename ProblemType, typename T>
struct AutotunedGenre<ProblemType, SM13, SMALL_SIZE, T, 1>
	: Policy<ProblemType, SM13, util::io::ld::NONE, util::io::st::NONE, false, false, false, 10,
	  8, 6, 2, 1,
	  6, 2, 0, 5,
	  8, 6, 2, 2, 5>
{
	static const ProbSizeGenre PROB_SIZE_GENRE = SMALL_SIZE;
};

// Small problems, 2B data
template <typename ProblemType, typename T>
struct AutotunedGenre<ProblemType, SM13, SMALL_SIZE, T, 2>
	: Policy<ProblemType, SM13, util::io::ld::NONE, util::io::st::NONE, false, true, false, 9,
	  8, 6, 1, 2,
	  6, 2, 0, 5,
	  8, 5, 2, 2, 5>
{
	static const ProbSizeGenre PROB_SIZE_GENRE = SMALL_SIZE;
};

// Small problems, 4B data
template <typename ProblemType, typename T>
struct AutotunedGenre<ProblemType, SM13, SMALL_SIZE, T, 4>
	: Policy<ProblemType, SM13, util::io::ld::NONE, util::io::st::NONE, false, false, false, 8,
	  8, 5, 2, 0,
	  6, 2, 0, 5,
	  8, 6, 1, 1, 5>
{
	static const ProbSizeGenre PROB_SIZE_GENRE = SMALL_SIZE;
};

// All other Small problems
template <typename ProblemType, typename T, int T_SIZE>
struct AutotunedGenre<ProblemType, SM13, SMALL_SIZE, T, T_SIZE>
	: Policy<ProblemType, SM13, util::io::ld::NONE, util::io::st::NONE, false, false, false, 6,
	  8, 5, 0, 1,
	  6, 2, 0, 5,
	  8, 5, 1, 0, 5>
{
	static const ProbSizeGenre PROB_SIZE_GENRE = SMALL_SIZE;
};



//-----------------------------------------------------------------------------
// SM1.0 specializations(s)
//-----------------------------------------------------------------------------






/******************************************************************************
 * Scan kernel entry points that can derive a tuned granularity type
 * implicitly from the PROB_SIZE_GENRE template parameter.  (As opposed to having
 * the granularity type passed explicitly.)
 *
 * TODO: Section can be removed if CUDA Runtime is fixed to
 * properly support template specialization around kernel call sites.
 ******************************************************************************/

/**
 * Tuned upsweep reduction kernel entry point
 */
template <typename ProblemType, int PROB_SIZE_GENRE>
__launch_bounds__ (
	(AutotunedGenre<ProblemType, __B40C_CUDA_ARCH__, (ProbSizeGenre) PROB_SIZE_GENRE>::Policy::Upsweep::THREADS),
	(AutotunedGenre<ProblemType, __B40C_CUDA_ARCH__, (ProbSizeGenre) PROB_SIZE_GENRE>::Policy::Upsweep::CTA_OCCUPANCY))
__global__ void TunedUpsweepKernel(
	typename ProblemType::T 								*d_in,
	typename ProblemType::T 								*d_spine,
	util::CtaWorkDistribution<typename ProblemType::SizeT> 	work_decomposition)
{
	// Load the kernel policy type identified by the enum for this architecture
	typedef typename AutotunedGenre<ProblemType, __B40C_CUDA_ARCH__, (ProbSizeGenre) PROB_SIZE_GENRE>::Upsweep KernelPolicy;

	// Shared storage for the kernel
	__shared__ typename KernelPolicy::SmemStorage smem_storage;

	upsweep::UpsweepPass<KernelPolicy>(d_in, d_spine, work_decomposition, smem_storage);
}

/**
 * Tuned spine scan kernel entry point
 */
template <typename ProblemType, int PROB_SIZE_GENRE>
__launch_bounds__ (
	(AutotunedGenre<ProblemType, __B40C_CUDA_ARCH__, (ProbSizeGenre) PROB_SIZE_GENRE>::Policy::Spine::THREADS),
	(AutotunedGenre<ProblemType, __B40C_CUDA_ARCH__, (ProbSizeGenre) PROB_SIZE_GENRE>::Policy::Spine::CTA_OCCUPANCY))
__global__ void TunedSpineKernel(
	typename ProblemType::T 		* d_in,
	typename ProblemType::T 		* d_out,
	typename ProblemType::SizeT 	spine_elements)
{
	// Load the kernel policy type identified by the enum for this architecture
	typedef typename AutotunedGenre<ProblemType, __B40C_CUDA_ARCH__, (ProbSizeGenre) PROB_SIZE_GENRE>::Spine KernelPolicy;

	// Shared storage for the kernel
	__shared__ typename KernelPolicy::SmemStorage smem_storage;

	spine::SpinePass<KernelPolicy>(d_in, d_out, spine_elements, smem_storage);
}


/**
 * Tuned downsweep scan kernel entry point
 */
template <typename ProblemType, int PROB_SIZE_GENRE>
__launch_bounds__ (
	(AutotunedGenre<ProblemType, __B40C_CUDA_ARCH__, (ProbSizeGenre) PROB_SIZE_GENRE>::Policy::Downsweep::THREADS),
	(AutotunedGenre<ProblemType, __B40C_CUDA_ARCH__, (ProbSizeGenre) PROB_SIZE_GENRE>::Policy::Downsweep::CTA_OCCUPANCY))
__global__ void TunedDownsweepKernel(
	typename ProblemType::T 			* d_in,
	typename ProblemType::T 			* d_out,
	typename ProblemType::T 			* d_spine,
	util::CtaWorkDistribution<typename ProblemType::SizeT> work_decomposition)
{
	// Load the kernel policy type identified by the enum for this architecture
	typedef typename AutotunedGenre<ProblemType, __B40C_CUDA_ARCH__, (ProbSizeGenre) PROB_SIZE_GENRE>::Downsweep KernelPolicy;

	// Shared storage for the kernel
	__shared__ typename KernelPolicy::SmemStorage smem_storage;

	downsweep::DownsweepPass<KernelPolicy>(d_in, d_out, d_spine, work_decomposition, smem_storage);
}


/******************************************************************************
 * Autotuned scan policy
 *******************************************************************************/

/**
 * Autotuned policy type
 */
template <
	typename ProblemType,
	int CUDA_ARCH,
	ProbSizeGenre PROB_SIZE_GENRE>
struct AutotunedPolicy :
	AutotunedGenre<
		ProblemType,
		CUDA_ARCH,
		PROB_SIZE_GENRE>
{
	//---------------------------------------------------------------------
	// Typedefs
	//---------------------------------------------------------------------

	typedef typename ProblemType::T 		T;
	typedef typename ProblemType::SizeT 	SizeT;

	typedef void (*UpsweepKernelPtr)(T*, T*, util::CtaWorkDistribution<SizeT>);
	typedef void (*SpineKernelPtr)(T*, T*, SizeT);
	typedef void (*DownsweepKernelPtr)(T*, T*, T*, util::CtaWorkDistribution<SizeT>);

	//---------------------------------------------------------------------
	// Kernel function pointer retrieval
	//---------------------------------------------------------------------

	static UpsweepKernelPtr UpsweepKernel() {
		return TunedUpsweepKernel<ProblemType, PROB_SIZE_GENRE>;
	}

	static SpineKernelPtr SpineKernel() {
		return TunedSpineKernel<ProblemType, PROB_SIZE_GENRE>;
	}

	static DownsweepKernelPtr DownsweepKernel() {
		return TunedDownsweepKernel<ProblemType, PROB_SIZE_GENRE>;
	}
};




}// namespace scan
}// namespace b40c
