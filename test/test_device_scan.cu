/******************************************************************************
 * Copyright (c) 2011, Duane Merrill.  All rights reserved.
 * Copyright (c) 2011-2013, NVIDIA CORPORATION.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of the NVIDIA CORPORATION nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL NVIDIA CORPORATION BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 ******************************************************************************/

/******************************************************************************
 * Test of DeviceScan utilities
 ******************************************************************************/

// Ensure printing of CUDA runtime errors to console
#define CUB_STDERR

#include <stdio.h>

#include <cub/util_allocator.cuh>
#include <cub/device/device_scan.cuh>

#include "test_util.h"

using namespace cub;


//---------------------------------------------------------------------
// Globals, constants and typedefs
//---------------------------------------------------------------------

bool                    g_verbose           = false;
int                     g_timing_iterations = 0;
int                     g_repeat            = 0;
CachingDeviceAllocator  g_allocator(true);



//---------------------------------------------------------------------
// Dispatch to different DeviceScan entrypoints
//---------------------------------------------------------------------

/**
 * Dispatch to exclusive scan entrypoint
 */
template <typename InputIterator, typename OutputIterator, typename ScanOp, typename Identity, typename Offset>
__host__ __device__ __forceinline__
cudaError_t Dispatch(
    Int2Type<false>     use_cdp,
    int                 timing_iterations,
    size_t              *d_temp_storage_bytes,
    cudaError_t         *d_cdp_error,

    void                *d_temp_storage,
    size_t              &temp_storage_bytes,
    InputIterator     d_in,
    OutputIterator    d_out,
    ScanOp              scan_op,
    Identity            identity,
    Offset               num_items,
    cudaStream_t        stream,
    bool                debug_synchronous)
{
    cudaError_t error = cudaSuccess;
    for (int i = 0; i < timing_iterations; ++i)
    {
        error = DeviceScan::ExclusiveScan(d_temp_storage, temp_storage_bytes, d_in, d_out, scan_op, identity, num_items, stream, debug_synchronous);
    }
    return error;
}


/**
 * Dispatch to exclusive sum entrypoint
 */
template <typename InputIterator, typename OutputIterator, typename T, typename Identity, typename Offset>
__host__ __device__ __forceinline__
cudaError_t Dispatch(
    Int2Type<false>     use_cdp,
    int                 timing_iterations,
    size_t              *d_temp_storage_bytes,
    cudaError_t         *d_cdp_error,

    void                *d_temp_storage,
    size_t              &temp_storage_bytes,
    InputIterator     d_in,
    OutputIterator    d_out,
    Sum                 scan_op,
    Identity            identity,
    Offset               num_items,
    cudaStream_t        stream,
    bool                debug_synchronous)
{
    cudaError_t error = cudaSuccess;
    for (int i = 0; i < timing_iterations; ++i)
    {
        error = DeviceScan::ExclusiveSum(d_temp_storage, temp_storage_bytes, d_in, d_out, num_items, stream, debug_synchronous);
    }
    return error;
}


/**
 * Dispatch to inclusive scan entrypoint
 */
template <typename InputIterator, typename OutputIterator, typename ScanOp, typename Offset>
__host__ __device__ __forceinline__
cudaError_t Dispatch(
    Int2Type<false>     use_cdp,
    int                 timing_iterations,
    size_t              *d_temp_storage_bytes,
    cudaError_t         *d_cdp_error,

    void                *d_temp_storage,
    size_t              &temp_storage_bytes,
    InputIterator     d_in,
    OutputIterator    d_out,
    ScanOp              scan_op,
    NullType            identity,
    Offset               num_items,
    cudaStream_t        stream,
    bool                debug_synchronous)
{
    cudaError_t error = cudaSuccess;
    for (int i = 0; i < timing_iterations; ++i)
    {
        error = DeviceScan::InclusiveScan(d_temp_storage, temp_storage_bytes, d_in, d_out, scan_op, num_items, stream, debug_synchronous);
    }
    return error;
}


/**
 * Dispatch to inclusive sum entrypoint
 */
