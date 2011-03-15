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
 * Thanks!
 * 
 ******************************************************************************/

/******************************************************************************
 * Tile-processing functionality for segmented scan downsweep reduction kernels
 ******************************************************************************/

#pragma once

#include <b40c/util/soa_tuple.cuh>
#include <b40c/util/scan/soa/cooperative_soa_scan.cuh>

namespace b40c {
namespace segmented_scan {


/**
 * Derivation of KernelConfig that encapsulates segmented-scan downsweep
 * reduction tile-processing state and routines
 */
template <typename KernelConfig>
struct ScanCta : KernelConfig						// Derive from our config
{
	//---------------------------------------------------------------------
	// Typedefs
	//---------------------------------------------------------------------

	typedef typename KernelConfig::T T;
	typedef typename KernelConfig::Flag Flag;
	typedef typename KernelConfig::SizeT SizeT;
	typedef typename KernelConfig::SrtsSoaDetails SrtsSoaDetails;
	typedef typename KernelConfig::SoaTuple SoaTuple;

	typedef T PartialsTile[KernelConfig::LOADS_PER_TILE][KernelConfig::LOAD_VEC_SIZE];
	typedef Flag FlagsTile[KernelConfig::LOADS_PER_TILE][KernelConfig::LOAD_VEC_SIZE];

	typedef util::Tuple<
		T (*)[KernelConfig::LOAD_VEC_SIZE],
		Flag (*)[KernelConfig::LOAD_VEC_SIZE]> DataSoa;

	//---------------------------------------------------------------------
	// Members
	//---------------------------------------------------------------------

	// Operational details for SRTS grid
	SrtsSoaDetails 	srts_soa_details;

	// The tuple value we will accumulate (in raking threads only)
	SoaTuple 		carry;

	// Input device pointers
	T 				*d_partials_in;
	Flag 			*d_flags_in;

	// Output device pointer
	T 				*d_partials_out;

	// Tile of segmented scan elements
	PartialsTile	partials;

	// Tile of flags
	FlagsTile		flags;

	// Soa reference to tiles
	DataSoa			data_soa;

	//---------------------------------------------------------------------
	// Methods
	//---------------------------------------------------------------------

	/**
	 * Constructor
	 */
	__device__ __forceinline__ ScanCta(
		SrtsSoaDetails srts_soa_details,
		T 		*d_partials_in,
		Flag 	*d_flags_in,
		T 		*d_partials_out,
		T 		spine_partial = KernelConfig::Identity(),
		Flag 	spine_flag = KernelConfig::FlagIdentity()) :

			srts_soa_details(srts_soa_details),
			d_partials_in(d_partials_in),
			d_flags_in(d_flags_in),
			d_partials_out(d_partials_out),
			data_soa(partials, flags),
			carry(spine_partial, spine_flag) {}			// Seed carry with spine partial & flag


	/**
	 * Process a single tile
	 */
	template <bool UNGUARDED_IO>
	__device__ __forceinline__ void ProcessTile(
		SizeT cta_offset,
		SizeT out_of_bounds)
	{
		// Load tile of partials
		util::LoadTile<
			T,
			SizeT,
			KernelConfig::LOG_LOADS_PER_TILE,
			KernelConfig::LOG_LOAD_VEC_SIZE,
			KernelConfig::THREADS,
			KernelConfig::READ_MODIFIER,
			UNGUARDED_IO>::Invoke(partials, d_partials_in, cta_offset, out_of_bounds);

		// Load tile of flags
		util::LoadTile<
			Flag,
			SizeT,
			KernelConfig::LOG_LOADS_PER_TILE,
			KernelConfig::LOG_LOAD_VEC_SIZE,
			KernelConfig::THREADS,
			KernelConfig::READ_MODIFIER,
			UNGUARDED_IO>::Invoke(flags, d_flags_in, cta_offset, out_of_bounds);

		// Scan tile with carry update in raking threads
		util::scan::soa::CooperativeSoaTileScan<
			SrtsSoaDetails,
			KernelConfig::LOAD_VEC_SIZE,
			EXCLUSIVE,									// Always inclusive: we handle the exclusive/inclusive details in our reduction/scan ops
			KernelConfig::SoaScanOp>::template ScanTileWithCarry<DataSoa>(
				srts_soa_details,
				data_soa,
				carry);

		// Store tile of partials
		util::StoreTile<
			T,
			SizeT,
			KernelConfig::LOG_LOADS_PER_TILE,
			KernelConfig::LOG_LOAD_VEC_SIZE,
			KernelConfig::THREADS,
			KernelConfig::WRITE_MODIFIER,
			UNGUARDED_IO>::Invoke(partials, d_partials_out, cta_offset, out_of_bounds);
	}
};



} // namespace segmented_scan
} // namespace b40c
