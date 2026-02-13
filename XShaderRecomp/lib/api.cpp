#include "include/xshader_api.h"
#include "vertex_shader.h"

const uint8_t* XSR_CreateRecompiledShader(size_t handle, uint32_t* pXboxFunction, DWORD* pXboxFunctionSize, size_t* outSize, bool exportHLSL)
{
	return CreateRecompiledShader(handle, pXboxFunction, pXboxFunctionSize, outSize, exportHLSL);
}


HostVertexDeclaration* XSR_HostGetVertexDeclaration(size_t handle, const bool isFixedFunction)
{
	return HostGetVertexDeclaration(handle, isFixedFunction);
}