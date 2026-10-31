
// HLSL
#define X_D3DSCM_CORRECTION                 96 // Add 96 to arrive at the range 0..191 (instead of -96..95)
#define X_D3DVS_CONSTREG_COUNT              192

	// Fog depth is taken from the vertex, rather than generated
#define FOG_DEPTH_NONE 0
	// Fog depth is the output Z coordinate
#define FOG_DEPTH_Z 1
	// Fog depth is based on the output W coordinate (1 / W)
#define FOG_DEPTH_W 2
	// Fog depth is based distance of the vertex from the eye position
#define FOG_DEPTH_RANGE 3

    // https://docs.microsoft.com/en-us/windows/win32/direct3d9/fog-formulas
#define FOG_TABLE_NONE 0
#define FOG_TABLE_EXP 1
#define FOG_TABLE_EXP2 2
#define FOG_TABLE_LINEAR 3

struct Transforms
{
    float4x4 View;
    float4x4 Projection;
    float4x4 Texture[4]; // c8-c23 (4 matrices x 4 regs each)
    float4x4 WorldView[4];
    float4x4 WorldViewInverseTranspose[4];
};

// See D3DLIGHT
struct Light
{
    float4 Diffuse;
    float4 Specular;

    // Viewspace light position (xyz) + Range in .w
    float4 PositionV; // cN+2.xyz
   // float Range; // cN+2.w

    // Viewspace light direction (normalized) in xyz + Type in .w
    float4 DirectionVN; // cN+3.xyz
    //float Type; // cN+3.w  // 1=Point, 2=Spot, 3=Directional

    // Attenuation (xyz) + Falloff in .w
    float4 Attenuation; // cN+4.xyz
    //float Falloff; // cN+4.w

    float4 SpotParams; // cN+5: x=CosHalfPhi, y=SpotIntensityDivisor, zw unused
    //float CosHalfPhi; // cN+5.x
    //float SpotIntensityDivisor; // cN+5.y

   
    // cN+5.z/.w unused/reserved for future use
};

#define CosHalfPhi(light) (light).SpotParams.x
#define SpotIntensityDivisor(light) (light).SpotParams.y

struct Material
{
    float4 Diffuse; // base for Materials[0], these will be array-offsetted
    float4 Ambient;
    float4 Specular;
    float4 Emissive;
    float4 Power; // c110.w/y/z free
};

struct Modes
{
    // c116
    float AmbientMaterialSource;
    float DiffuseMaterialSource;
    float SpecularMaterialSource;
    float EmissiveMaterialSource;

    // c117
    float BackAmbientMaterialSource;
    float BackDiffuseMaterialSource;
    float BackSpecularMaterialSource;
    float BackEmissiveMaterialSource;

    // c118
    float Lighting;
    float TwoSidedLighting;
    // float SpecularEnable; 
    float LocalViewer;
    float _pad0;
    // c118.w unused

    // c119
    // float ColorVertex;
    float VertexBlend_NrOfMatrices;
    float VertexBlend_CalcLastWeight;
    float NormalizeNormals;
    float _pad1;
    // c119.w unused
};



struct PointSprite
{
  // c126
    float PointSize;
    float PointSize_Min;
    float PointSize_Max;
//  float PointScaleEnable;
    float XboxRenderTargetHeight;
    // c127
    float4 PointScaleABC; //xyz PointScaleABC + RenderUpscaleFactor in .w
   // float RenderUpscaleFactor;
};

#define SRenderUpscaleFactor(PointSprite) (PointSprite).PointScaleABC.w

struct TextureState
{
    float TextureTransformFlagsCount; 
    float TextureTransformFlagsProjected;
    float TexCoordIndex;
    float TexCoordIndexGen;
};

struct Fog
{
    // c120
    float Enable;
    float DepthMode;
    float TableMode;
    float Density; // EXP density
    // c121
    float Start; // LINEAR start
    float End; // LINEAR end
    float _pad0;
    float _pad1;
};


// Vertex lighting
// Both frontface and backface lighting can be calculated
struct TwoSidedColor
{
    float4 Front; // c104.xyz
    float4 Back; // c105.xyz
};

struct FixedFunctionVertexShaderState
{
    Transforms Transforms;
    Light Lights[8];

