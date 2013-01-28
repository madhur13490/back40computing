/******************************************************************************
 *
 * Copyright (c) 2010-2012, Duane Merrill.  All rights reserved.
 * Copyright (c) 2011-2012, NVIDIA CORPORATION.  All rights reserved.
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
 ******************************************************************************/

/******************************************************************************
 * Test of CtaScan utilities
 ******************************************************************************/

// Ensure printing of CUDA runtime errors to console
#define CUB_STDERR

#include <stdio.h>
#include <iostream>
#include <test_util.h>
#include "../cub.cuh"

using namespace cub;

//---------------------------------------------------------------------
// Globals, constants and typedefs
//---------------------------------------------------------------------

/**
 * Verbose output
 */
bool g_verbose = false;


/**
 * Primitive variant to test
 */
enum TestMode
{
	BASIC,
	AGGREGATE,
	PREFIX_AGGREGATE,
};



//---------------------------------------------------------------------
// Test kernels
//---------------------------------------------------------------------

// Stateful prefix functor
template <
    typename T,
    typename ScanOp>
struct CtaPrefixOp
{
    T       prefix;
    ScanOp  scan_op;

    __device__ __forceinline__
    CtaPrefixOp(T prefix, ScanOp scan_op) : prefix(prefix), scan_op(scan_op) {}

    __device__ __forceinline__
    T operator()(T local_aggregate)
    {
        T retval = prefix;
        prefix = scan_op(prefix, local_aggregate);
        return retval;
    }
};


/**
 * Exclusive CtaScan test kernel.
 */
template <
	int 		CTA_THREADS,
	int 		ITEMS_PER_THREAD,
	TestMode	TEST_MODE,
	typename 	T,
	typename 	ScanOp,
	typename 	IdentityT>
__global__ void CtaScanKernel(
	T 			*d_in,
	T 			*d_out,
	ScanOp 		scan_op,
	IdentityT 	identity,
	T			prefix,
	clock_t		*d_elapsed)
{
	const int TILE_SIZE = CTA_THREADS * ITEMS_PER_THREAD;

	// Cooperative warp-scan utility type (1 warp)
	typedef CtaScan<T, CTA_THREADS> CtaScan;

	// Shared memory
	__shared__ typename CtaScan::SmemStorage smem_storage;

	// Per-thread tile data
	T data[ITEMS_PER_THREAD];
	CtaLoadDirect(data, d_in, 0);

	// Record elapsed clocks
	clock_t start = clock();

	// Test scan
	T aggregate;
    CtaPrefixOp<T, ScanOp> prefix_op(prefix, scan_op);
	if (TEST_MODE == BASIC)
	{
		// Test basic warp scan
		CtaScan::ExclusiveScan(smem_storage, data, data, identity, scan_op);
	}
	else if (TEST_MODE == AGGREGATE)
	{
		// Test with cumulative aggregate
		CtaScan::ExclusiveScan(smem_storage, data, data, identity, scan_op, aggregate);
	}
	else if (TEST_MODE == PREFIX_AGGREGATE)
	{
		// Test with warp-prefix and cumulative aggregate
		CtaScan::ExclusiveScan(smem_storage, data, data, identity, scan_op, aggregate, prefix_op);
	}

	// Record elapsed clocks
	*d_elapsed = clock() - start;

	// Store output
	CtaStoreDirect(data, d_out, 0);

	// Store aggregate
	if (threadIdx.x == 0)
	{
		d_out[TILE_SIZE] = aggregate;
	}
}


/**
 * Inclusive CtaScan test kernel.
 */
template <
	int 		CTA_THREADS,
	int 		ITEMS_PER_THREAD,
	TestMode	TEST_MODE,
	typename 	T,
	typename 	ScanOp>
