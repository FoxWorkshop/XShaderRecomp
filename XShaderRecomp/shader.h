#pragma once

#include "constant_table.h"

#include <atomic>
#include <string> // std::string
#include "dxc_compiler.h"

struct Float4Definition
{
    be<uint16_t> registerIndex;
    be<uint16_t> count;
    be<uint32_t> physicalOffset;
};

struct Int4Definition
{
    be<uint16_t> registerIndex;
    be<uint16_t> count;
    be<uint32_t> values[];
};

struct DefinitionTable
{
    be<uint32_t> field0;
    be<uint32_t> field4;
    be<uint32_t> field8;
    be<uint32_t> fieldC;
    be<uint32_t> size;
    be<uint32_t> definitions[]; // float4, int4 and bool separated by null terminators
};

struct Shader
{
    be<uint32_t> physicalOffset;
    be<uint32_t> size;
    be<uint32_t> field8;
    be<uint32_t> fieldC; // svPos register: (fieldC >> 8) & 0xFF
    be<uint32_t> field10;
    be<uint32_t> interpolatorInfo; // interpolator count: (interpolatorInfo >> 5) & 0x1F
};

enum class DeclUsage : uint32_t
{
    Position = 0,
    BlendWeight = 1,
    BlendIndices = 2,
    Normal = 3,
    PointSize = 4,
    TexCoord = 5,
    Tangent = 6,
    Binormal = 7,
    TessFactor = 8,
    PositionT = 9,
    Color = 10,
    Fog = 11,
    Depth = 12,
    Sample = 13
};

struct VertexElement
{
    uint32_t address : 12;
    DeclUsage usage : 4;
    uint32_t usageIndex : 4;
};

struct Interpolator
{
    uint32_t usageIndex : 4;
    DeclUsage usage : 4;
    uint32_t reg : 4;
    uint32_t : 20;
};

struct VertexShader : Shader
{
    be<uint32_t> field18;
    be<uint32_t> vertexElementCount;
    be<uint32_t> field20;
    be<uint32_t> vertexElementsAndInterpolators[]; // field18 + vertex elements + interpolators
};

enum PixelShaderOutputs : uint32_t
{
    PIXEL_SHADER_OUTPUT_COLOR0 = 0x1,
    PIXEL_SHADER_OUTPUT_COLOR1 = 0x2,
    PIXEL_SHADER_OUTPUT_COLOR2 = 0x4,
    PIXEL_SHADER_OUTPUT_COLOR3 = 0x8,
    PIXEL_SHADER_OUTPUT_DEPTH = 0x10
};

struct PixelShader : Shader
{
    be<uint32_t> field18;
    be<PixelShaderOutputs> outputs;
    be<uint32_t> interpolators[];
};

struct ShaderContainer
{
    be<uint32_t> flags;
    be<uint32_t> virtualSize;
    be<uint32_t> physicalSize;
    be<uint32_t> fieldC;
    be<uint32_t> constantTableOffset;
    be<uint32_t> definitionTableOffset;
    be<uint32_t> shaderOffset;
    be<uint32_t> field1C;
    be<uint32_t> field20;
};

enum VertexShaderType
{
    Default,
    Weights_Bones,
    Weights_Bones_normal_uv,
    TwoDimensional, //hud, menu, etc.
    VertexShaderTypeMax
};

typedef enum _X_D3DRESOURCETYPE
{
    X_D3DRTYPE_NONE = 0,
    X_D3DRTYPE_SURFACE = 1, // = D3DRESOURCETYPE.D3DRTYPE_SURFACE
    X_D3DRTYPE_VOLUME = 2, // = D3DRESOURCETYPE.D3DRTYPE_VOLUME
    X_D3DRTYPE_TEXTURE = 3, // = D3DRESOURCETYPE.D3DRTYPE_TEXTURE
    X_D3DRTYPE_VOLUMETEXTURE = 4, // = D3DRESOURCETYPE.D3DRTYPE_VOLUMETEXTURE
    X_D3DRTYPE_CUBETEXTURE = 5, // = D3DRESOURCETYPE.D3DRTYPE_CUBETEXTURE
    X_D3DRTYPE_VERTEXBUFFER = 6, // = D3DRESOURCETYPE.D3DRTYPE_VERTEXBUFFER
    X_D3DRTYPE_INDEXBUFFER = 7, // = D3DRESOURCETYPE.D3DRTYPE_INDEXBUFFER
    X_D3DRTYPE_PUSHBUFFER = 8,
    X_D3DRTYPE_PALETTE = 9,
    X_D3DRTYPE_FIXUP = 10,

    X_D3DRTYPE_FORCE_DWORD = 0x7fffffff
}
X_D3DRESOURCETYPE;

extern HRESULT CompileShader
(
    std::string hlsl_str,
    const char* shader_profile,
    IDxcBlob** ppHostShader,
    const char* pSourceName,
    bool compileSpirv = false
);



struct ShaderSources {
    // Pixel Shader
    std::string pixelShaderTemplateHlsl[3];

    std::string fixedFunctionPixelShaderHlsl;
    std::string fixedFunctionPixelShaderPath;

    // Vertex Shader
    std::string vertexShaderTemplateHlsl[VertexShaderTypeMax][2];

    std::string fixedFunctionVertexShaderHlsl;
    std::string fixedFunctionVertexShaderPath;

    std::string vertexShaderPassthroughHlsl;
    std::string vertexShaderPassthroughPath;

    // Load shaders from disk (if out-of-date)
    // and return the current loaded shader version
    int Update();

    // Start a thread to watch for changes in the shader folder
    void InitShaderHotloading();

private:
    void LoadShadersFromDisk();

    // counts upwards on every change detected to the shader source files at runtime
    std::atomic_int shaderVersionOnDisk = 0;
    // current loaded shader version
    // Initialized to < shaderVersionOnDisk
    int shaderVersionLoadedFromDisk = -1;
};

extern ShaderSources g_ShaderSources;

extern std::string template_vs[VertexShaderTypeMax];