    TwoSidedColor TotalLightsAmbient; // c104 - c105
    Material Materials[2]; // c106 - c115
    Modes Modes; // c116 - c119
    Fog Fog; // c120 - c121
    TextureState TextureStates[4]; // c122 - c125
    PointSprite PointSprite; // c126 - c127
    float4 TexCoordComponentCount; // c128
};


#ifdef __spirv__

struct PushConstants
{
    uint64_t VertexShaderConstants;
    uint64_t PixelShaderConstants;
    uint64_t SharedConstants;
};

[[vk::push_constant]] ConstantBuffer<PushConstants> g_PushConstants;

float4x4 LoadMatrix(uint64_t addr)
{
    float4 r0 = vk::RawBufferLoad<float4>(addr + 0);
    float4 r1 = vk::RawBufferLoad<float4>(addr + 16);
    float4 r2 = vk::RawBufferLoad<float4>(addr + 32);
    float4 r3 = vk::RawBufferLoad<float4>(addr + 48);
    return float4x4(r0,r1,r2,r3);
}

Fog LoadFog(uint64_t addr)
{
    float4 f0 = vk::RawBufferLoad<float4>(addr);
    float4 f1 = vk::RawBufferLoad<float4>(addr + 16);
    Fog f;
    f.Enable = f0.x;
    f.DepthMode = f0.y;
    f.TableMode = f0.z;
    f.Density = f0.w;
    f.Start = f1.x;
    f.End = f1.y;
    f._pad0 = f1.z;
    f._pad1 = f1.w;
    return f;
}

#define REG(cN) ((cN) * 16)
#define REG_COMP(c,comp) (REG(c) + (comp)*4)
#define V_CBUFFER_OFFSET(cN, comp) ((cN)*16 + ((comp) == 'x' ? 0 : (comp) == 'y' ? 4 : (comp) == 'z' ? 8 : 12))
#define V_ARRAY_OFFSET(cn, slot) ((cn)*16 + (slot)*16)
#define V_STRUCT_OFFSET(cN, subOffset) (REG(cN) + (subOffset))

// Separate macros for register offsets (converted to bytes) vs array indices
#define REG_TO_BYTES(cN) ((cN) * 16)

// For single component access within a register
#define COMP_OFFSET(comp) ((comp) * 4)  // 0, 1, 2, or 3 for x, y, z, w

// For array access where the base is a register number
#define ARRAY_ELEMENT_BYTES(baseReg, elementIndex) (REG_TO_BYTES(baseReg) + (elementIndex) * 16)

// Updated macros
#define LOAD_FLOAT(c, comp) \
    vk::RawBufferLoad<float>(g_PushConstants.VertexShaderConstants + REG_TO_BYTES(c) + COMP_OFFSET(comp))

#define LOAD_FLOAT4(c) \
    vk::RawBufferLoad<float4>(g_PushConstants.VertexShaderConstants + REG_TO_BYTES(c))

#define vRegisterDefaultValues(i) vk::RawBufferLoad<float4>(g_PushConstants.VertexShaderConstants + 192*16 + (i)*16)
#define vRegisterDefaultFlagsPacked(i) vk::RawBufferLoad<float4>(g_PushConstants.VertexShaderConstants + 208*16 + (i)*16)

#define TransfoView LoadMatrix(g_PushConstants.VertexShaderConstants + V_STRUCT_OFFSET(0, 0))
#define TransfoProj LoadMatrix(g_PushConstants.VertexShaderConstants + V_STRUCT_OFFSET(4, 0))
#define TransfoTex(i) LoadMatrix(g_PushConstants.VertexShaderConstants + V_STRUCT_OFFSET(8, (i)*64))
#define TransfoWorldView(i)   LoadMatrix(g_PushConstants.VertexShaderConstants + V_STRUCT_OFFSET(24, (i)*64))
#define TransfoWorldViewIT(i) LoadMatrix(g_PushConstants.VertexShaderConstants + V_STRUCT_OFFSET(40, (i)*64))


#define PSPointSize \
vk::RawBufferLoad<float>(g_PushConstants.VertexShaderConstants + V_CBUFFER_OFFSET(126,'x'))

#define PSPointSize_Min \
vk::RawBufferLoad<float>(g_PushConstants.VertexShaderConstants + V_CBUFFER_OFFSET(126,'y'))

#define PSPointSize_Max \
vk::RawBufferLoad<float>(g_PushConstants.VertexShaderConstants + V_CBUFFER_OFFSET(126,'z'))

