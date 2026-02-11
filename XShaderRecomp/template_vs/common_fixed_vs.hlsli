
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
    float4x4 Texture[4]; // c8-c23 (4 matrices × 4 regs each)
    float4x4 WorldView[4];
    float4x4 WorldViewInverseTranspose[4];
};

// See D3DLIGHT
struct Light
{
    // TODO in vs_4_0+ when floats are packable
    // Change colour values to float3
    // And put something useful in the alpha slot
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
    // c118.w unused

    // c119
    // float ColorVertex;
    float VertexBlend_NrOfMatrices;
    float VertexBlend_CalcLastWeight;
    float NormalizeNormals;
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



// Default values for vertex registers, and whether to use them

cbuffer VertexShaderConstants : register(b0, space4)
{
    Transforms transforms : packoffset(c0);
    Light Lights[8] : packoffset(c56);

    TwoSidedColor TotalLightsAmbient : packoffset(c104); // c104 - c105
    Material Materials[2] : packoffset(c106); // c106 - c115
    Modes modes : packoffset(c116); // c116 - c119
    Fog fog : packoffset(c120); // c120 - c121
    TextureState TextureStates[4] : packoffset(c122); // c122 - c125
    PointSprite pointSprite : packoffset(c126); // c126 - c128
    float4 TexCoordComponentCount : packoffset(c128); // c129
    
    //regular vertex constant
    float4 vRegisterDefaultValues[16] : packoffset(c192); //vertex attribute (on cxbx it seems to work if those are empty see SetFixedFunctionDefaultVertexAttributes)
    float4 vRegisterDefaultFlagsPacked[4] : packoffset(c208); // Default values for vertex registers, and whether to use them (see UpdateHostVertexDeclaration function)
    float4 xboxScreenspaceScale : packoffset(c212);
    float4 xboxScreenspaceOffset : packoffset(c213);
    float4 xboxTextureScale[4] : packoffset(c214);
   // float4 FogInfo : packoffset(c218); //Parameters for mapping the shader's fog output value to a fog factor (D3DVS_CONSTREG_FOGINFO)  
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