template <typename InputIterator, typename OutputIterator, typename T, typename Offset>
__host__ __device__ __forceinline__
cudaError_t Dispatch(
    Int2Type<false>     use_cdp,
    int                 timing_iterations,
    size_t              *d_temp_storage_bytes,
    cudaError_t         *d_cdp_error,

    void                *d_temp_storage,
    size_t              &temp_storage_bytes,
    InputIterator     d_in,
    OutputIterator    d_out,
    Sum                 scan_op,
    NullType            identity,
    Offset               num_items,
    cudaStream_t        stream,
    bool                debug_synchronous)
{
    cudaError_t error = cudaSuccess;
    for (int i = 0; i < timing_iterations; ++i)
    {
        error = DeviceScan::InclusiveSum(d_temp_storage, temp_storage_bytes, d_in, d_out, num_items, stream, debug_synchronous);
    }
    return error;
}


//---------------------------------------------------------------------
// CUDA Nested Parallelism Test Kernel
//---------------------------------------------------------------------

/**
 * Simple wrapper kernel to invoke DeviceScan
 */
template <typename InputIterator, typename OutputIterator, typename ScanOp, typename Identity, typename Offset>
__global__ void CnpDispatchKernel(
    int                 timing_iterations,
    size_t              *d_temp_storage_bytes,
    cudaError_t         *d_cdp_error,

    void                *d_temp_storage,
    size_t              temp_storage_bytes,
    InputIterator     d_in,
    OutputIterator    d_out,
    ScanOp              scan_op,
    Identity            identity,
    Offset               num_items,
    bool                debug_synchronous)
{
#ifndef CUB_CDP
    *d_cdp_error = cudaErrorNotSupported;
#else
    *d_cdp_error = Dispatch(Int2Type<false>(), timing_iterations, d_temp_storage_bytes, d_cdp_error, d_temp_storage, temp_storage_bytes, d_in, d_out, scan_op, identity, num_items, 0, debug_synchronous);
    *d_temp_storage_bytes = temp_storage_bytes;
#endif
}


/**
 * Dispatch to CDP kernel
 */
template <typename InputIterator, typename OutputIterator, typename ScanOp, typename Identity, typename Offset>
cudaError_t Dispatch(
    Int2Type<true>      use_cdp,
    int                 timing_iterations,
    size_t              *d_temp_storage_bytes,
    cudaError_t         *d_cdp_error,

    void                *d_temp_storage,
    size_t              &temp_storage_bytes,
    InputIterator     d_in,
    OutputIterator    d_out,
    ScanOp              scan_op,
    Identity            identity,
    Offset               num_items,
    cudaStream_t        stream,
    bool                debug_synchronous)
{
    // Invoke kernel to invoke device-side dispatch
    CnpDispatchKernel<<<1,1>>>(timing_iterations, d_temp_storage_bytes, d_cdp_error, d_temp_storage, temp_storage_bytes, d_in, d_out, scan_op, identity, num_items, debug_synchronous);

    // Copy out temp_storage_bytes
    CubDebugExit(cudaMemcpy(&temp_storage_bytes, d_temp_storage_bytes, sizeof(size_t) * 1, cudaMemcpyDeviceToHost));

    // Copy out error
    cudaError_t retval;
    CubDebugExit(cudaMemcpy(&retval, d_cdp_error, sizeof(cudaError_t) * 1, cudaMemcpyDeviceToHost));
    return retval;
}



//---------------------------------------------------------------------
// Test generation
//---------------------------------------------------------------------


/**
 * Initialize problem
 */
template <typename T>
void Initialize(
    GenMode      gen_mode,
    T            *h_in,
    int          num_items)
{
    for (int i = 0; i < num_items; ++i)
    {
        InitValue(gen_mode, h_in[i], i);
    }
}

/**
 * Solve exclusive-scan problem
 */
template <
    typename        InputIterator,
    typename        T,
    typename        ScanOp,
    typename        IdentityT>
