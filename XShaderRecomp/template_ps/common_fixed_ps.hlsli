#define arr(name, type, length) type name[length]
#define alignas(x)
#define const static

	// From X_D3DTOP
const float X_D3DTOP_DISABLE = 1;
const float X_D3DTOP_SELECTARG1 = 2;
const float X_D3DTOP_SELECTARG2 = 3;
const float X_D3DTOP_MODULATE = 4;
const float X_D3DTOP_MODULATE2X = 5;
const float X_D3DTOP_MODULATE4X = 6;
const float X_D3DTOP_ADD = 7;
const float X_D3DTOP_ADDSIGNED = 8;
const float X_D3DTOP_ADDSIGNED2X = 9;
const float X_D3DTOP_SUBTRACT = 10;
const float X_D3DTOP_ADDSMOOTH = 11;
const float X_D3DTOP_BLENDDIFFUSEALPHA = 12;
const float X_D3DTOP_BLENDCURRENTALPHA = 13;
const float X_D3DTOP_BLENDTEXTUREALPHA = 14;
const float X_D3DTOP_BLENDFACTORALPHA = 15;
const float X_D3DTOP_BLENDTEXTUREALPHAPM = 16;
const float X_D3DTOP_PREMODULATE = 17;
const float X_D3DTOP_MODULATEALPHA_ADDCOLOR = 18;
const float X_D3DTOP_MODULATECOLOR_ADDALPHA = 19;
const float X_D3DTOP_MODULATEINVALPHA_ADDCOLOR = 20;
const float X_D3DTOP_MODULATEINVCOLOR_ADDALPHA = 21;
const float X_D3DTOP_DOTPRODUCT3 = 22;
const float X_D3DTOP_MULTIPLYADD = 23;
const float X_D3DTOP_LERP = 24;
const float X_D3DTOP_BUMPENVMAP = 25;
const float X_D3DTOP_BUMPENVMAPLUMINANCE = 26;

	// D3DTA taken from D3D9 - we don't have Xbox definitions
	// for these so I guess they're the same?
const float X_D3DTA_DIFFUSE = 0x00000000; // select diffuse color (read only)
const float X_D3DTA_CURRENT = 0x00000001; // select stage destination register (read/write)
const float X_D3DTA_TEXTURE = 0x00000002; // select texture color (read only)
const float X_D3DTA_TFACTOR = 0x00000003; // select D3DRS_TEXTUREFACTOR (read only)
const float X_D3DTA_SPECULAR = 0x00000004; // select specular color (read only)
const float X_D3DTA_TEMP = 0x00000005; // select temporary register color (read/write)
const float X_D3DTA_CONSTANT = 0x00000006; // select texture stage constant
const float X_D3DTA_COMPLEMENT = 0x00000010; // take 1.0 - x (read modifier)
const float X_D3DTA_ALPHAREPLICATE = 0x00000020; // replicate alpha to color components (read modifier)

const int SAMPLE_NONE = 0;
const int SAMPLE_2D = 1;
const int SAMPLE_3D = 2;
const int SAMPLE_CUBE = 3;

 // https://docs.microsoft.com/en-us/windows/win32/direct3d9/fog-formulas
const float FOG_TABLE_NONE = 0;
const float FOG_TABLE_EXP = 1;
const float FOG_TABLE_EXP2 = 2;
const float FOG_TABLE_LINEAR = 3;

struct PsTextureStageState
{
    uint BUMPENVMAT00;
    uint BUMPENVMAT01;
    uint BUMPENVMAT11;
    uint BUMPENVMAT10;
    uint BUMPENVLSCALE;
    uint BUMPENVLOFFSET;

};

	// This state is compiled into the shader
	// Values correspond to XD3D8 version of D3DTEXTURESTAGESTATETYPE
	// https://docs.microsoft.com/en-us/windows/win32/direct3d9/d3dtexturestagestatetype
struct PsTextureHardcodedState
{
    uint COLOROP;
    uint COLORARG0;
    uint COLORARG1;
    uint COLORARG2;
    uint ALPHAOP;
    uint ALPHAARG0;
    uint ALPHAARG1;
    uint ALPHAARG2;
    uint RESULTARG;
};


