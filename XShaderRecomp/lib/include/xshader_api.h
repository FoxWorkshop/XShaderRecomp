#pragma once

#include "vertex_declaration.h"

/**
* \brief Attempt to extract, decode, build and return a shader, return a valid pointer if the creation succeeded, otherwise return nullptr. 
* The caller is responsible for freeing the returned shader blob. 
* \param handle: The vertex shader handle, which can be either a vertex shader function handle or an FVF handle.
* \param pXboxFunction: Pointer to the Xbox shader function microcode. 
* \param pXboxFunctionSize: Size of the Xbox shader function microcode in bytes. 
* \param outSize: Output parameter that will receive the size of the returned shader blob in bytes.
* \param Vulkan: Specify if shader should be compiled with spirv features.
* \param exportHLSL: if true, the HLSL source code of the shader will be exported to the user data directory (e.g. %APPDATA%/XShaderRecomp/HLSL) for debugging purposes. 
*/
const uint8_t* XSR_CreateRecompiledShader(size_t handle, uint32_t* pXboxFunction, DWORD* pXboxFunctionSize, size_t* outSize, bool Vulkan, bool exportHLSL);

/**
* \brief Attempt to get vertex declaration information for the given vertex shader handle, return a valid pointer if the creation succeeded, otherwise return nullptr.
* \param handle: The vertex shader handle, which can be either a vertex shader function handle or an FVF handle. 
* \param isFixedFunction: Whether the fixed function pipeline is in use for this vertex shader. This is used to determine the resulting vertex declaration, since some titles use different declarations for the same attributes depending on if the fixed function pipeline is in use or not.
*/
HostVertexDeclaration* XSR_HostGetVertexDeclaration(size_t handle, const bool isFixedFunction);