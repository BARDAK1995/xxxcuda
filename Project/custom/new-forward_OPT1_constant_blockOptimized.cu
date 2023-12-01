#include <cmath>
#include <iostream>
#include "gpu-new-forward.h"
__constant__ float KERNEL_DEVICE_CST[3136];

__global__ void conv_forward_kernel_basic(float *output, const float *input, const float *mask, const int B, const int M, const int C, const int H, const int W, const int K,const int S)
{
    /*
    Function paramter definitions:
    output - output
    input - input
    mask - convolution kernel
    B - batch_size (number of images in x)
    M - number of output feature maps
    C - number of input feature maps
    H - input height dimension
    W - input width dimension
    K - kernel height and width (K x K)
    S - stride step length
    */
    const int H_out = (H - K)/S + 1;
    const int W_out = (W - K)/S + 1;
    #define out_4d(i3, i2, i1, i0) output[(i3) * (M * H_out * W_out) + (i2) * (H_out * W_out) + (i1) * (W_out) + i0]    // out_4d(b, m, h, w)
    #define in_4d_global(i3, i2, i1, i0) input[(i3) * (C * H * W) + (i2) * (H * W) + (i1) * (W) + i0]                          // in_4d(b, c, cell_height, cell_width)
    #define mask_4d(i3, i2, i1, i0) mask[(i3) * (C * K * K) + (i2) * (K * K) + (i1) * (K) + i0]                         // mask_4d(m, c, mask_heightindex, mask_widthindex)
    // Insert your GPU convolution kernel code here
    const int tile_width = blockDim.x;
    const int tile_height = blockDim.y;
    const int W_grid_blocks = (W_out - 1) / tile_width + 1;  //tiles in outputWidth
    const int m_feature = blockIdx.x;
    const int b = blockIdx.z;
    const int output_h = (blockIdx.y / W_grid_blocks) * tile_height + threadIdx.y;
    const int output_w = (blockIdx.y % W_grid_blocks) * tile_width + threadIdx.x;
    // starting index for current Block
    const int input_h_start = output_h * S; 
    const int input_w_start = output_w * S;
    int input_x;// input-x index
    int input_y;// input-y index
    float acc = 0.0f;
    if((output_h < H_out) && (output_w < W_out)){
        for(int c = 0; c < C; ++c){   // sum over all input channels
            for(int j = 0; j < K; ++j){   // KxK filter (height)
                input_y = input_h_start + j;
                for(int i = 0; i < K; ++i){   // KxK filter (width)
                    input_x = input_w_start + i;
                    acc += in_4d_global(b, c, input_y, input_x) * mask_4d(m_feature, c, j, i); 
                }
            }
        }
        out_4d(b, m_feature, output_h, output_w) = acc;
    }
    #undef out_4d
    #undef in_4d_global
    #undef mask_4d
}

__global__ void conv_forward_kernel_ConstantMem(float *output, const float *input, const float *mask, const int B, const int M, const int C, const int H, const int W, const int K,const int S)
{
    /*
    Function paramter definitions:
    output - output
    input - input
    KERNEL_DEVICE_CST - convolution kernel mask in constant MEM
    B - batch_size (number of images in x)
    M - number of output feature maps
    C - number of input feature maps
    H - input height dimension
    W - input width dimension
    K - kernel height and width (K x K)
    S - stride step length
    */
    const int H_out = (H - K)/S + 1;
    const int W_out = (W - K)/S + 1;
    #define out_4d(i3, i2, i1, i0) output[(i3) * (M * H_out * W_out) + (i2) * (H_out * W_out) + (i1) * (W_out) + i0]    // out_4d(b, m, h, w)
    #define in_4d_global(i3, i2, i1, i0) input[(i3) * (C * H * W) + (i2) * (H * W) + (i1) * (W) + i0]                          // in_4d(b, c, cell_height, cell_width)
    #define mask_4d(i3, i2, i1, i0) KERNEL_DEVICE_CST[(i3) * (C * K * K) + (i2) * (K * K) + (i1) * (K) + i0]                         // mask_4d(m, c, mask_heightindex, mask_widthindex)
    // Insert your GPU convolution kernel code here
    const int tile_width = blockDim.x;
    const int tile_height = blockDim.y;
    const int W_grid_blocks = (W_out - 1) / tile_width + 1;  //tiles in outputWidth
    const int m_feature = blockIdx.x;
    const int b = blockIdx.z;
    const int output_h = (blockIdx.y / W_grid_blocks) * tile_height + threadIdx.y;
    const int output_w = (blockIdx.y % W_grid_blocks) * tile_width + threadIdx.x;
    // starting index for current Block
    const int input_h_start = output_h * S; 
    const int input_w_start = output_w * S;
    int input_x;// input-x index
    int input_y;// input-y index
    float acc = 0.0f;
    if((output_h < H_out) && (output_w < W_out)){
        for(int c = 0; c < C; ++c){   // sum over all input channels
            for(int j = 0; j < K; ++j){   // KxK filter (height)
                input_y = input_h_start + j;
                for(int i = 0; i < K; ++i){   // KxK filter (width)
                    input_x = input_w_start + i;
                    acc += in_4d_global(b, c, input_y, input_x) * mask_4d(m_feature, c, j, i); 
                }
            }
        }
        out_4d(b, m_feature, output_h, output_w) = acc;
    }
    #undef out_4d
    #undef in_4d_global
    #undef mask_4d
}