cbuffer SharedConstants : register(b2, space4)
{

    // Texture 2D indices - pack 4 per constant register
    uint texture2D_0 : packoffset(c0.x); // c0 = bytes 0-15
    uint texture2D_1 : packoffset(c0.y);
    uint texture2D_2 : packoffset(c0.z);
    uint texture2D_3 : packoffset(c0.w);
    
    // Texture 3D indices (c4-c7)
    uint texture3D_0 : packoffset(c4.x);
    uint texture3D_1 : packoffset(c4.y);
    uint texture3D_2 : packoffset(c4.z);
    uint texture3D_3 : packoffset(c4.w);
    
    uint textureCube_0 : packoffset(c8.x);

    // Samplers (c12-c15)  
    uint sampler_0 : packoffset(c12.x);
    uint sampler_1 : packoffset(c12.y);
    uint sampler_2 : packoffset(c12.z);
    uint sampler_3 : packoffset(c12.w);
    
    uint color_op_0 : packoffset(c16.x);
    uint color_op_1 : packoffset(c16.y);
    uint color_op_2 : packoffset(c16.z);
    uint color_op_3 : packoffset(c16.w);
    
    uint color_arg0_0 : packoffset(c20.x);
    uint color_arg0_1 : packoffset(c20.y);
    uint color_arg0_2 : packoffset(c20.z);
    uint color_arg0_3 : packoffset(c20.w);
    
    uint color_arg1_0 : packoffset(c24.x);
    uint color_arg1_1 : packoffset(c24.y);
    uint color_arg1_2 : packoffset(c24.z);
    uint color_arg1_3 : packoffset(c24.w);
   
    uint color_arg2_0 : packoffset(c28.x);
    uint color_arg2_1 : packoffset(c28.y);
    uint color_arg2_2 : packoffset(c28.z);
    uint color_arg2_3 : packoffset(c28.w);
    
    uint alpha_op_0 : packoffset(c32.x);
    uint alpha_op_1 : packoffset(c32.y);
    uint alpha_op_2 : packoffset(c32.z);
    uint alpha_op_3 : packoffset(c32.w);
    
    //alpha arg0 c36
    uint alpha_arg0_0 : packoffset(c36.x);
    
    //alpha arg1 c40
    uint alpha_arg1_0 : packoffset(c40.x);
    
    //alpha arg2 c44
    uint alpha_arg2_0 : packoffset(c44.x);
    
    //resultarg c48
    uint result_arg_0 : packoffset(c48.x);
    
    uint TextureSampleType_0 : packoffset(c52.x);
    uint TextureSampleType_1 : packoffset(c52.y);
    uint TextureSampleType_2 : packoffset(c52.z);
    uint TextureSampleType_3 : packoffset(c52.w);
    
    uint bumpenvtmat00 : packoffset(c56.x);
    
    uint bumpenvtmat01 : packoffset(c60.x);
    
    uint bumpenvtmat11 : packoffset(c64.x);
    
    uint bumpenvtmat10 : packoffset(c68.x);
    
    uint bumpenvlscale : packoffset(c72.x);
    
    uint bumpenvloffset : packoffset(c76.x);
    
    uint texcoordindex : packoffset(c80.x);
    
    float4 TextureFactor : packoffset(c84);
    
    uint SpecularEnable : packoffset(c85.x);
    uint FogEnable : packoffset(c85.y);
    uint FogTableMode : packoffset(c85.z);
    uint FogDensity : packoffset(c85.w);
    
    uint FogStart : packoffset(c86.x);
    uint FogEnd : packoffset(c86.y);
    float FogColor0 : packoffset(c86.z);
    float FogColor1 : packoffset(c86.w);
    float FogColor2 : packoffset(c87.x);
    uint alphaTestEnable : packoffset(c87.y);
    uint alphaFunc : packoffset(c87.z);
    float alphaRef : packoffset(c87.w);
 
       

        // Other data
   /* uint booleans : packoffset(c12.x);
    uint swappedTexcoords : packoffset(c12.y);
    float halfPixelOffsetX : packoffset(c12.z);
    float halfPixelOffsetY : packoffset(c12.w);
    
    float alphaThreshold : packoffset(c13.x);*/
    
    //TextureCombinerState combiners[16] : packoffset(c14);
};

uint GetTextureStage(uint slot, uint type)
{
    switch (type)
    {
        case 1:
        default:
            return texture2D_0;
        case 2:
            return texture3D_0;
        case 3:
            return textureCube_0;
    }
}

uint GetSamplerState(uint slot)
{
    switch (slot)
    {
        default:
            return sampler_0;
        case 1:
            return sampler_1;
        case 2:
            return sampler_2;
        case 3:
            return sampler_3;
    }
}

uint GetTextureSampleType(uint slot)
{
    switch (slot)
    {
        default:
            return TextureSampleType_0;
        case 1:
            return TextureSampleType_1;
        case 2:
            return TextureSampleType_2;
        case 3:
            return TextureSampleType_3;
    }
}