#define PSXboxRenderTargetHeight \
vk::RawBufferLoad<float>(g_PushConstants.VertexShaderConstants + V_CBUFFER_OFFSET(126,'w'))

#define PSPointScaleABC \
vk::RawBufferLoad<float4>(g_PushConstants.VertexShaderConstants + V_CBUFFER_OFFSET(127,'x'))
#define PSRenderUpscaleFactor PSPointScaleABC.w

#define LIGHT_STRIDE 96

#define LIGHT_CBASE 56
#define LIGHT_SIZE_BYTES 96 // 6 float4s * 16
#define LDiffuse(i)        vk::RawBufferLoad<float4>(g_PushConstants.VertexShaderConstants + (LIGHT_CBASE*16 + (i)*LIGHT_SIZE_BYTES + 0))
#define LSpecular(i)       vk::RawBufferLoad<float4>(g_PushConstants.VertexShaderConstants + (LIGHT_CBASE*16 + (i)*LIGHT_SIZE_BYTES + 16))
#define LPositionV(i)      vk::RawBufferLoad<float4>(g_PushConstants.VertexShaderConstants + (LIGHT_CBASE*16 + (i)*LIGHT_SIZE_BYTES + 32))
#define LDirectionVN(i)    vk::RawBufferLoad<float4>(g_PushConstants.VertexShaderConstants + (LIGHT_CBASE*16 + (i)*LIGHT_SIZE_BYTES + 48))
#define LAttenuation(i)    vk::RawBufferLoad<float4>(g_PushConstants.VertexShaderConstants + (LIGHT_CBASE*16 + (i)*LIGHT_SIZE_BYTES + 64))
#define LSpotParams(i)     vk::RawBufferLoad<float4>(g_PushConstants.VertexShaderConstants + (LIGHT_CBASE*16 + (i)*LIGHT_SIZE_BYTES + 80))

#define TLightColorFront vk::RawBufferLoad<float4>(g_PushConstants.VertexShaderConstants + V_STRUCT_OFFSET(104, 0))
#define TLightColorBack vk::RawBufferLoad<float4>(g_PushConstants.VertexShaderConstants + V_STRUCT_OFFSET(105, 0))


#define MAT_STRIDE 80

#define MDiffuse(i) \
vk::RawBufferLoad<float4>(g_PushConstants.VertexShaderConstants + V_STRUCT_OFFSET(106, (i)*MAT_STRIDE + 0))
#define MAmbient(i) \
vk::RawBufferLoad<float4>(g_PushConstants.VertexShaderConstants + V_STRUCT_OFFSET(106, (i)*MAT_STRIDE + 16))
#define MSpecular(i) \
vk::RawBufferLoad<float4>(g_PushConstants.VertexShaderConstants + V_STRUCT_OFFSET(106, (i)*MAT_STRIDE + 32))
#define MEmissive(i) \
vk::RawBufferLoad<float4>(g_PushConstants.VertexShaderConstants + V_STRUCT_OFFSET(106, (i)*MAT_STRIDE + 48))
#define MPower(i) \
vk::RawBufferLoad<float4>(g_PushConstants.VertexShaderConstants + V_STRUCT_OFFSET(106, (i)*MAT_STRIDE + 64))

#define ModeAmbientMaterialSource LOAD_FLOAT(116,0)
#define ModeDiffuseMaterialSource LOAD_FLOAT(116,1)
#define ModeSpecularMaterialSource LOAD_FLOAT(116,2)
#define ModeEmissiveMaterialSource LOAD_FLOAT(116,3)

#define ModeLighting LOAD_FLOAT(118,0)
#define ModeTwoSidedLighting LOAD_FLOAT(118,1)
#define ModeLocalViewer LOAD_FLOAT(118,2)
#define ModeVertexBlend_NrOfMatrices LOAD_FLOAT(119,0)
#define ModeVertexBlend_CalcLastWeight LOAD_FLOAT(119,1)
#define ModeNormalizeNormals LOAD_FLOAT(119,2)


#define fog LoadFog(g_PushConstants.VertexShaderConstants + V_STRUCT_OFFSET(120,0))

#define TexState_TransfoFlagsCount(i) \
vk::RawBufferLoad<float>(g_PushConstants.VertexShaderConstants + REG(122) + (i)*16 + 0)

