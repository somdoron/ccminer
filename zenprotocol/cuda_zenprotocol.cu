/*
 * Zen Protocol SHA3 CUDA implementation.
 */

#include <stdint.h>
#include <stdio.h>
#include <memory.h>

#include <cuda_helper.h>
#include <miner.h>

__constant__ uint32_t pTarget[8];
__constant__ static uint8_t c_PaddedMessage[136]; // padded message (100 bytes + padding)



static __device__ uint32_t HIWORD(const uint64_t x)
{
    uint32_t result;
    asm(
        "{\n\t"
        ".reg .u32 xl; \n\t"
        "mov.b64 {xl,%0},%1; \n\t"
        "}" : "=r"(result) : "l"(x)
    );
    return result;
}

static __device__ uint32_t LOWORD(const uint64_t x)
{
    uint32_t result;
    asm(
        "{\n\t"
        ".reg .u32 xh; \n\t"
        "mov.b64 {%0,xh},%1; \n\t"
        "}" : "=r"(result) : "l"(x)
    );
    return result;
}

#define ROTL_1(d0, d1, v0, v1)      ROTL_SMALL(d0, d1, v0, v1,  1)
#define ROTL_2(d0, d1, v0, v1)      ROTL_SMALL(d0, d1, v0, v1,  2)
#define ROTL_3(d0, d1, v0, v1)      ROTL_SMALL(d0, d1, v0, v1,  3)
#define ROTL_6(d0, d1, v0, v1)      ROTL_SMALL(d0, d1, v0, v1,  6)
#define ROTL_8(d0, d1, v0, v1)      ROTL_SMALL(d0, d1, v0, v1,  8)
#define ROTL_10(d0, d1, v0, v1)     ROTL_SMALL(d0, d1, v0, v1, 10)
#define ROTL_14(d0, d1, v0, v1)     ROTL_SMALL(d0, d1, v0, v1, 14)
#define ROTL_15(d0, d1, v0, v1)     ROTL_SMALL(d0, d1, v0, v1, 15)
#define ROTL_18(d0, d1, v0, v1)     ROTL_SMALL(d0, d1, v0, v1, 18)
#define ROTL_20(d0, d1, v0, v1)     ROTL_SMALL(d0, d1, v0, v1, 20)
#define ROTL_21(d0, d1, v0, v1)     ROTL_SMALL(d0, d1, v0, v1, 21)
#define ROTL_25(d0, d1, v0, v1)     ROTL_SMALL(d0, d1, v0, v1, 25)
#define ROTL_27(d0, d1, v0, v1)     ROTL_SMALL(d0, d1, v0, v1, 27)
#define ROTL_28(d0, d1, v0, v1)     ROTL_SMALL(d0, d1, v0, v1, 28)
#define ROTL_32(d0, d1, v0, v1)     (d0 = v1; d1 = v0; )
#define ROTL_36(d0, d1, v0, v1)     ROTL_BIG(d0, d1, v0, v1, 36)
#define ROTL_39(d0, d1, v0, v1)     ROTL_BIG(d0, d1, v0, v1, 39)
#define ROTL_41(d0, d1, v0, v1)     ROTL_BIG(d0, d1, v0, v1, 41)
#define ROTL_43(d0, d1, v0, v1)     ROTL_BIG(d0, d1, v0, v1, 43)
#define ROTL_44(d0, d1, v0, v1)     ROTL_BIG(d0, d1, v0, v1, 44)
#define ROTL_45(d0, d1, v0, v1)     ROTL_BIG(d0, d1, v0, v1, 45)
#define ROTL_55(d0, d1, v0, v1)     ROTL_BIG(d0, d1, v0, v1, 55)
#define ROTL_56(d0, d1, v0, v1)     ROTL_BIG(d0, d1, v0, v1, 56)
#define ROTL_61(d0, d1, v0, v1)     ROTL_BIG(d0, d1, v0, v1, 61)
#define ROTL_62(d0, d1, v0, v1)     ROTL_BIG(d0, d1, v0, v1, 62)