__global__ void CtaScanKernel(
	T 			*d_in,
	T 			*d_out,
	ScanOp 		scan_op,
	NullType,
	T			prefix,
	clock_t		*d_elapsed)
{
	const int TILE_SIZE = CTA_THREADS * ITEMS_PER_THREAD;

	// Cooperative warp-scan utility type (1 warp)
	typedef CtaScan<T, CTA_THREADS> CtaScan;

	// Shared memory
	__shared__ typename CtaScan::SmemStorage smem_storage;

	// Per-thread tile data
	T data[ITEMS_PER_THREAD];
	CtaLoadDirect(data, d_in, 0);

	// Record elapsed clocks
	clock_t start = clock();

	T aggregate;
    CtaPrefixOp<T, ScanOp> prefix_op(prefix, scan_op);
	if (TEST_MODE == BASIC)
	{
		// Test basic warp scan
		CtaScan::InclusiveScan(smem_storage, data, data, scan_op);
	}
	else if (TEST_MODE == AGGREGATE)
	{
		// Test with cumulative aggregate
		CtaScan::InclusiveScan(smem_storage, data, data, scan_op, aggregate);
	}
	else if (TEST_MODE == PREFIX_AGGREGATE)
	{
		// Test with warp-prefix and cumulative aggregate
		CtaScan::InclusiveScan(smem_storage, data, data, scan_op, aggregate, prefix_op);
	}

	// Record elapsed clocks
	*d_elapsed = clock() - start;

	// Store output
	CtaStoreDirect(data, d_out, 0);

	// Store aggregate
	if (threadIdx.x == 0)
	{
		d_out[TILE_SIZE] = aggregate;
	}
}


/**
 * Exclusive CtaScan test kernel (sum)
 */
template <
    int         CTA_THREADS,
    int         ITEMS_PER_THREAD,
    TestMode    TEST_MODE,
    typename    T>
__global__ void CtaScanKernel(
    T                                               *d_in,
    T                                               *d_out,
    Sum<T>,
    T,
    T                                               prefix,
    clock_t                                         *d_elapsed,
    typename EnableIf<Traits<T>::PRIMITIVE>::Type   *dummy = NULL)
{
    const int TILE_SIZE = CTA_THREADS * ITEMS_PER_THREAD;

    // Cooperative warp-scan utility type (1 warp)
    typedef CtaScan<T, CTA_THREADS> CtaScan;

    // Shared memory
    __shared__ typename CtaScan::SmemStorage smem_storage;

    // Per-thread tile data
    T data[ITEMS_PER_THREAD];
    CtaLoadDirect(data, d_in, 0);

    // Record elapsed clocks
    clock_t start = clock();

    // Test scan
    T aggregate;
    CtaPrefixOp<T, Sum<T> > prefix_op(prefix, Sum<T>());
    if (TEST_MODE == BASIC)
    {
        // Test basic warp scan
        CtaScan::ExclusiveSum(smem_storage, data, data);
    }
    else if (TEST_MODE == AGGREGATE)
    {
        // Test with cumulative aggregate
        CtaScan::ExclusiveSum(smem_storage, data, data, aggregate);
    }
    else if (TEST_MODE == PREFIX_AGGREGATE)
    {
        // Test with warp-prefix and cumulative aggregate
        CtaScan::ExclusiveSum(smem_storage, data, data, aggregate, prefix_op);
    }

    // Record elapsed clocks
    *d_elapsed = clock() - start;

    // Store output
    CtaStoreDirect(data, d_out, 0);

    // Store aggregate
    if (threadIdx.x == 0)
    {
        d_out[TILE_SIZE] = aggregate;
    }
}


/**
 * Inclusive CtaScan test kernel (sum)
 */
template <
    int         CTA_THREADS,
    int         ITEMS_PER_THREAD,
    TestMode    TEST_MODE,
    typename    T>
__global__ void CtaScanKernel(
    T                                               *d_in,
    T                                               *d_out,
    Sum<T>,
    NullType,
    T                                               prefix,
    clock_t                                         *d_elapsed,
    typename EnableIf<Traits<T>::PRIMITIVE>::Type   *dummy = NULL)
{
    const int TILE_SIZE = CTA_THREADS * ITEMS_PER_THREAD;

    // Cooperative warp-scan utility type (1 warp)
    typedef CtaScan<T, CTA_THREADS> CtaScan;

    // Shared memory
    __shared__ typename CtaScan::SmemStorage smem_storage;

    // Per-thread tile data
    T data[ITEMS_PER_THREAD];
    CtaLoadDirect(data, d_in, 0);

    // Record elapsed clocks
    clock_t start = clock();

    T aggregate;
    CtaPrefixOp<T, Sum<T> > prefix_op(prefix, Sum<T>());
    if (TEST_MODE == BASIC)
    {
        // Test basic warp scan
        CtaScan::InclusiveSum(smem_storage, data, data);
    }
    else if (TEST_MODE == AGGREGATE)
    {
        // Test with cumulative aggregate
        CtaScan::InclusiveSum(smem_storage, data, data, aggregate);
    }
    else if (TEST_MODE == PREFIX_AGGREGATE)
    {
        // Test with warp-prefix and cumulative aggregate
        CtaScan::InclusiveSum(smem_storage, data, data, aggregate, prefix_op);
    }

    // Record elapsed clocks
    *d_elapsed = clock() - start;

    // Store output
    CtaStoreDirect(data, d_out, 0);

    // Store aggregate
    if (threadIdx.x == 0)
    {
        d_out[TILE_SIZE] = aggregate;
    }
}