#define TexState_TransfoFlagsProj(i) \
vk::RawBufferLoad<float>(g_PushConstants.VertexShaderConstants + REG(122) + (i)*16 + 4)

#define TexState_TexCoordIndex(i) \
vk::RawBufferLoad<float>(g_PushConstants.VertexShaderConstants + REG(122) + (i)*16 + 8)

#define TexState_TexCoorIndexGen(i) \
vk::RawBufferLoad<float>(g_PushConstants.VertexShaderConstants + REG(122) + (i)*16 + 12)

#define TexCoordComponentCount vk::RawBufferLoad<float4>(g_PushConstants.VertexShaderConstants + V_CBUFFER_OFFSET(128, 'x') )

#define xboxScreenspaceScale  vk::RawBufferLoad<float4>(g_PushConstants.VertexShaderConstants + V_CBUFFER_OFFSET(212, 'x') )
#define xboxScreenspaceOffset  vk::RawBufferLoad<float4>(g_PushConstants.VertexShaderConstants + V_CBUFFER_OFFSET(213, 'x') )
#define xboxTextureScale(i) vk::RawBufferLoad<float4>(g_PushConstants.VertexShaderConstants +  V_ARRAY_OFFSET(214, i) )

#else

// Default values for vertex registers, and whether to use them

cbuffer VertexShaderConstants : register(b0, space4)
{
    Transforms transforms : packoffset(c0);
    Light Lights[8] : packoffset(c56); //c56 - c103 (6 * 8 = 48)

    TwoSidedColor TotalLightsAmbient : packoffset(c104); // c104 - c105
    Material Materials[2] : packoffset(c106); // c106 - c115
    Modes modes : packoffset(c116); // c116 - c119
    Fog fog : packoffset(c120); // c120 - c121
    TextureState TextureStates[4] : packoffset(c122); // c122 - c125
    PointSprite pointSprite : packoffset(c126); // c126 - c127
    float4 texCoordComponentCount : packoffset(c128); // c128
    
    //regular vertex constant
    float4 vRegisterDefaultVal[16] : packoffset(c192); //vertex attribute (on cxbx it seems to work if those are empty see SetFixedFunctionDefaultVertexAttributes)
    float4 vRegisterDefaultFlagsPack[4] : packoffset(c208); // Default values for vertex registers, and whether to use them (see UpdateHostVertexDeclaration function)
    float4 xboxScreenspaceScale : packoffset(c212);
    float4 xboxScreenspaceOffset : packoffset(c213);
    float4 xboxTextureScl[4] : packoffset(c214);
    
    //float4 randomUVTest : packoffset(c218); //left over debugging keep it in case I need to make another similar test
    
   // float4 FogInfo : packoffset(c218); //Parameters for mapping the shader's fog output value to a fog factor (D3DVS_CONSTREG_FOGINFO)  
}

cbuffer SharedConstants : register(b2, space4)
{
    uint FogTableMode : packoffset(c81.z);
    uint FogDensity : packoffset(c81.w);
    uint FogStart : packoffset(c82.x);
    uint FogEnd : packoffset(c82.y);
    
    float2 halfPixelOffset : packoffset(c88);
    //float halfPixelOffsetY : packoffset(c88.y);
    
    float alphaThreshold : packoffset(c88.z);
}

#define g_halfPixelOffset halfPixelOffset
#define TransfoView transforms.View
#define TransfoProj transforms.Projection
#define TransfoTex(i) transforms.Texture[i]
#define TransfoWorldView(i) transforms.WorldView[i]
#define TransfoWorldViewIT(i) transforms.WorldViewInverseTranspose[i]

#define TLightColorBack TotalLightsAmbient.Back
#define TLightColorFront TotalLightsAmbient.Front

#define ModeAmbientMaterialSource modes.AmbientMaterialSource
#define ModeDiffuseMaterialSource modes.DiffuseMaterialSource
#define ModeSpecularMaterialSource modes.SpecularMaterialSource
#define ModeEmissiveMaterialSource modes.EmissiveMaterialSource


#define ModeTwoSidedLighting modes.TwoSidedLighting
#define ModeLocalViewer modes.LocalViewer
#define ModeVertexBlend_NrOfMatrices modes.VertexBlend_NrOfMatrices
#define ModeVertexBlend_CalcLastWeight modes.VertexBlend_CalcLastWeight
#define ModeNormalizeNormals modes.NormalizeNormals
#define ModeLighting modes.Lighting