#define ROTLI_1(d1, d2, v1, v2)    ROTLI_odd1(d1, d2, v1, v2)
#define ROTLI_2(d1, d2, v1, v2)    ROTLI_even(d1, d2, v1, v2,  1)
#define ROTLI_3(d1, d2, v1, v2)    ROTLI_odd( d1, d2, v1, v2,  2)
#define ROTLI_6(d1, d2, v1, v2)    ROTLI_even(d1, d2, v1, v2,  3)
#define ROTLI_8(d1, d2, v1, v2)    ROTLI_even(d1, d2, v1, v2,  4)
#define ROTLI_10(d1, d2, v1, v2)   ROTLI_even(d1, d2, v1, v2,  5)
#define ROTLI_14(d1, d2, v1, v2)   ROTLI_even(d1, d2, v1, v2,  7)
#define ROTLI_15(d1, d2, v1, v2)   ROTLI_odd( d1, d2, v1, v2,  8)
#define ROTLI_18(d1, d2, v1, v2)   ROTLI_even(d1, d2, v1, v2,  9)
#define ROTLI_20(d1, d2, v1, v2)   ROTLI_even(d1, d2, v1, v2, 10)
#define ROTLI_21(d1, d2, v1, v2)   ROTLI_odd( d1, d2, v1, v2, 11)
#define ROTLI_25(d1, d2, v1, v2)   ROTLI_odd( d1, d2, v1, v2, 13)
#define ROTLI_27(d1, d2, v1, v2)   ROTLI_odd( d1, d2, v1, v2, 14)
#define ROTLI_28(d1, d2, v1, v2)   ROTLI_even(d1, d2, v1, v2, 14)
#define ROTLI_36(d1, d2, v1, v2)   ROTLI_even(d1, d2, v1, v2, 18)
#define ROTLI_39(d1, d2, v1, v2)   ROTLI_odd( d1, d2, v1, v2, 20)
#define ROTLI_41(d1, d2, v1, v2)   ROTLI_odd( d1, d2, v1, v2, 21)
#define ROTLI_43(d1, d2, v1, v2)   ROTLI_odd( d1, d2, v1, v2, 22)
#define ROTLI_44(d1, d2, v1, v2)   ROTLI_even(d1, d2, v1, v2, 22)
#define ROTLI_45(d1, d2, v1, v2)   ROTLI_odd( d1, d2, v1, v2, 23)
#define ROTLI_55(d1, d2, v1, v2)   ROTLI_odd( d1, d2, v1, v2, 28)
#define ROTLI_56(d1, d2, v1, v2)   ROTLI_even(d1, d2, v1, v2, 28)
#define ROTLI_61(d1, d2, v1, v2)   ROTLI_odd( d1, d2, v1, v2, 31)
#define ROTLI_62(d1, d2, v1, v2)   ROTLI_even(d1, d2, v1, v2, 31)

#define ROTs(a, b, n) ROTL_##n(s[a], s[a+1], s[b], s[b+1])
#define ROTIs(a, b, n) ROTLI_##n(s[a], s[a+1], s[b], s[b+1])

static __device__ __forceinline__ void ROTL_SMALL( uint32_t &d0, uint32_t &d1, uint32_t v0, uint32_t v1, const uint32_t offset )
{
#if __CUDA_ARCH__ >= 320
    asm(
        "shf.l.wrap.b32 %0, %2, %3, %4;\n\t"
        "shf.l.wrap.b32 %1, %3, %2, %4;\n\t"
        : "=r"(d0), "=r"(d1) 
        : "r"(v1), "r"(v0), "r"(offset));
#else
    d0 = (v0 << offset) | (v1 >> (32-offset));
    d1 = (v1 << offset) | (v0 >> (32-offset));
#endif
}

static __device__ __forceinline__ void ROTL_BIG( uint32_t &d0, uint32_t &d1, uint32_t v0, uint32_t v1, const uint32_t offset )
{
#if __CUDA_ARCH__ >= 320
    asm(
        "shf.l.wrap.b32 %0, %3, %2, %4;\n\t"
        "shf.l.wrap.b32 %1, %2, %3, %4;\n\t"
        : "=r"(d0), "=r"(d1) 
        : "r"(v1), "r"(v0), "r"(offset-32));
#else
    d0 = (v1 << (offset-32)) | (v0 >> (64-offset));
    d1 = (v0 << (offset-32)) | (v1 >> (64-offset));
#endif
}

