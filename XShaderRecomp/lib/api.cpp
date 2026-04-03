#include "pch.h"
#include "include/xshader_api.h"
#include "vertex_shader.h"
#include "pixel_shader.h"

const uint8_t* XSR_CreateRecompiledVertexShader(size_t handle, uint32_t* pXboxFunction, DWORD* pXboxFunctionSize, size_t* outSize, bool Vulkan, bool exportHLSL)
{
	return CreateRecompiledShader(handle, pXboxFunction, pXboxFunctionSize, outSize, Vulkan, exportHLSL);
}

const uint8_t* XSR_CreateRecompiledPixelShader(void* psDef, size_t* outSize, pixelShader_GuestInfo* psGuestInfo, bool Vulkan, bool exportHLSL)
{
	return CreateRecompilePixelShader((X_D3DPIXELSHADERDEF*)psDef, outSize, psGuestInfo, Vulkan, exportHLSL);
}


HostVertexDeclaration* XSR_HostGetVertexDeclaration(size_t handle, const bool isFixedFunction)
{
	return HostGetVertexDeclaration(handle, isFixedFunction);
}