//---------------------------------------------------------------------
// Host utility subroutines
//---------------------------------------------------------------------

/**
 * Initialize exclusive-scan problem (and solution)
 */
template <
	typename 	T,
	typename 	ScanOp,
	typename 	IdentityT>
T Initialize(
	int		 	gen_mode,
	T 			*h_in,
	T 			*h_reference,
	int 		num_elements,
	ScanOp 		scan_op,
	IdentityT 	identity,
	T			*prefix)
{
	T inclusive = (prefix != NULL) ? *prefix : identity;
    T aggregate = identity;

	for (int i = 0; i < num_elements; ++i)
	{
		InitValue(gen_mode, h_in[i], i);
		h_reference[i] = inclusive;
		inclusive = scan_op(inclusive, h_in[i]);
        aggregate = scan_op(aggregate, h_in[i]);
	}

	return aggregate;
}


/**
 * Initialize inclusive-scan problem (and solution)
 */
template <
	typename 	T,
	typename 	ScanOp>
T Initialize(
	int		 	gen_mode,
	T 			*h_in,
	T 			*h_reference,
	int 		num_elements,
	ScanOp 		scan_op,
	NullType,
	T			*prefix)
{
	T inclusive;
    T aggregate;
	for (int i = 0; i < num_elements; ++i)
	{
		InitValue(gen_mode, h_in[i], i);
		if (i == 0)
		{
			inclusive = (prefix != NULL) ?
				scan_op(*prefix, h_in[0]) :
				h_in[0];
            aggregate = h_in[0];
		}
		else
		{
			inclusive = scan_op(inclusive, h_in[i]);
            aggregate = scan_op(aggregate, h_in[i]);
		}
		h_reference[i] = inclusive;
	}

	return aggregate;
}


/**
 * Test CTA scan
 */
template <
	int 		CTA_THREADS,
	int 		ITEMS_PER_THREAD,
	TestMode 	TEST_MODE,
	typename 	ScanOp,
	typename 	IdentityT,		// NullType implies inclusive-scan, otherwise inclusive scan
	typename 	T>
void Test(
	int 		gen_mode,
	ScanOp 		scan_op,
	IdentityT 	identity,
	T			prefix,
	char		*type_string)
{
	const int TILE_SIZE = CTA_THREADS * ITEMS_PER_THREAD;

	// Allocate host arrays
	T *h_in = new T[TILE_SIZE];
	T *h_reference = new T[TILE_SIZE];

	// Initialize problem
	T *p_prefix = (TEST_MODE == PREFIX_AGGREGATE) ? &prefix : NULL;
	T aggregate = Initialize(
		gen_mode,
		h_in,
		h_reference,
		TILE_SIZE,
		scan_op,
		identity,
		p_prefix);

	// Initialize device arrays
	T *d_in = NULL;
	T *d_out = NULL;
	clock_t *d_elapsed = NULL;
	CubDebugExit(cudaMalloc((void**)&d_in, sizeof(T) * TILE_SIZE));
	CubDebugExit(cudaMalloc((void**)&d_out, sizeof(T) * (TILE_SIZE + 1)));
	CubDebugExit(cudaMalloc((void**)&d_elapsed, sizeof(clock_t)));
	CubDebugExit(cudaMemcpy(d_in, h_in, sizeof(T) * TILE_SIZE, cudaMemcpyHostToDevice));

	// Run kernel
	printf("Test-mode %d, gen-mode %d, %s CtaScan, %d CTA threads, %d items per thread, %s (%d bytes) elements:\n",
		TEST_MODE,
		gen_mode,
		(Equals<IdentityT, NullType>::VALUE) ? "Inclusive" : "Exclusive",
		CTA_THREADS,
		ITEMS_PER_THREAD,
		type_string,
		(int) sizeof(T));
	fflush(stdout);

	// Display input problem data
	if (g_verbose)
	{
		printf("Input data: ");
		for (int i = 0; i < TILE_SIZE; i++)
		{
			std::cout << CoutCast(h_in[i]) << ", ";
		}
		printf("\n\n");
	}

	// Run aggregate/prefix kernel
	CtaScanKernel<CTA_THREADS, ITEMS_PER_THREAD, TEST_MODE><<<1, CTA_THREADS>>>(
		d_in,
		d_out,
		scan_op,
		identity,
		prefix,
		d_elapsed);

	if (g_verbose)
	{
		printf("\tElapsed clocks: ");
		DisplayDeviceResults(d_elapsed, 1);
	}

	CubDebugExit(cudaDeviceSynchronize());

	// Copy out and display results
	printf("\tScan results: ");
	AssertEquals(0, CompareDeviceResults(h_reference, d_out, TILE_SIZE, g_verbose, g_verbose));
	printf("\n");

	// Copy out and display aggregate
	if ((TEST_MODE == AGGREGATE) || (TEST_MODE == PREFIX_AGGREGATE))
	{
		printf("\tScan aggregate: ");
		AssertEquals(0, CompareDeviceResults(&aggregate, d_out + TILE_SIZE, 1, g_verbose, g_verbose));
		printf("\n");
	}

	// Cleanup
	if (h_in) delete h_in;
	if (h_reference) delete h_in;
	if (d_in) CubDebugExit(cudaFree(d_in));
	if (d_out) CubDebugExit(cudaFree(d_out));
}


