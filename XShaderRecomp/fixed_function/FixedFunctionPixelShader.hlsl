#include "common_fixed_ps.hlsli"
#include "fixed_function_pixel_shader/state.hlsli"

Texture2D<float4> g_Texture2DDescriptorHeap[] : register(t0, space0);
Texture3D<float4> g_Texture3DDescriptorHeap[] : register(t0, space1);
TextureCube<float4> g_TextureCubeDescriptorHeap[] : register(t0, space2);
SamplerState g_SamplerDescriptorHeap[] : register(s0, space3);

struct PS_INPUT // Declared identical to vertex shader output (see VS_OUTPUT)
{
    float4 iPos : SV_Position; // Screen space x,y pixel location (changed from float 2 IPos)
    float4 iD0 : COLOR0; // Front-facing primary (diffuse) vertex color (clamped to 0..1)
    float4 iD1 : COLOR1; // Front-facing secondary (specular) vertex color (clamped to 0..1)
    float iFog : FOG;
    float iPts : PSIZE;
    float4 iB0 : TEXCOORD4; // Back-facing primary (diffuse) vertex color (clamped to 0..1)
    float4 iB1 : TEXCOORD5; // Back-facing secondary (specular) vertex color (clamped to 0..1)
    float4 iT[4] : TEXCOORD0; // Texture Coord 0
    uint iFF : SV_IsFrontFace; // Front facing if true (changed from float VFACE to uint SV_IsFrontFace)
};

// These 'D3DTA' texture argument values
// may be used during each texture stage
struct TextureArgs
{
    float4 CURRENT;
    float4 TEXTURE;
    float4 DIFFUSE;
    float4 SPECULAR;
    float4 TEMP;
    float4 TFACTOR;
};

static float4 TexCoords[4];


bool HasFlag(float value, float flag)
{
	// http://theinstructionlimit.com/encoding-boolean-flags-into-a-float-in-hlsl
    return fmod(value, flag) >= flag / 2;
}

float4 GetArg(float arg, TextureArgs ctx)
{
	// https://docs.microsoft.com/en-us/windows/win32/direct3d9/d3dta
    bool alphaReplicate = HasFlag(arg, X_D3DTA_ALPHAREPLICATE);
    bool complement = HasFlag(arg, X_D3DTA_COMPLEMENT);
    arg = arg % 16;

    float4 o;

    if (arg == X_D3DTA_DIFFUSE)
        o = ctx.DIFFUSE;
    if (arg == X_D3DTA_CURRENT)
        o = ctx.CURRENT;
    if (arg == X_D3DTA_TEXTURE)
        o = ctx.TEXTURE;
    if (arg == X_D3DTA_TFACTOR)
        o = ctx.TFACTOR;
    if (arg == X_D3DTA_SPECULAR)
        o = ctx.SPECULAR;
    if (arg == X_D3DTA_TEMP)
        o = ctx.TEMP;

    if (alphaReplicate)
        return o.aaaa;
    else if (complement)
        return 1 - o;
    else
        return o;
}