#define TexCoordComponentCount texCoordComponentCount


#define vRegisterDefaultValues(i) vRegisterDefaultVal[i]
#define vRegisterDefaultFlagsPacked(i) vRegisterDefaultFlagsPack[i]
#define xboxTextureScale(i) xboxTextureScl[i]
#define PSRenderUpscaleFactor pointSprite.PointScaleABC.w


#endif

void UnpackRegisterDefaultFlags(out bool flags[16])
{
    float4 packed0 = vRegisterDefaultFlagsPacked(0);
    float4 packed1 = vRegisterDefaultFlagsPacked(1);
    float4 packed2 = vRegisterDefaultFlagsPacked(2);
    float4 packed3 = vRegisterDefaultFlagsPacked(3);

    flags[0] = packed0.x;
    flags[1] = packed0.y;
    flags[2] = packed0.z;
    flags[3] = packed0.w;

    flags[4] = packed1.x;
    flags[5] = packed1.y;
    flags[6] = packed1.z;
    flags[7] = packed1.w;

    flags[8] = packed2.x;
    flags[9] = packed2.y;
    flags[10] = packed2.z;
    flags[11] = packed2.w;

    flags[12] = packed3.x;
    flags[13] = packed3.y;
    flags[14] = packed3.z;
    flags[15] = packed3.w;
}

void FillLightArray(out Light lightsArray[8])
{
#ifdef __spirv__
    
    [unroll]
    for (uint i = 0; i < 8; i++)
    {
        lightsArray[i].Diffuse = LDiffuse(i);
        lightsArray[i].Specular = LSpecular(i);
        lightsArray[i].PositionV = LPositionV(i);
        lightsArray[i].DirectionVN = LDirectionVN(i);
        lightsArray[i].Attenuation = LAttenuation(i);
        lightsArray[i].SpotParams = LSpotParams(i);
    
    }

    
#else   
    lightsArray = Lights;
 #endif
}

Light LoadLight(const uint index)
{
#ifdef __spirv__
    Light light;
    light.Diffuse = LDiffuse(index);
    light.Specular = LSpecular(index);
    light.PositionV = LPositionV(index);
    light.DirectionVN = LDirectionVN(index);
    light.Attenuation = LAttenuation(index);
    light.SpotParams = LSpotParams(index);
    return light;
#else
    return Lights[index];
#endif
}

Light LoadDirectionalLight(const uint index)
{
    Light light = (Light)0;
#ifdef __spirv__
    light.Diffuse = LDiffuse(index);
#if !defined(FIXED_FUNCTION_VERTEX_SHADER_VARIANT) || FFVS_SPECULAR_ENABLE_VALUE
    light.Specular = LSpecular(index);
#endif
    light.DirectionVN = LDirectionVN(index);
#else
    light.Diffuse = Lights[index].Diffuse;
#if !defined(FIXED_FUNCTION_VERTEX_SHADER_VARIANT) || FFVS_SPECULAR_ENABLE_VALUE
    light.Specular = Lights[index].Specular;
#endif
    light.DirectionVN = Lights[index].DirectionVN;
#endif
    return light;
}

void FillMaterialArray(out Material matArray[2])
{
#ifdef __spirv__
    
    [unroll]
    for (uint i = 0; i < 2; i++)
    {
        matArray[i].Diffuse = MDiffuse(i);
        matArray[i].Ambient = MAmbient(i);
        matArray[i].Specular = MSpecular(i);
        matArray[i].Emissive = MEmissive(i);
        matArray[i].Power = MPower(i);
    }

    
#else   
    matArray = Materials;
 #endif
}

Material LoadMaterial(const uint index)
{
#ifdef __spirv__
    Material material;
    material.Diffuse = MDiffuse(index);
    material.Ambient = MAmbient(index);
    material.Specular = MSpecular(index);
    material.Emissive = MEmissive(index);
    material.Power = MPower(index);
    return material;
#else
    return Materials[index];
#endif
}