T Solve(
    InputIterator   h_in,
    T               *h_reference,
    int             num_items,
    ScanOp          scan_op,
    IdentityT       identity)
{
    T inclusive = identity;
    T aggregate = identity;

    for (int i = 0; i < num_items; ++i)
    {
        h_reference[i] = inclusive;
        inclusive = scan_op(inclusive, h_in[i]);
        aggregate = scan_op(aggregate, h_in[i]);
    }

    return aggregate;
}


/**
 * Solve inclusive-scan problem
 */
template <
    typename        InputIterator,
    typename        T,
    typename        ScanOp>
T Solve(
    InputIterator   h_in,
    T               *h_reference,
    int             num_items,
    ScanOp          scan_op,
    NullType)
{
    T inclusive;
    T aggregate;
    for (int i = 0; i < num_items; ++i)
    {
        if (i == 0)
        {
            inclusive = h_in[0];
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
 * Test DeviceScan for a given problem input
 */
template <
    bool                CDP,
    typename            DeviceInputIterator,
    typename            T,
    typename            ScanOp,
    typename            IdentityT>
void Test(
    DeviceInputIterator d_in,
    T                   *h_reference,
    int                 num_items,
    ScanOp              scan_op,
    IdentityT           identity,
    char*               type_string)
{
    // Allocate device output array
    T *d_out = NULL;
    CubDebugExit(g_allocator.DeviceAllocate((void**)&d_out,         sizeof(T) * num_items));

    // Allocate CDP device arrays
    size_t          *d_temp_storage_bytes = NULL;
    cudaError_t     *d_cdp_error = NULL;
    CubDebugExit(g_allocator.DeviceAllocate((void**)&d_temp_storage_bytes,  sizeof(size_t) * 1));
    CubDebugExit(g_allocator.DeviceAllocate((void**)&d_cdp_error,   sizeof(cudaError_t) * 1));

    // Allocate temporary storage
    void            *d_temp_storage = NULL;
    size_t          temp_storage_bytes = 0;
    CubDebugExit(Dispatch(Int2Type<CDP>(), 1, d_temp_storage_bytes, d_cdp_error, d_temp_storage, temp_storage_bytes, d_in, d_out, scan_op, identity, num_items, 0, true));
    CubDebugExit(g_allocator.DeviceAllocate(&d_temp_storage, temp_storage_bytes));

    // Clear device output array
    CubDebugExit(cudaMemset(d_out, 0, sizeof(T) * num_items));

    // Run warmup/correctness iteration
    CubDebugExit(Dispatch(Int2Type<CDP>(), 1, d_temp_storage_bytes, d_cdp_error, d_temp_storage, temp_storage_bytes, d_in, d_out, scan_op, identity, num_items, 0, true));

    // Check for correctness (and display results, if specified)
    int compare = CompareDeviceResults(h_reference, d_out, num_items, true, g_verbose);
    printf("\t%s", compare ? "FAIL" : "PASS");

    // Flush any stdout/stderr
    fflush(stdout);
    fflush(stderr);

    // Performance
    GpuTimer gpu_timer;
    gpu_timer.Start();
    CubDebugExit(Dispatch(Int2Type<CDP>(), g_timing_iterations, d_temp_storage_bytes, d_cdp_error, d_temp_storage, temp_storage_bytes, d_in, d_out, scan_op, identity, num_items, 0, false));
    gpu_timer.Stop();
    float elapsed_millis = gpu_timer.ElapsedMillis();

    // Display performance
    if (g_timing_iterations > 0)
    {
        float avg_millis = elapsed_millis / g_timing_iterations;
        float grate = float(num_items) / avg_millis / 1000.0 / 1000.0;
        float gbandwidth = grate * sizeof(T) * 2;
        printf(", %.3f avg ms, %.3f billion items/s, %.3f logical GB/s", avg_millis, grate, gbandwidth);
    }

    printf("\n\n");

    // Cleanup
    if (d_out) CubDebugExit(g_allocator.DeviceFree(d_out));
    if (d_temp_storage_bytes) CubDebugExit(g_allocator.DeviceFree(d_temp_storage_bytes));
    if (d_cdp_error) CubDebugExit(g_allocator.DeviceFree(d_cdp_error));
    if (d_temp_storage) CubDebugExit(g_allocator.DeviceFree(d_temp_storage));

    // Correctness asserts
    AssertEquals(0, compare);
}


/**
 * Test DeviceScan on pointer type
 */
template <
    bool            CDP,
    typename        T,
    typename        ScanOp,
    typename        IdentityT>
void TestPointer(
    int             num_items,
    GenMode         gen_mode,
    ScanOp          scan_op,
    IdentityT       identity,
    char*           type_string)
{
    printf("\nPointer %s %s cub::DeviceScan::%s %d items, %s %d-byte elements, gen-mode %s\n",
        (CDP) ? "CDP device invoked" : "Host-invoked",
        (Equals<IdentityT, NullType>::VALUE) ? "Inclusive" : "Exclusive",
        (Equals<ScanOp, Sum>::VALUE) ? "Sum" : "Scan",
        num_items,
        type_string,
        (int) sizeof(T),
        (gen_mode == RANDOM) ? "RANDOM" : (gen_mode == SEQ_INC) ? "SEQUENTIAL" : "HOMOGENOUS");
    fflush(stdout);

    // Allocate host arrays
    T*  h_in = new T[num_items];
    T*  h_reference = new T[num_items];

    // Initialize problem and solution
    Initialize(gen_mode, h_in, num_items);
    Solve(h_in, h_reference, num_items, scan_op, identity);

    // Allocate problem device arrays
    T *d_in = NULL;
    CubDebugExit(g_allocator.DeviceAllocate((void**)&d_in,          sizeof(T) * num_items));

    // Initialize device input
    CubDebugExit(cudaMemcpy(d_in, h_in, sizeof(T) * num_items, cudaMemcpyHostToDevice));

    // Run Test
    Test<CDP>(d_in, h_reference, num_items, scan_op, identity, type_string);

    // Cleanup
    if (h_in) delete[] h_in;
    if (h_reference) delete[] h_reference;
    if (d_in) CubDebugExit(g_allocator.DeviceFree(d_in));
}


/**
 * Test DeviceScan on iterator type
 */
template <
    bool            CDP,
    typename        T,
    typename        ScanOp,
    typename        IdentityT>
void TestIterator(
    int             num_items,
    ScanOp          scan_op,
    IdentityT       identity,
    char*           type_string)
{
    printf("\nIterator %s %s cub::DeviceScan::%s %d items, %s %d-byte elements\n",
        (CDP) ? "CDP device invoked" : "Host-invoked",
        (Equals<IdentityT, NullType>::VALUE) ? "Inclusive" : "Exclusive",
        (Equals<ScanOp, Sum>::VALUE) ? "Sum" : "Scan",
        num_items,
        type_string,
        (int) sizeof(T));
    fflush(stdout);

    // Use a constant iterator as the input
    T val = T();
    ConstantInputIterator<T, int> h_in(val);

    // Allocate host arrays
    T*  h_reference = new T[num_items];

    // Initialize problem and solution
    Solve(h_in, h_reference, num_items, scan_op, identity);

    // Run Test
    Test<CDP>(h_in, h_reference, num_items, scan_op, identity, type_string);

    // Cleanup
    if (h_reference) delete[] h_reference;
}


/**
 * Test different gen modes
 */
template <
    int             CDP,
    typename        T,
    typename        ScanOp,
    typename        Identity>
void Test(
    int             num_items,
    ScanOp          scan_op,
    Identity        identity,
    char*           type_string)
{
    TestPointer<CDP, T>(num_items, UNIFORM, scan_op, identity, type_string);
    TestPointer<CDP, T>(num_items, RANDOM, scan_op, identity, type_string);

    TestIterator<CDP, T>(num_items, scan_op, identity, type_string);
}


/**
 * Test different dispatch
 */
template <
    typename        T,
    typename        ScanOp,
    typename        IdentityT>
void Test(
    int             num_items,
    ScanOp          scan_op,
    IdentityT       identity,
    char*           type_string)
{
    Test<false, T>(num_items, scan_op, identity, type_string);
#ifdef CUB_CDP
    Test<true, T>(num_items, scan_op, identity, type_string);
#endif
}




/**
 * Test inclusive/exclusive
 */
template <
    typename        T,
    typename        ScanOp>
void Test(
    int             num_items,
    ScanOp          scan_op,
    char*           type_string)
{
    Test<T>(num_items, scan_op, T(), type_string);          // exclusive
    Test<T>(num_items, scan_op, NullType(), type_string);   // inclusive
}


/**
 * Test different operators
 */
template <typename T>
void TestOp(
    int             num_items,
    char*           type_string)
{
    Test<T>(num_items, Sum(), type_string);
    Test<T>(num_items, Max(), type_string);
}


/**
 * Test different input sizes
 */
template <typename T>
void Test(
    int             num_items,
    char*           type_string)
{
    if (num_items < 0)
    {
        TestOp<T>(1,        type_string);
        TestOp<T>(100,      type_string);
        TestOp<T>(10000,    type_string);
        TestOp<T>(1000000,  type_string);
    }
    else
    {
        TestOp<T>(num_items, type_string);
    }
}



//---------------------------------------------------------------------
// Main
//---------------------------------------------------------------------

/**
 * Main
 */
int main(int argc, char** argv)
{
    int num_items = -1;

    // Initialize command line
    CommandLineArgs args(argc, argv);
    g_verbose = args.CheckCmdLineFlag("v");
    bool quick = args.CheckCmdLineFlag("quick");
    args.GetCmdLineArgument("n", num_items);
    args.GetCmdLineArgument("i", g_timing_iterations);
    args.GetCmdLineArgument("repeat", g_repeat);

    // Print usage
    if (args.CheckCmdLineFlag("help"))
    {
        printf("%s "
            "[--n=<input items> "
            "[--i=<timing iterations> "
            "[--device=<device-id>] "
            "[--repeat=<times to repeat tests>]"
            "[--quick]"
            "[--v] "
            "[--cdp]"
            "\n", argv[0]);
        exit(0);
    }

    // Initialize device
    CubDebugExit(args.DeviceInit());
    printf("\n");

    if (quick)
    {
        // Quick test
        if (num_items < 0) num_items = 32000000;

        TestPointer<false, char>(        num_items * 4, UNIFORM, Sum(), char(0), CUB_TYPE_STRING(char));
        TestPointer<false, short>(       num_items * 2, UNIFORM, Sum(), short(0), CUB_TYPE_STRING(short));
        TestPointer<false, int>(         num_items    , UNIFORM, Sum(), (int) (0), CUB_TYPE_STRING(int));
        TestPointer<false, long long>(   num_items / 2, UNIFORM, Sum(), (long long) (0), CUB_TYPE_STRING(long long));
        TestPointer<false, TestFoo>(     num_items / 4, UNIFORM, Sum(), TestFoo(), CUB_TYPE_STRING(TestFoo));
    }
    else
    {
        // Repeat test sequence
        for (int i = 0; i <= g_repeat; ++i)
        {
            // Test different input types
            Test<unsigned char>(num_items, CUB_TYPE_STRING(unsigned char));
            Test<unsigned short>(num_items, CUB_TYPE_STRING(unsigned short));
            Test<unsigned int>(num_items, CUB_TYPE_STRING(unsigned int));
            Test<unsigned long long>(num_items, CUB_TYPE_STRING(unsigned long long));

            Test<uchar2>(num_items, CUB_TYPE_STRING(uchar2));
            Test<uint2>(num_items, CUB_TYPE_STRING(uint2));
            Test<ulonglong2>(num_items, CUB_TYPE_STRING(ulonglong2));
            Test<ulonglong4>(num_items, CUB_TYPE_STRING(ulonglong4));

            Test<TestFoo>(num_items, CUB_TYPE_STRING(TestFoo));
            Test<TestBar>(num_items, CUB_TYPE_STRING(TestBar));
        }
    }

    return 0;
}