float4 ExecuteTextureOp(float op, float4 arg1, float4 arg2, float4 arg0, TextureArgs ctx, PsTextureStageState stage)
{
	// https://docs.microsoft.com/en-us/windows/win32/direct3d9/d3dtextureop

	// Note if we use ifs here instead of else if
	// D3DCompile may stackoverflow at runtime
    if (op == X_D3DTOP_SELECTARG1)
        return arg1;
    else if (op == X_D3DTOP_SELECTARG2)
        return arg2;
    else if (op == X_D3DTOP_MODULATE)
        return arg1 * arg2;
    else if (op == X_D3DTOP_MODULATE2X)
        return 2 * (arg1 * arg2);
    else if (op == X_D3DTOP_MODULATE4X)
        return 4 * (arg1 * arg2);
    else if (op == X_D3DTOP_ADD)
        return arg1 + arg2;
    else if (op == X_D3DTOP_ADDSIGNED)
        return arg1 + arg2 - 0.5;
    else if (op == X_D3DTOP_ADDSIGNED2X)
        return 2 * (arg1 + arg2 - 0.5);
    else if (op == X_D3DTOP_SUBTRACT)
        return arg1 - arg2;
    else if (op == X_D3DTOP_ADDSMOOTH)
        return arg1 + arg2 * (1 - arg1);
    else if (op == X_D3DTOP_BLENDDIFFUSEALPHA)
        return arg1 * ctx.DIFFUSE.a + arg2 * (1 - ctx.DIFFUSE.a);
    else if (op == X_D3DTOP_BLENDCURRENTALPHA)
        return arg1 * ctx.CURRENT.a + arg2 * (1 - ctx.CURRENT.a);
    else if (op == X_D3DTOP_BLENDTEXTUREALPHA)
        return arg1 * ctx.TEXTURE.a + arg2 * (1 - ctx.TEXTURE.a);
    else if (op == X_D3DTOP_BLENDFACTORALPHA)
        return arg1 * ctx.TFACTOR.a + arg2 * (1 - ctx.TFACTOR.a);
    else if (op == X_D3DTOP_BLENDTEXTUREALPHAPM)
        return arg1 + arg2 * (1 - ctx.TEXTURE.a);
    else if (op == X_D3DTOP_PREMODULATE)
        return arg1; // Note this also multiplies the next stage's CURRENT by its texture
    else if (op == X_D3DTOP_MODULATEALPHA_ADDCOLOR)
        return float4(arg1.rgb + arg1.a * arg2.rgb, 1);
    else if (op == X_D3DTOP_MODULATECOLOR_ADDALPHA)
        return float4(arg1.rgb * arg2.rgb + arg1.a, 1);
    else if (op == X_D3DTOP_MODULATEINVALPHA_ADDCOLOR)
        return float4((1 - arg1.a) * arg2.rgb + arg1.rgb, 1);
    else if (op == X_D3DTOP_MODULATEINVCOLOR_ADDALPHA)
        return float4((1 - arg1.rgb) * arg2.rgb + arg1.a, 1);
    else if (op == X_D3DTOP_DOTPRODUCT3)
		// Test case: PerPixelLighting
        return saturate(dot(
			(arg1.rgb - 0.5) * 2,
			(arg2.rgb - 0.5) * 2
		));
	// Note arg0 below is arg1 in D3D docs
	// since it becomes the first argument for operations supporting 3 arguments...
    else if (op == X_D3DTOP_MULTIPLYADD)
        return arg0 + arg1 * arg2;
    else if (op == X_D3DTOP_LERP)
        return arg0 * arg1 + (1 - arg0) * arg2;
    else if (op == X_D3DTOP_BUMPENVMAP)
        return float4(
			arg1.x * stage.BUMPENVMAT00 + arg1.y * stage.BUMPENVMAT10,
			arg1.x * stage.BUMPENVMAT01 + arg1.y * stage.BUMPENVMAT11,
			1, 1);
    else if (op == X_D3DTOP_BUMPENVMAPLUMINANCE)
        return float4(
			arg1.x * stage.BUMPENVMAT00 + arg1.y * stage.BUMPENVMAT10,
			arg1.x * stage.BUMPENVMAT01 + arg1.y * stage.BUMPENVMAT11,
			arg1.z * stage.BUMPENVLSCALE + stage.BUMPENVLOFFSET,
			1);

	// Something is amiss... we should have returned by now!
	// Return a bright colour
    return float4(0, 1, 1, 1);
}