/**
 * Run battery of tests for different primitive variants
 */
template <
	int 		CTA_THREADS,
	int 		ITEMS_PER_THREAD,
	typename 	ScanOp,
	typename 	T>
void Test(
	int 		gen_mode,
	ScanOp 		scan_op,
	T 			identity,
	T			prefix,
	char *		type_string)
{
	// Exclusive
	Test<CTA_THREADS, ITEMS_PER_THREAD, BASIC>(gen_mode, scan_op, identity, prefix, type_string);
	Test<CTA_THREADS, ITEMS_PER_THREAD, AGGREGATE>(gen_mode, scan_op, identity, prefix, type_string);
	Test<CTA_THREADS, ITEMS_PER_THREAD, PREFIX_AGGREGATE>(gen_mode, scan_op, identity, prefix, type_string);

	// Inclusive
	Test<CTA_THREADS, ITEMS_PER_THREAD, BASIC>(gen_mode, scan_op, NullType(), prefix, type_string);
	Test<CTA_THREADS, ITEMS_PER_THREAD, AGGREGATE>(gen_mode, scan_op, NullType(), prefix, type_string);
	Test<CTA_THREADS, ITEMS_PER_THREAD, PREFIX_AGGREGATE>(gen_mode, scan_op, NullType(), prefix, type_string);
}


/**
 * Run battery of tests for different data types and scan ops
 */
template <
	int CTA_THREADS,
	int ITEMS_PER_THREAD>