Material LoadSpecializedMaterial(const uint index)
{
    Material material = (Material)0;
#ifdef __spirv__
    material.Diffuse = MDiffuse(index);
    material.Ambient = MAmbient(index);
    material.Emissive = MEmissive(index);
#if !defined(FIXED_FUNCTION_VERTEX_SHADER_VARIANT) || FFVS_SPECULAR_ENABLE_VALUE
    material.Specular = MSpecular(index);
    material.Power = MPower(index);
#endif
#else
    material.Diffuse = Materials[index].Diffuse;
    material.Ambient = Materials[index].Ambient;
    material.Emissive = Materials[index].Emissive;
#if !defined(FIXED_FUNCTION_VERTEX_SHADER_VARIANT) || FFVS_SPECULAR_ENABLE_VALUE
    material.Specular = Materials[index].Specular;
    material.Power = Materials[index].Power;
#endif
#endif
    return material;
}


void FillTextureStateArray(out TextureState texArray[4])
{
#ifdef __spirv__
    
    [unroll]
    for (uint i = 0; i < 4; i++)
    {
        texArray[i].TextureTransformFlagsCount = TexState_TransfoFlagsCount(i);
        texArray[i].TextureTransformFlagsProjected = TexState_TransfoFlagsProj(i);
        texArray[i].TexCoordIndex = TexState_TexCoordIndex(i);
        texArray[i].TexCoordIndexGen = TexState_TexCoorIndexGen(i);
    } 
#else   
    texArray = TextureStates;
 #endif
}

PointSprite GetPointSprite()
{
#ifdef __spirv__
    PointSprite pr; 
    pr.PointSize = PSPointSize;
    pr.PointSize_Min = PSPointSize_Min;
    pr.PointSize_Max = PSPointSize_Max;
    pr.XboxRenderTargetHeight = PSXboxRenderTargetHeight;
    pr.PointScaleABC = PSPointScaleABC;
    
    return pr;
   
#else
    return pointSprite;
#endif
}

// Input register indices (also known as attributes, as given in VS_INPUT.v array)
// TODO : Convert FVF codes on CPU to a vertex declaration with these standardized register indices:
// NOTE : Converting FVF vertex indices must also consider NV2A vertex attribute 'slot mapping',
// as set in NV2A_VTXFMT/NV097_SET_VERTEX_DATA_ARRAY_FORMAT!
// TODO : Rename these into SLOT_POSITION, SLOT_WEIGHT, SLOT_TEXTURE0, SLOT_TEXTURE3, etc :
static const uint position = 0; // See X_D3DFVF_XYZ      / X_D3DVSDE_POSITION    was float4 pos : POSITION;
static const uint weight = 1; // See X_D3DFVF_XYZB1-4  / X_D3DVSDE_BLENDWEIGHT was float4 bw : BLENDWEIGHT;
static const uint normal = 2; // See X_D3DFVF_NORMAL   / X_D3DVSDE_NORMAL      was float4 normal : NORMAL; // Note : Only normal.xyz is used. 
static const uint diffuse = 3; // See X_D3DFVF_DIFFUSE  / X_D3DVSDE_DIFFUSE     was float4 color[2] : COLOR;
static const uint specular = 4; // See X_D3DFVF_SPECULAR / X_D3DVSDE_SPECULAR
static const uint fogCoord = 5; // Has no X_D3DFVF_* ! See X_D3DVSDE_FOG         Note : Only fog.x is used.
static const uint pointSize = 6; // Has no X_D3DFVF_* ! See X_D3DVSDE_POINTSIZE
static const uint backDiffuse = 7; // Has no X_D3DFVF_* ! See X_D3DVSDE_BACKDIFFUSE was float4 backColor[2] : TEXCOORD4;
static const uint backSpecular = 8; // Has no X_D3DFVF_* ! See X_D3DVSDE_BACKSPECULAR
static const uint texcoord0 = 9; // See X_D3DFVF_TEX1     / X_D3DVSDE_TEXCOORD0   was float4 texcoord[4] : TEXCOORD;
static const uint texcoord1 = 10; // See X_D3DFVF_TEX2     / X_D3DVSDE_TEXCOORD1
static const uint texcoord2 = 11; // See X_D3DFVF_TEX3     / X_D3DVSDE_TEXCOORD2
static const uint texcoord3 = 12; // See X_D3DFVF_TEX4     / X_D3DVSDE_TEXCOORD3
static const uint reserved0 = 13; // Has no X_D3DFVF_*     / X_D3DVSDE_*
static const uint reserved1 = 14; // Has no X_D3DFVF_*     / X_D3DVSDE_*
static const uint reserved2 = 15; // Has no X_D3DFVF_*     / X_D3DVSDE_*