__constant__ uint32_t d_RC[48];
static const uint32_t h_RC[48] = {
    0x00000001, 0x00000000, 0x00008082, 0x00000000,
    0x0000808a, 0x80000000, 0x80008000, 0x80000000,
    0x0000808b, 0x00000000, 0x80000001, 0x00000000,
    0x80008081, 0x80000000, 0x00008009, 0x80000000,
    0x0000008a, 0x00000000, 0x00000088, 0x00000000,
    0x80008009, 0x00000000, 0x8000000a, 0x00000000,
    0x8000808b, 0x00000000, 0x0000008b, 0x80000000,
    0x00008089, 0x80000000, 0x00008003, 0x80000000,
    0x00008002, 0x80000000, 0x00000080, 0x80000000,
    0x0000800a, 0x00000000, 0x8000000a, 0x80000000,
    0x80008081, 0x80000000, 0x00008080, 0x80000000,
    0x80000001, 0x00000000, 0x80008008, 0x80000000
};

static __device__ void keccak_block(uint32_t *s) 
{
    uint32_t t[10], u[10], v[2];

#pragma unroll 4
    for (int i = 0; i < 48; i += 2) {

        t[4] = s[4] ^ s[14] ^ s[24] ^ s[34] ^ s[44];
        t[5] = s[5] ^ s[15] ^ s[25] ^ s[35] ^ s[45];
        t[2] = s[2] ^ s[12] ^ s[22] ^ s[32] ^ s[42];
        t[3] = s[3] ^ s[13] ^ s[23] ^ s[33] ^ s[43];
        t[6] = s[6] ^ s[16] ^ s[26] ^ s[36] ^ s[46];
        t[7] = s[7] ^ s[17] ^ s[27] ^ s[37] ^ s[47];
        t[8] = s[8] ^ s[18] ^ s[28] ^ s[38] ^ s[48];
        t[9] = s[9] ^ s[19] ^ s[29] ^ s[39] ^ s[49];
        t[0] = s[0] ^ s[10] ^ s[20] ^ s[30] ^ s[40];
        t[1] = s[1] ^ s[11] ^ s[21] ^ s[31] ^ s[41];
    
        ROTL_1(u[2], u[3], t[4], t[5]);
        ROTL_1(u[0], u[1], t[2], t[3]);
        ROTL_1(u[4], u[5], t[6], t[7]);
        ROTL_1(u[6], u[7], t[8], t[9]);
        ROTL_1(u[8], u[9], t[0], t[1]);
        
        u[2] ^= t[0]; u[3] ^= t[1];
        u[0] ^= t[8]; u[1] ^= t[9];
        u[4] ^= t[2]; u[5] ^= t[3];
        u[6] ^= t[4]; u[7] ^= t[5];
        u[8] ^= t[6]; u[9] ^= t[7];

        s[2] ^= u[2]; s[3] ^= u[3];

        s[0] ^= u[0]; s[10] ^= u[0]; s[20] ^= u[0]; s[30] ^= u[0]; s[40] ^= u[0];
        s[1] ^= u[1]; s[11] ^= u[1]; s[21] ^= u[1]; s[31] ^= u[1]; s[41] ^= u[1];
        s[12] ^= u[2]; s[22] ^= u[2]; s[32] ^= u[2]; s[42] ^= u[2];
        s[13] ^= u[3]; s[23] ^= u[3]; s[33] ^= u[3]; s[43] ^= u[3];
        s[4] ^= u[4]; s[14] ^= u[4]; s[24] ^= u[4]; s[34] ^= u[4]; s[44] ^= u[4];
        s[5] ^= u[5]; s[15] ^= u[5]; s[25] ^= u[5]; s[35] ^= u[5]; s[45] ^= u[5];
        s[6] ^= u[6]; s[16] ^= u[6]; s[26] ^= u[6]; s[36] ^= u[6]; s[46] ^= u[6];
        s[7] ^= u[7]; s[17] ^= u[7]; s[27] ^= u[7]; s[37] ^= u[7]; s[47] ^= u[7];
        s[8] ^= u[8]; s[18] ^= u[8]; s[28] ^= u[8]; s[38] ^= u[8]; s[48] ^= u[8];
        s[9] ^= u[9]; s[19] ^= u[9]; s[29] ^= u[9]; s[39] ^= u[9]; s[49] ^= u[9];

        v[0] = s[2]; v[1] = s[3];
        ROTs( 2, 12, 44);
        ROTs(12, 18, 20);
        ROTs(18, 44, 61);
        ROTs(44, 28, 39);
        ROTs(28, 40, 18);
        ROTs(40,  4, 62);
        ROTs( 4, 24, 43);
        ROTs(24, 26, 25);
        ROTs(26, 38,  8);
        ROTs(38, 46, 56);
        ROTs(46, 30, 41);
        ROTs(30,  8, 27);
        ROTs( 8, 48, 14);
        ROTs(48, 42,  2);
        ROTs(42, 16, 55);
        ROTs(16, 32, 45);
        ROTs(32, 10, 36);
        ROTs(10,  6, 28);
        ROTs( 6, 36, 21);
        ROTs(36, 34, 15);
        ROTs(34, 22, 10);
        ROTs(22, 14,  6);
        ROTs(14, 20,  3);
        ROTL_1(s[20], s[21], v[0], v[1]);

        v[0] = s[ 0]; v[1] = s[ 2]; s[ 0] ^= (~v[1]) & s[ 4]; s[ 2] ^= (~s[ 4]) & s[ 6]; s[ 4] ^= (~s[ 6]) & s[ 8]; s[ 6] ^= (~s[ 8]) & v[0]; s[ 8] ^= (~v[0]) & v[1];
        v[0] = s[ 1]; v[1] = s[ 3]; s[ 1] ^= (~v[1]) & s[ 5]; s[ 3] ^= (~s[ 5]) & s[ 7]; s[ 5] ^= (~s[ 7]) & s[ 9]; s[ 7] ^= (~s[ 9]) & v[0]; s[ 9] ^= (~v[0]) & v[1];
        v[0] = s[10]; v[1] = s[12]; s[10] ^= (~v[1]) & s[14]; s[12] ^= (~s[14]) & s[16]; s[14] ^= (~s[16]) & s[18]; s[16] ^= (~s[18]) & v[0]; s[18] ^= (~v[0]) & v[1];
        v[0] = s[11]; v[1] = s[13]; s[11] ^= (~v[1]) & s[15]; s[13] ^= (~s[15]) & s[17]; s[15] ^= (~s[17]) & s[19]; s[17] ^= (~s[19]) & v[0]; s[19] ^= (~v[0]) & v[1];
        v[0] = s[20]; v[1] = s[22]; s[20] ^= (~v[1]) & s[24]; s[22] ^= (~s[24]) & s[26]; s[24] ^= (~s[26]) & s[28]; s[26] ^= (~s[28]) & v[0]; s[28] ^= (~v[0]) & v[1];
        v[0] = s[21]; v[1] = s[23]; s[21] ^= (~v[1]) & s[25]; s[23] ^= (~s[25]) & s[27]; s[25] ^= (~s[27]) & s[29]; s[27] ^= (~s[29]) & v[0]; s[29] ^= (~v[0]) & v[1];
        v[0] = s[30]; v[1] = s[32]; s[30] ^= (~v[1]) & s[34]; s[32] ^= (~s[34]) & s[36]; s[34] ^= (~s[36]) & s[38]; s[36] ^= (~s[38]) & v[0]; s[38] ^= (~v[0]) & v[1];
        v[0] = s[31]; v[1] = s[33]; s[31] ^= (~v[1]) & s[35]; s[33] ^= (~s[35]) & s[37]; s[35] ^= (~s[37]) & s[39]; s[37] ^= (~s[39]) & v[0]; s[39] ^= (~v[0]) & v[1];
        v[0] = s[40]; v[1] = s[42]; s[40] ^= (~v[1]) & s[44]; s[42] ^= (~s[44]) & s[46]; s[44] ^= (~s[46]) & s[48]; s[46] ^= (~s[48]) & v[0]; s[48] ^= (~v[0]) & v[1];
        v[0] = s[41]; v[1] = s[43]; s[41] ^= (~v[1]) & s[45]; s[43] ^= (~s[45]) & s[47]; s[45] ^= (~s[47]) & s[49]; s[47] ^= (~s[49]) & v[0]; s[49] ^= (~v[0]) & v[1];

        s[0] ^= d_RC[i];
        s[1] ^= d_RC[i+1];
    }
}

