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
 * Memcopy kernel
 ******************************************************************************/

#pragma once

#include "b40c_cuda_properties.cuh"
#include "b40c_kernel_utils.cuh"
#include "b40c_kernel_data_movement.cuh"

namespace b40c {
namespace memcopy {


/******************************************************************************
 * Memcopy kernel subroutines
 ******************************************************************************/


template <typename Config, bool UNGUARDED_IO>
__device__ __forceinline__ void ProcessTile(
	typename Config::T * __restrict d_out,
	typename Config::T * __restrict d_in,
	typename Config::SizeT 	cta_offset,
	typename Config::SizeT 	out_of_bounds)
{
	typedef typename Config::T T;
	typedef typename Config::SizeT SizeT;

	T data[Config::LOADS_PER_TILE][Config::LOAD_VEC_SIZE];

	// Load tile
	LoadTile<
		T,
		SizeT,
		Config::LOG_LOADS_PER_TILE,
		Config::LOG_LOAD_VEC_SIZE,
		Config::THREADS,
		Config::CACHE_MODIFIER,
		UNGUARDED_IO>::Invoke(data, d_in, cta_offset, out_of_bounds);

	__syncthreads();

	// Store tile
	StoreTile<
		T,
		SizeT,
		Config::LOG_LOADS_PER_TILE,
		Config::LOG_LOAD_VEC_SIZE,
		Config::THREADS,
		Config::CACHE_MODIFIER,
		UNGUARDED_IO>::Invoke(data, d_out, cta_offset, out_of_bounds);
}


/**
 * Memcopy pass (non-workstealing)
 */
template <typename Config, bool WORK_STEALING>
struct MemcopyPass
{
	static __device__ __forceinline__ void Invoke(
		typename Config::T 			* __restrict &d_out,
		typename Config::T 			* __restrict &d_in,
		typename Config::SizeT 		* __restrict &d_work_progress,
		CtaWorkDistribution<typename Config::SizeT> &work_decomposition,
		int &progress_selector,
		int &extra_bytes)
	{
		typedef typename Config::SizeT SizeT;

		// Determine our threadblock's work range
		SizeT cta_offset;			// Offset at which this CTA begins processing
		SizeT cta_elements;			// Total number of elements for this CTA to process
		SizeT guarded_offset; 		// Offset of final, partially-full tile (requires guarded loads)
		SizeT guarded_elements;		// Number of elements in partially-full tile

		work_decomposition.GetCtaWorkLimits<Config::LOG_TILE_ELEMENTS, Config::LOG_SCHEDULE_GRANULARITY>(
			cta_offset, cta_elements, guarded_offset, guarded_elements);

		SizeT out_of_bounds = cta_offset + cta_elements;

		// Copy full tiles of tile_elements
		while (cta_offset < guarded_offset) {

			ProcessTile<Config, true>(d_out, d_in, cta_offset, out_of_bounds);
			cta_offset += Config::TILE_ELEMENTS;
		}

		// Clean up last partial tile with guarded-io
		if (guarded_elements) {
			ProcessTile<Config, false>(d_out, d_in, cta_offset, out_of_bounds);
		}

		// Cleanup any extra bytes
		if ((sizeof(typename Config::T) > 1) && (blockIdx.x == gridDim.x - 1) && (threadIdx.x < extra_bytes)) {

			unsigned char* d_in_bytes = reinterpret_cast<unsigned char *>(d_in + out_of_bounds);
			unsigned char* d_out_bytes = reinterpret_cast<unsigned char *>(d_out + out_of_bounds);
			unsigned char extra_byte;

			ModifiedLoad<unsigned char, Config::CACHE_MODIFIER>::Ld(extra_byte, d_in_bytes, threadIdx.x);
			ModifiedStore<unsigned char, Config::CACHE_MODIFIER>::St(extra_byte, d_out_bytes, threadIdx.x);
		}
	}
};


/**
 * Memcopy pass (workstealing)
 */
template <typename Config>
struct MemcopyPass <Config, true>
{
	static __device__ __forceinline__ void Invoke(
		typename Config::T 			* __restrict &d_out,
		typename Config::T 			* __restrict &d_in,
		typename Config::SizeT 		* __restrict &d_work_progress,
		CtaWorkDistribution<typename Config::SizeT> &work_decomposition,
		int &progress_selector,
		int &extra_bytes)
	{
		typedef typename Config::SizeT SizeT;

		__shared__ SizeT cta_offset;

		// First CTA resets the work progress for the next pass
		if ((blockIdx.x == 0) && (threadIdx.x == 0)) {
			d_work_progress[progress_selector ^ 1] = 0;
		}

		// Steal full-tiles of work, incrementing progress counter
		SizeT unguarded_elements = work_decomposition.num_elements & (~(Config::TILE_ELEMENTS - 1));
		while (true) {

			// Thread zero atomically steals work from the progress counter
			if (threadIdx.x == 0) {
				cta_offset = atomicAdd(&d_work_progress[progress_selector], Config::TILE_ELEMENTS);
			}

			__syncthreads();

			if (cta_offset >= unguarded_elements) {
				// All done
				break;
			}

			ProcessTile<Config, true>(d_out, d_in, cta_offset, unguarded_elements);
		}

		// Last CTA does any extra, guarded work
		if (blockIdx.x == gridDim.x - 1) {

			ProcessTile<Config, false>(d_out, d_in, unguarded_elements, work_decomposition.num_elements);

			// Cleanup any extra bytes
			if ((sizeof(typename Config::T) > 1) && (threadIdx.x < extra_bytes)) {
				unsigned char* d_in_bytes = reinterpret_cast<unsigned char *>(d_in + work_decomposition.num_elements);
				unsigned char* d_out_bytes = reinterpret_cast<unsigned char *>(d_out + work_decomposition.num_elements);
				unsigned char extra_byte;
				ModifiedLoad<unsigned char, Config::CACHE_MODIFIER>::Ld(extra_byte, d_in_bytes, threadIdx.x);
				ModifiedStore<unsigned char, Config::CACHE_MODIFIER>::St(extra_byte, d_out_bytes, threadIdx.x);
			}
		}
	}
};


/**
 * Upsweep reduction kernel entry point 
 */
template <typename Config>
__launch_bounds__ (Config::THREADS, Config::CTA_OCCUPANCY)
__global__ 
void MemcopyKernel(
	typename Config::T 			* __restrict d_out,
	typename Config::T 			* __restrict d_in,
	typename Config::SizeT 		* __restrict d_work_progress,
	CtaWorkDistribution<typename Config::SizeT> work_decomposition,
	int progress_selector,
	int extra_bytes)
{
	MemcopyPass<Config, Config::WORK_STEALING>::Invoke(
		d_out, d_in, d_work_progress, work_decomposition, progress_selector, extra_bytes);
}


/**
 * Wrapper stub for arbitrary types to quiet the linker
 */
template <typename Config>
void __wrapper__device_stub_MemcopyKernel(
	typename Config::T 			* __restrict &,
	typename Config::T 			* __restrict &,
	typename Config::SizeT 		* __restrict &,
	CtaWorkDistribution<typename Config::SizeT> &,
	int &,
	int &) {}



} // namespace memcopy
} // namespace b40c