TextureArgs ExecuteTextureStage(
	int i,
	TextureArgs ctx,
	PsTextureHardcodedState s,
	int previousOp,
    int type
)
{
	// Early exit if this stage is disabled (and therefore all further stages are too)
    if (s.COLOROP == X_D3DTOP_DISABLE)
        return ctx;

    //todo all stages support
    PsTextureStageState stage;
    stage.BUMPENVLOFFSET = bumpenvloffset; 
    stage.BUMPENVLSCALE = bumpenvlscale; 
    stage.BUMPENVMAT00 = bumpenvtmat00; 
    stage.BUMPENVMAT01 = bumpenvtmat01;
    stage.BUMPENVMAT11 = bumpenvtmat11;
    stage.BUMPENVMAT10 = bumpenvtmat10;


	// Determine the texture for this stage
    float3 offset = float3(0, 0, 0);
    float4 factor = float4(1, 1, 1, 1);

	// Bumpmap special case
    if (previousOp == X_D3DTOP_BUMPENVMAP ||
		previousOp == X_D3DTOP_BUMPENVMAPLUMINANCE)
    {
		// Assume U, V, L is in CURRENT
		// Add U', V', to the texture coordinates
		// And multiply by L'
		// https://docs.microsoft.com/en-us/windows/win32/direct3d9/bump-mapping-formulas
        offset.xy = ctx.CURRENT.xy;
        factor.rgb = ctx.CURRENT.z;
    }

	// Sample the texture
    float4 t;
    if (type == SAMPLE_NONE)
    {
        //t = 1;
        t = float4(1, 1, 1, 1);
    }
    else if (type == SAMPLE_2D)
    {   
        // Edge bleed fix: Make sure to not read the unwritten border of upscaled render target
        // We guard regular tex, if they get a zero bound, we can keep their negative coordinate and thus their
        //  wrap addressing.
        float2 uv = TexCoords[i].xy + offset.xy;
        const float2 texCoordMin = GetTexCoordMin(i);
        if (texCoordMin.x > 0.0f)
            uv = max(uv, texCoordMin);

        // Extra clamp for FMVs with their aspect ratio set to "fit" while having a high resolution set (4k+).
        const float2 texCoordMax = GetTexCoordMax(i);
        if (texCoordMax.x > 0.0f)
            uv = min(uv, texCoordMax);

        t = g_Texture2DDescriptorHeap[GetTextureStage(i, type)].Sample(g_SamplerDescriptorHeap[GetSamplerState(i)],
        uv);
    }
    else if (type == SAMPLE_3D)
    {
        
        t = g_Texture3DDescriptorHeap[GetTextureStage(i, type)].Sample(g_SamplerDescriptorHeap[GetSamplerState(i)],
        TexCoords[i].xyz + offset.xyz);
    }
    else if (type == SAMPLE_CUBE)
        t = g_TextureCubeDescriptorHeap[GetTextureStage(i, type)].Sample(g_SamplerDescriptorHeap[GetSamplerState(i)],
    TexCoords[i].xyz + offset.xyz);


	// Assign the final value for TEXTURE
    ctx.TEXTURE = t * factor;
    

	// Premodulate special case
    if (previousOp == X_D3DTOP_PREMODULATE)
    {
        ctx.CURRENT *= ctx.TEXTURE;
    }

	// Get arguments for the texture operation
	// Almost all operate on 2 arguments, Arg1 and Arg2
	// Arg0 is a third argument that seems to have been tacked on
	// for MULTIPLYADD and LERP

	// Colour operation arguments
    float4 cArg1 = GetArg(s.COLORARG1, ctx);
    float4 cArg2 = GetArg(s.COLORARG2, ctx);
    float4 cArg0 = GetArg(s.COLORARG0, ctx);

	// Alpha operation arguments
    float4 aArg1 = GetArg(s.ALPHAARG1, ctx);
    float4 aArg2 = GetArg(s.ALPHAARG2, ctx);
    float4 aArg0 = GetArg(s.ALPHAARG0, ctx);
    
	// Execute texture operation
	// ALPHAOP == X_D3DTOP_DISABLE is undefined behaviour
	// Using an intermediate value matches known cases...
    /*static float4 value = 1;
    value.rgb = ExecuteTextureOp(s.COLOROP, cArg1, cArg2, cArg0, ctx, stage).rgb;
    if (s.ALPHAOP != X_D3DTOP_DISABLE)
    {
        value.a = ExecuteTextureOp(s.ALPHAOP, aArg1, aArg2, aArg0, ctx, stage).a;
    }

	// Save the result
	// Note RESULTARG should either be CURRENT or TEMP
	// But some titles seem to set it to DIFFUSE
	// Use CURRENT for anything other than TEMP

    if (s.RESULTARG == X_D3DTA_TEMP)
        ctx.TEMP = value;
    else
        ctx.CURRENT = value;

    return ctx;*/
    
    // Execute texture operation (color + alpha handled separately)
    float4 colorResult = ExecuteTextureOp(s.COLOROP, cArg1, cArg2, cArg0, ctx, stage);

// Determine alpha result:
// - If an explicit alpha op exists, use it.
// - Otherwise, preserve the incoming CURRENT alpha (fixed-function semantics).
    float alphaResult;
    if (s.ALPHAOP != X_D3DTOP_DISABLE)
    {
        float4 alphaResVec = ExecuteTextureOp(s.ALPHAOP, aArg1, aArg2, aArg0, ctx, stage);
        alphaResult = alphaResVec.a;
    }
    else
    {
    // don't take alpha from colorResult; preserve current alpha
        alphaResult = ctx.CURRENT.a;
    }

// Compose the final value for this stage
    float4 value = float4(colorResult.rgb, alphaResult);

// Save the result in TEMP or CURRENT as requested
    if (s.RESULTARG == X_D3DTA_TEMP)
        ctx.TEMP = value;
    else
        ctx.CURRENT = value;
 
    return ctx;
  
}

int DebugStage; // -1 = disabled, 0..3 = return current alpha after that stage
int DebugStageInner; // -1 = disabled, stage index to dump internal args inside ExecuteTextureStage