__global__ void zenprotocol_gpu_hash_100(uint32_t threads, uint32_t startNonce, uint32_t *resultNonce)
{
    uint32_t thread = (blockDim.x * blockIdx.x + threadIdx.x);
    
    if (thread < threads)
    {
        uint32_t nonce =  startNonce + thread;
        uint64_t state[25];

#pragma unroll 17
        for (int i = 0; i < 17; ++i) {
          state[i] = (((uint64_t*)c_PaddedMessage)[i]);
        }
	((uint32_t*)state)[24] = nonce;
#if 0        
        printf("GPU INPUT 0\n");
        for (int i = 0; i < 17; ++i) {
          printf("%08x", cuda_swab32(((uint32_t*)state)[i]));
        }
        printf("\n");
#endif
        
#pragma unroll 8        
        for (int i = 17; i < 25; ++i) {
          state[i] = 0;
        }

        keccak_block((uint32_t*)state);

        uint32_t h0 = cuda_swab32(LOWORD(state[0]));
        uint32_t h1 = cuda_swab32(HIWORD(state[0]));

        if ((h0 < pTarget[0]) || (h0 == pTarget[0] && h1 <= pTarget[1])) {
          uint32_t tmp = atomicExch(&resultNonce[0], thread);
          if (tmp != UINT32_MAX) {
            resultNonce[1] = tmp;
          }

#if 0
          uint32_t pHash[8];
#pragma unroll 4
          for (int i = 0; i < 4; ++i) {
            pHash[2 * i] = cuda_swab32(LOWORD(state[i]));
            pHash[2 * i + 1] = cuda_swab32(HIWORD(state[i]));
          }
          printf("GPU 100 HASH:\n");
          for (int i = 0; i < 8; ++i) {
            printf("%08x", pHash[i]);
          }
          printf("\nGPU 100 Target:\n");
          for (int i = 0; i < 8; ++i) {
            printf("%08x", pTarget[i]);
          }
	  printf("\n");
#endif
         }

    }
}