void Test(int gen_mode)
{
	// primitive
	Test<CTA_THREADS, ITEMS_PER_THREAD>(gen_mode, Sum<unsigned char>(), (unsigned char) 0, (unsigned char) 99, CUB_TYPE_STRING(Sum<unsigned char>));
	Test<CTA_THREADS, ITEMS_PER_THREAD>(gen_mode, Sum<unsigned short>(), (unsigned short) 0, (unsigned short) 99, CUB_TYPE_STRING(Sum<unsigned short>));
	Test<CTA_THREADS, ITEMS_PER_THREAD>(gen_mode, Sum<unsigned int>(), (unsigned int) 0, (unsigned int) 99, CUB_TYPE_STRING(Sum<unsigned int>));
	Test<CTA_THREADS, ITEMS_PER_THREAD>(gen_mode, Sum<unsigned long long>(), (unsigned long long) 0, (unsigned long long) 99, CUB_TYPE_STRING(Sum<unsigned long long>));

	// primitive (alternative scan op)
	Test<CTA_THREADS, ITEMS_PER_THREAD>(gen_mode, Max<unsigned char>(), (unsigned char) 0, (unsigned char) 99, CUB_TYPE_STRING(Max<unsigned char>));
	Test<CTA_THREADS, ITEMS_PER_THREAD>(gen_mode, Max<unsigned short>(), (unsigned short) 0, (unsigned short) 99, CUB_TYPE_STRING(Max<unsigned short>));
	Test<CTA_THREADS, ITEMS_PER_THREAD>(gen_mode, Max<unsigned int>(), (unsigned int) 0, (unsigned int) 99, CUB_TYPE_STRING(Max<unsigned int>));
	Test<CTA_THREADS, ITEMS_PER_THREAD>(gen_mode, Max<unsigned long long>(), (unsigned long long) 0, (unsigned long long) 99, CUB_TYPE_STRING(Max<unsigned long long>));

	// vec-2
	Test<CTA_THREADS, ITEMS_PER_THREAD>(gen_mode, Sum<uchar2>(), make_uchar2(0, 0), make_uchar2(17, 21), CUB_TYPE_STRING(Sum<uchar2>));
	Test<CTA_THREADS, ITEMS_PER_THREAD>(gen_mode, Sum<ushort2>(), make_ushort2(0, 0), make_ushort2(17, 21), CUB_TYPE_STRING(Sum<ushort2>));
	Test<CTA_THREADS, ITEMS_PER_THREAD>(gen_mode, Sum<uint2>(), make_uint2(0, 0), make_uint2(17, 21), CUB_TYPE_STRING(Sum<uint2>));
	Test<CTA_THREADS, ITEMS_PER_THREAD>(gen_mode, Sum<ulonglong2>(), make_ulonglong2(0, 0), make_ulonglong2(17, 21), CUB_TYPE_STRING(Sum<ulonglong2>));

	// vec-4
	Test<CTA_THREADS, ITEMS_PER_THREAD>(gen_mode, Sum<uchar4>(), make_uchar4(0, 0, 0, 0), make_uchar4(17, 21, 32, 85), CUB_TYPE_STRING(Sum<uchar4>));
	Test<CTA_THREADS, ITEMS_PER_THREAD>(gen_mode, Sum<ushort4>(), make_ushort4(0, 0, 0, 0), make_ushort4(17, 21, 32, 85), CUB_TYPE_STRING(Sum<ushort4>));
	Test<CTA_THREADS, ITEMS_PER_THREAD>(gen_mode, Sum<uint4>(), make_uint4(0, 0, 0, 0), make_uint4(17, 21, 32, 85), CUB_TYPE_STRING(Sum<uint4>));
	Test<CTA_THREADS, ITEMS_PER_THREAD>(gen_mode, Sum<ulonglong4>(), make_ulonglong4(0, 0, 0, 0), make_ulonglong4(17, 21, 32, 85), CUB_TYPE_STRING(Sum<ulonglong4>));

	// complex
	Test<CTA_THREADS, ITEMS_PER_THREAD>(gen_mode, Sum<TestFoo>(), TestFoo::MakeTestFoo(0, 0, 0, 0), TestFoo::MakeTestFoo(17, 21, 32, 85), CUB_TYPE_STRING(Sum<TestFoo>));
	Test<CTA_THREADS, ITEMS_PER_THREAD>(gen_mode, Sum<TestBar>(), TestBar::MakeTestBar(0, 0), TestBar::MakeTestBar(17, 21), CUB_TYPE_STRING(Sum<TestBar>));
}


/**
 * Run battery of tests for different problem generation options
 */
template <int CTA_THREADS, int ITEMS_PER_THREAD>
void Test()
{
	Test<CTA_THREADS, ITEMS_PER_THREAD>(UNIFORM);
	Test<CTA_THREADS, ITEMS_PER_THREAD>(SEQ_INC);
	Test<CTA_THREADS, ITEMS_PER_THREAD>(RANDOM);
}


/**
 * Run battery of tests for different items per thread
 */
template <int CTA_THREADS>
void Test()
{
	Test<CTA_THREADS, 1>();
	Test<CTA_THREADS, 2>();
	Test<CTA_THREADS, 3>();
	Test<CTA_THREADS, 8>();
}



/**
 * Main
 */
int main(int argc, char** argv)
{
    // Initialize command line
    CommandLineArgs args(argc, argv);
    g_verbose = args.CheckCmdLineFlag("v");
    bool quick = args.CheckCmdLineFlag("quick");

    // Print usage
    if (args.CheckCmdLineFlag("help"))
    {
    	printf("%s "
    		"[--device=<device-id>] "
    		"[--v] "
    		"[--quick]"
    		"\n", argv[0]);
    	exit(0);
    }

    // Initialize device
    CubDebugExit(args.DeviceInit());

    if (quick)
    {
        // Quick exclusive test
    	Test<128, 4, BASIC>(UNIFORM, Sum<int>(), int(0), int(10), CUB_TYPE_STRING(Sum<int));
/*
        TestFoo prefix = TestFoo::MakeTestFoo(17, 21, 32, 85);
        Test<128, 2, PREFIX_AGGREGATE>(SEQ_INC, Sum<TestFoo>(), NullType(), prefix, CUB_TYPE_STRING(Sum<TestFoo>));
*/
    }
    else
    {

        // Run battery of tests for different CTA sizes
        Test<17>();
        Test<32>();
        Test<62>();
        Test<65>();
        Test<96>();
        Test<128>();

    }

    return 0;
}