float4 main(PS_INPUT input) : SV_Target
{

    // Calculate the fog factor
    float fogFactor;


    if (FF_FOG_ENABLE == 0)
    {
        fogFactor = 1;
    }
    else
    {
        if (FF_FOG_TABLE_MODE == FOG_TABLE_NONE)
            fogFactor = input.iFog;
        if (FF_FOG_TABLE_MODE == FOG_TABLE_EXP)
            fogFactor = 1 / exp(input.iFog * FogDensity); // 1 / e^(d * density)
        if (FF_FOG_TABLE_MODE == FOG_TABLE_EXP2)
            fogFactor = 1 / exp(pow(input.iFog * FogDensity, 2)); // 1 / e^((d * density)^2)
        if (FF_FOG_TABLE_MODE == FOG_TABLE_LINEAR)
            fogFactor = (FogEnd - input.iFog) / (FogEnd - FogStart); // (end - d) / (end - start)
        if (FF_FOG_ENABLE == 0)
            fogFactor = 1;
    }
    TexCoords = input.iT;

	// Each stage is passed and returns
	// a set of texture arguments
	// And will usually update the CURRENT value
    TextureArgs ctx;

	// The CURRENT register
	// Default to the diffuse value
	// TODO determine whether to use the front or back colours
	// and set them here
    ctx.CURRENT = input.iD0;
    ctx.DIFFUSE = input.iD0;
    ctx.SPECULAR = input.iD1;
	// The TEMP register
	// Default to 0
    ctx.TEMP = float4(0, 0, 0, 0);
    ctx.TFACTOR = TextureFactor;

#ifdef FIXED_FUNCTION_PIXEL_SHADER_VARIANT
#define FF_SET_STAGE(stage, index) \
    stage.COLOROP = FF_COLOR_OP_##index; \
    stage.COLORARG0 = FF_COLOR_ARG0_##index; \
    stage.COLORARG1 = FF_COLOR_ARG1_##index; \
    stage.COLORARG2 = FF_COLOR_ARG2_##index; \
    stage.ALPHAOP = FF_ALPHA_OP_##index; \
    stage.ALPHAARG0 = FF_ALPHA_ARG0_##index; \
    stage.ALPHAARG1 = FF_ALPHA_ARG1_##index; \
    stage.ALPHAARG2 = FF_ALPHA_ARG2_##index; \
    stage.RESULTARG = FF_RESULT_ARG_##index

#if FF_ACTIVE_STAGE_COUNT_VALUE > 0
    PsTextureHardcodedState stage0;
    FF_SET_STAGE(stage0, 0);
    ctx = ExecuteTextureStage(0, ctx, stage0, -1, FF_TEXTURE_SAMPLE_TYPE_0);
#endif
#if FF_ACTIVE_STAGE_COUNT_VALUE > 1
    PsTextureHardcodedState stage1;
    FF_SET_STAGE(stage1, 1);
    ctx = ExecuteTextureStage(1, ctx, stage1, FF_COLOR_OP_0, FF_TEXTURE_SAMPLE_TYPE_1);
#endif
#if FF_ACTIVE_STAGE_COUNT_VALUE > 2
    PsTextureHardcodedState stage2;
    FF_SET_STAGE(stage2, 2);
    ctx = ExecuteTextureStage(2, ctx, stage2, FF_COLOR_OP_1, FF_TEXTURE_SAMPLE_TYPE_2);
#endif
#if FF_ACTIVE_STAGE_COUNT_VALUE > 3
    PsTextureHardcodedState stage3;
    FF_SET_STAGE(stage3, 3);
    ctx = ExecuteTextureStage(3, ctx, stage3, FF_COLOR_OP_2, FF_TEXTURE_SAMPLE_TYPE_3);
#endif
#undef FF_SET_STAGE
#else
    PsTextureHardcodedState stages[4];
    stages[0].COLOROP = X_D3DTOP_DISABLE;
    stages[1].COLOROP = X_D3DTOP_DISABLE;
    stages[2].COLOROP = X_D3DTOP_DISABLE;
    stages[3].COLOROP = X_D3DTOP_DISABLE;

    stages[0].COLOROP = FF_COLOR_OP_0;
    stages[0].COLORARG0 = FF_COLOR_ARG0_0;
    stages[0].COLORARG1 = FF_COLOR_ARG1_0;
    stages[0].COLORARG2 = FF_COLOR_ARG2_0;
    stages[0].ALPHAOP = FF_ALPHA_OP_0;
    stages[0].ALPHAARG0 = FF_ALPHA_ARG0_0;
    stages[0].ALPHAARG1 = FF_ALPHA_ARG1_0;
    stages[0].ALPHAARG2 = FF_ALPHA_ARG2_0;
    stages[0].RESULTARG = FF_RESULT_ARG_0;

    stages[1].COLOROP = FF_COLOR_OP_1;
    stages[1].COLORARG0 = FF_COLOR_ARG0_1;
    stages[1].COLORARG1 = FF_COLOR_ARG1_1;
    stages[1].COLORARG2 = FF_COLOR_ARG2_1;
    stages[1].ALPHAOP = FF_ALPHA_OP_1;
    stages[1].ALPHAARG0 = FF_ALPHA_ARG0_1;
    stages[1].ALPHAARG1 = FF_ALPHA_ARG1_1;
    stages[1].ALPHAARG2 = FF_ALPHA_ARG2_1;
    stages[1].RESULTARG = FF_RESULT_ARG_1;

    stages[2].COLOROP = FF_COLOR_OP_2;
    stages[2].COLORARG0 = FF_COLOR_ARG0_2;
    stages[2].COLORARG1 = FF_COLOR_ARG1_2;
    stages[2].COLORARG2 = FF_COLOR_ARG2_2;
    stages[2].ALPHAOP = FF_ALPHA_OP_2;
    stages[2].ALPHAARG0 = FF_ALPHA_ARG0_2;
    stages[2].ALPHAARG1 = FF_ALPHA_ARG1_2;
    stages[2].ALPHAARG2 = FF_ALPHA_ARG2_2;
    stages[2].RESULTARG = FF_RESULT_ARG_2;

    stages[3].COLOROP = FF_COLOR_OP_3;
    stages[3].COLORARG0 = FF_COLOR_ARG0_3;
    stages[3].COLORARG1 = FF_COLOR_ARG1_3;
    stages[3].COLORARG2 = FF_COLOR_ARG2_3;
    stages[3].ALPHAOP = FF_ALPHA_OP_3;
    stages[3].ALPHAARG0 = FF_ALPHA_ARG0_3;
    stages[3].ALPHAARG1 = FF_ALPHA_ARG1_3;
    stages[3].ALPHAARG2 = FF_ALPHA_ARG2_3;
    stages[3].RESULTARG = FF_RESULT_ARG_3;

    int sampleTypes[4];
    sampleTypes[0] = FF_TEXTURE_SAMPLE_TYPE_0;
    sampleTypes[1] = FF_TEXTURE_SAMPLE_TYPE_1;
    sampleTypes[2] = FF_TEXTURE_SAMPLE_TYPE_2;
    sampleTypes[3] = FF_TEXTURE_SAMPLE_TYPE_3;

    int previousOp = -1;
    [unroll]
    for (int i = 0; i < 4; i++)
    {
        ctx = ExecuteTextureStage(i, ctx, stages[i], previousOp, sampleTypes[i]);
        previousOp = stages[i].COLOROP;
    }
#endif
    
    

	// Add fog if enabled
    if (FF_FOG_ENABLE)
    {
        float3 fogCOlor_ = float3(FogColor0, FogColor1, FogColor2);
        ctx.CURRENT.rgb = lerp(fogCOlor_.rgb, ctx.CURRENT.rgb, saturate(fogFactor));
    }

	// Add specular if enabled
    if (FF_SPECULAR_ENABLE)
    {
        ctx.CURRENT.rgb += ctx.SPECULAR.rgb;
    }
     
    if (FF_ALPHA_TEST_ENABLE)
    {
        bool passTest = false;
        
        if (FF_ALPHA_FUNC == 1) // D3DCMP_NEVER
            passTest = false;
        else if (FF_ALPHA_FUNC == 2) // D3DCMP_LESS
            passTest = ctx.CURRENT.a < alphaRef;
        else if (FF_ALPHA_FUNC == 3) // D3DCMP_EQUAL
            passTest = abs(ctx.CURRENT.a - alphaRef) < 0.001f;
        else if (FF_ALPHA_FUNC == 4) // D3DCMP_LESSEQUAL
            passTest = ctx.CURRENT.a <= alphaRef;
        else if (FF_ALPHA_FUNC == 5) // D3DCMP_GREATER
            passTest = ctx.CURRENT.a > alphaRef;
        else if (FF_ALPHA_FUNC == 6) // D3DCMP_NOTEQUAL
            passTest = abs(ctx.CURRENT.a - alphaRef) >= 0.001f;
        else if (FF_ALPHA_FUNC == 7) // D3DCMP_GREATEREQUAL
            passTest = ctx.CURRENT.a >= alphaRef;
        else if (FF_ALPHA_FUNC == 8) // D3DCMP_ALWAYS
            passTest = true;
            
        if (!passTest)
            discard;
    }
    

  
    
   return ctx.CURRENT;
}