__host__ void zenprotocol_setBlock_100(uint32_t *pdata)
{
	unsigned char PaddedMessage[136];
	memcpy(PaddedMessage, pdata, 100);
	memset(PaddedMessage + 100, 0, 36);
	PaddedMessage[100] = 0x06;
	PaddedMessage[135] = 0x80;

	CUDA_SAFE_CALL(cudaMemcpyToSymbol(c_PaddedMessage, PaddedMessage, 136*sizeof(uint8_t), 0, cudaMemcpyHostToDevice));
}

__host__ void zenprotocol_setTarget(const uint32_t *ptarget)
{
        CUDA_SAFE_CALL(cudaMemcpyToSymbol(pTarget, ptarget, 8 * sizeof(uint32_t), 0, cudaMemcpyHostToDevice));
}

__host__
void zenprotocol_init(int thr_id)
{
        CUDA_SAFE_CALL(cudaMemcpyToSymbol(d_RC, h_RC, sizeof(h_RC), 0, cudaMemcpyHostToDevice));
}

__host__
void zenprotocol_free(int thr_id)
{
}

__host__
void zenprotocol_cpu_hash(int thr_id, uint32_t threads, uint32_t startNonce, uint32_t *resultNonce)
{
	const uint32_t threadsperblock = 256;

	dim3 grid((threads + threadsperblock-1)/threadsperblock);
	dim3 block(threadsperblock);

        zenprotocol_gpu_hash_100 <<<grid, block>>> (threads, startNonce, resultNonce);
}