__host__ void GPUInterface::conv_forward_gpu_prolog(const float *host_output, const float *host_input, const float *host_mask, float **device_output_ptr, float **device_input_ptr, float **device_mask_ptr, const int B, const int M, const int C, const int H, const int W, const int K, const int S)
{
    // Allocate memory and copy over the relevant data structures to the GPU
    const int memSizeInput = (B * C * H * W) * sizeof(float);
    const int memSizeMask = (M * C * K * K) * sizeof(float);
    const int outputHeight = (H - K)/S + 1;
    const int outputWidth = (W - K)/S + 1;
    const int memSizeOutput = (B * M * outputHeight * outputWidth) * sizeof(float);
    // We pass double pointers for you to initialize the relevant device pointers,
    //  which are passed to the other two functions.
    cudaMalloc((void **)device_input_ptr, memSizeInput);
    cudaMalloc((void **)device_mask_ptr, memSizeMask);
    cudaMalloc((void **)device_output_ptr, memSizeOutput);
    cudaMemcpy(*device_input_ptr, host_input, memSizeInput, cudaMemcpyHostToDevice);
    cudaMemcpy(*device_mask_ptr, host_mask, memSizeMask, cudaMemcpyHostToDevice);
    cudaMemcpyToSymbol(KERNEL_DEVICE_CST, host_mask, memSizeMask);
}


__host__ void GPUInterface::conv_forward_gpu(float *device_output, const float *device_input, const float *device_mask, const int B, const int M, const int C, const int H, const int W, const int K, const int S)
{
    // Set the kernel dimensions and call the kernel
    const int outputHeight = (H - K)/S + 1;
    const int outputWidth = (W - K)/S + 1;
    int TILE_WIDTH = 8;
    int TILE_HEIGHT = 48;
    bool kernelFlag = false;
    //first layer
    if(outputWidth==80){
        TILE_WIDTH = 16;
        TILE_HEIGHT = 16;
        kernelFlag = true;
    }
    //second layer
    else if(outputWidth==34){
        TILE_WIDTH = 8;
        TILE_HEIGHT = 48;
        kernelFlag = true;
    }
    int H_grid_blocks = (outputHeight - 1) / TILE_HEIGHT + 1; //tiles in outputHeight
    int W_grid_blocks = (outputWidth - 1) / TILE_WIDTH + 1;  //tiles in outputWidth
    int nTiles = H_grid_blocks * W_grid_blocks; // total tiles
    dim3 dimBlock(TILE_WIDTH, TILE_HEIGHT, 1);
    dim3 dimGrid(M, nTiles, B); // Ensuring all elements are covered
    conv_forward_kernel_ConstantMem<<<dimGrid, dimBlock>>>(device_output, device_input, device_mask, B, M, C, H, W, K, S);
}

__host__ void GPUInterface::conv_forward_gpu_epilog(float *host_output, float *device_output, float *device_input, float *device_mask, const int B, const int M, const int C, const int H, const int W, const int K, const int S)
{
    // Copy the output back to host
    const int outputHeight = (H - K)/S + 1;
    const int outputWidth = (W - K)/S + 1;
    const int memSizeOutput = (B * M * outputHeight * outputWidth) * sizeof(float);
    cudaMemcpy(host_output, device_output, memSizeOutput,cudaMemcpyDeviceToHost);
    cudaFree(device_input);
    cudaFree(device_mask);
    cudaFree(device_output);
    // Free device memory
}


__host__ void GPUInterface::get_device_properties()
{
    int deviceCount;
    cudaGetDeviceCount(&deviceCount);

    for(int dev = 0; dev < deviceCount; dev++)
    {
        cudaDeviceProp deviceProp;
        cudaGetDeviceProperties(&deviceProp, dev);

        std::cout<<"Device "<<dev<<" name: "<<deviceProp.name<<std::endl;
        std::cout<<"Computational capabilities: "<<deviceProp.major<<"."<<deviceProp.minor<<std::endl;
        std::cout<<"Max Global memory size: "<<deviceProp.totalGlobalMem<<std::endl;
        std::cout<<"Max Constant memory size: "<<deviceProp.totalConstMem<<std::endl;
        std::cout<<"Max Shared memory size per block: "<<deviceProp.sharedMemPerBlock<<std::endl;
        std::cout<<"Max threads per block: "<<deviceProp.maxThreadsPerBlock<<std::endl;
        std::cout<<"Max block dimensions: "<<deviceProp.maxThreadsDim[0]<<" x, "<<deviceProp.maxThreadsDim[1]<<" y, "<<deviceProp.maxThreadsDim[2]<<" z"<<std::endl;
        std::cout<<"Max grid dimensions: "<<deviceProp.maxGridSize[0]<<" x, "<<deviceProp.maxGridSize[1]<<" y, "<<deviceProp.maxGridSize[2]<<" z"<<std::endl;
        std::cout<<"Warp Size: "<<deviceProp.warpSize<<std::endl;
    }
}