#include "common_fixed_vs.hlsli"
#include "fixed_function_vertex_shader/state.hlsli"

static bool vRegisterDefaultFlags[16];

// Input registers
struct VS_INPUT
{
    float4 pos : POSITION;
    float4 bw : BLENDWEIGHT;
    float4 normal : NORMAL;
    float4 color[2] : COLOR;
    float1 fogCoord : FOG;
    float1 pointSize : PSIZE;
    float4 backColor[2] : TEXCOORD4;
    float4 texcoord[4] : TEXCOORD;
    float4 reserved[3] : TEXCOORD6;
};


// Output registers
struct VS_OUTPUT
{
    float4 oPos : SV_Position; // Homogeneous clip space position
    float4 oD0 : COLOR0; // Primary color (front-facing)
    float4 oD1 : COLOR1; // Secondary color (front-facing)
    float oFog : FOG; // Fog coordinate
    float oPts : PSIZE; // Point size
    float4 oB0 : TEXCOORD4; // Back-facing primary color
    float4 oB1 : TEXCOORD5; // Back-facing secondary color
    float4 oT0 : TEXCOORD0; // Texture coordinate set 0
    float4 oT1 : TEXCOORD1; // Texture coordinate set 1
    float4 oT2 : TEXCOORD2; // Texture coordinate set 2
    float4 oT3 : TEXCOORD3; // Texture coordinate set 3
};


float4 Get(const VS_INPUT xIn, const uint index)
{

    // switch statements inexplicably don't work here
    if (index == position)
        return xIn.pos;
    if (index == weight)
        return xIn.bw;
    if (index == normal)
        return xIn.normal;
    if (index == diffuse)
        return xIn.color[0];
    if (index == specular)
        return xIn.color[1];
    if (index == fogCoord)
        return xIn.fogCoord;
    if (index == pointSize)
        return xIn.pointSize;
    if (index == backDiffuse)
        return xIn.backColor[0];
    if (index == backSpecular)
        return xIn.backColor[1];
    if (index == texcoord0)
        return xIn.texcoord[0];
    if (index == texcoord1)
        return xIn.texcoord[1];
    if (index == texcoord2)
        return xIn.texcoord[2];
    if (index == texcoord3)
        return xIn.texcoord[3];
    if (index == reserved0)
        return xIn.reserved[0];
    if (index == reserved1)
        return xIn.reserved[1];
    if (index == reserved2)
        return xIn.reserved[2];
    return 1;
}

struct TransformInfo
{
    float4 Position;
    float3 Normal;
};

static TransformInfo View; // Vertex transformed to viewspace
static TransformInfo Projection; // Vertex transformed to projection space

static const int LIGHT_TYPE_NONE = 0;
static const int LIGHT_TYPE_POINT = 1;
static const int LIGHT_TYPE_SPOT = 2;
static const int LIGHT_TYPE_DIRECTIONAL = 3;

// Final lighting output
struct LightingOutput
{
    TwoSidedColor Diffuse;
    TwoSidedColor Specular;
};


// useful reference https://drivers.amd.com/misc/samples/dx9/FixedFuncShader.pdf
LightingOutput DoLight(const Light l, const float type, const float2 powers)
{
    LightingOutput o;
#if !defined(FIXED_FUNCTION_VERTEX_SHADER_VARIANT) || FFVS_TWO_SIDED_LIGHTING_ENABLE_VALUE
    o.Diffuse.Front.xyz = o.Diffuse.Back.xyz = float3(0, 0, 0);
    o.Specular.Front.xyz = o.Specular.Back.xyz = float3(0, 0, 0);
#else
    o.Diffuse.Front.xyz = float3(0, 0, 0);
    o.Specular.Front.xyz = float3(0, 0, 0);
#endif

    float3 toLight;
    float3 toLightN;
    float attenuation = 1;
    float spotIntensity = 1;
    
	
    if (type == LIGHT_TYPE_DIRECTIONAL)
    {
        toLight = toLightN = -l.DirectionVN.xyz;
    }
    else
    {
        toLight = l.PositionV.xyz - View.Position.xyz;
        toLightN = normalize(toLight);
    }

    if (type == LIGHT_TYPE_SPOT)
    {
		// Spotlight factors
		// https://docs.microsoft.com/en-us/windows/win32/direct3d9/light-types
        float3 toVertexN = -toLightN;
        float cosAlpha = dot(l.DirectionVN.xyz, toVertexN);
		// I = ( cos(a) - cos(phi/2) ) / ( cos(theta/2) - cos(phi/2) )
        float spotBase = saturate((cosAlpha - CosHalfPhi(l)) / SpotIntensityDivisor(l));
        float fallOff = l.Attenuation.w;
        float spotIntensity = pow(spotBase, fallOff);
    }

  
    if (type == LIGHT_TYPE_POINT || type == LIGHT_TYPE_SPOT)
    {
        float lightDist = length(toLight);

		// A(Constant) + A(Linear) * dist + A(Exp) * dist^2
        attenuation =
		1 / (l.Attenuation[0]
			+ l.Attenuation[1] * lightDist
			+ l.Attenuation[2] * lightDist * lightDist);

        float range = l.PositionV.w;
		// Range cutoff
        if (lightDist > range)
            attenuation = 0;
    }


	// Diffuse lighting calculation
    const float NdotLFront = dot(View.Normal, toLightN);
#if !defined(FIXED_FUNCTION_VERTEX_SHADER_VARIANT) || FFVS_TWO_SIDED_LIGHTING_ENABLE_VALUE
    const float NdotLBack = dot(-View.Normal, toLightN);
#endif
    o.Diffuse.Front.xyz = max(NdotLFront, 0) * l.Diffuse.rgb * attenuation * spotIntensity;
#if !defined(FIXED_FUNCTION_VERTEX_SHADER_VARIANT) || FFVS_TWO_SIDED_LIGHTING_ENABLE_VALUE
    o.Diffuse.Back.xyz = max(NdotLBack, 0) * l.Diffuse.rgb * attenuation * spotIntensity;
#endif

	// Note : if X_D3DRS_SPECULARENABLE is false then all light specular colours should have been zeroed out
	// Blinn-Phong
	// https://learnopengl.com/Advanced-Lighting/Advanced-Lighting
#if !defined(FIXED_FUNCTION_VERTEX_SHADER_VARIANT) || FFVS_SPECULAR_ENABLE_VALUE
    float3 toViewerN = FFVS_LOCAL_VIEWER_ENABLE
		? normalize(-View.Position.xyz) // Strip sample
		: float3(0, 0, -1); // DoA 3 character select
    const float3 halfway = normalize(toViewerN + toLightN);
    const float NdotHFront = dot(View.Normal, halfway);
#if !defined(FIXED_FUNCTION_VERTEX_SHADER_VARIANT) || FFVS_TWO_SIDED_LIGHTING_ENABLE_VALUE
    const float NdotHBack = dot(-View.Normal, halfway);
#endif

    o.Specular.Front.xyz = pow(max(NdotHFront, 0), powers[0]) * l.Specular.rgb * attenuation * spotIntensity;
#if !defined(FIXED_FUNCTION_VERTEX_SHADER_VARIANT) || FFVS_TWO_SIDED_LIGHTING_ENABLE_VALUE
    o.Specular.Back.xyz = pow(max(NdotHBack, 0), powers[1]) * l.Specular.rgb * attenuation * spotIntensity;
#endif
#endif

    return o;
}

LightingOutput CalcLighting(const float2 powers)
{
    LightingOutput totalLightOutput;
    totalLightOutput.Diffuse.Front.xyz = float3(0, 0, 0);
#if !defined(FIXED_FUNCTION_VERTEX_SHADER_VARIANT) || FFVS_TWO_SIDED_LIGHTING_ENABLE_VALUE
    totalLightOutput.Diffuse.Back.xyz = float3(0, 0, 0);
#endif
    totalLightOutput.Specular.Front.xyz = float3(0, 0, 0);
#if !defined(FIXED_FUNCTION_VERTEX_SHADER_VARIANT) || FFVS_TWO_SIDED_LIGHTING_ENABLE_VALUE
    totalLightOutput.Specular.Back.xyz = float3(0, 0, 0);
#endif

    
#ifdef FIXED_FUNCTION_VERTEX_SHADER_VARIANT
#define FFVS_ACCUMULATE_LIGHT(index, typeValue) \
    { \
        const Light currentLight = LoadLight(index); \
        const LightingOutput currentLightOutput = DoLight(currentLight, typeValue, powers); \
        totalLightOutput.Diffuse.Front.xyz += currentLightOutput.Diffuse.Front.xyz; \
        totalLightOutput.Specular.Front.xyz += currentLightOutput.Specular.Front.xyz; \
    }
#define FFVS_ACCUMULATE_DIRECTIONAL_LIGHT(index) \
    { \
        const Light currentLight = LoadDirectionalLight(index); \
        const LightingOutput currentLightOutput = DoLight(currentLight, LIGHT_TYPE_DIRECTIONAL, powers); \
        totalLightOutput.Diffuse.Front.xyz += currentLightOutput.Diffuse.Front.xyz; \
        totalLightOutput.Specular.Front.xyz += currentLightOutput.Specular.Front.xyz; \
    }
#if FFVS_LIGHT_TYPE_0_VALUE != 0
    #if FFVS_LIGHT_TYPE_0_VALUE == 3
        FFVS_ACCUMULATE_DIRECTIONAL_LIGHT(0)
    #else
        FFVS_ACCUMULATE_LIGHT(0, FFVS_LIGHT_TYPE_0_VALUE)
    #endif
#endif
#if FFVS_LIGHT_TYPE_1_VALUE != 0
    #if FFVS_LIGHT_TYPE_1_VALUE == 3
        FFVS_ACCUMULATE_DIRECTIONAL_LIGHT(1)
    #else
        FFVS_ACCUMULATE_LIGHT(1, FFVS_LIGHT_TYPE_1_VALUE)
    #endif
#endif
#if FFVS_LIGHT_TYPE_2_VALUE != 0
    #if FFVS_LIGHT_TYPE_2_VALUE == 3
        FFVS_ACCUMULATE_DIRECTIONAL_LIGHT(2)
    #else
        FFVS_ACCUMULATE_LIGHT(2, FFVS_LIGHT_TYPE_2_VALUE)
    #endif
#endif
#if FFVS_LIGHT_TYPE_3_VALUE != 0
    #if FFVS_LIGHT_TYPE_3_VALUE == 3
        FFVS_ACCUMULATE_DIRECTIONAL_LIGHT(3)
    #else
        FFVS_ACCUMULATE_LIGHT(3, FFVS_LIGHT_TYPE_3_VALUE)
    #endif
#endif
#if FFVS_LIGHT_TYPE_4_VALUE != 0
    #if FFVS_LIGHT_TYPE_4_VALUE == 3
        FFVS_ACCUMULATE_DIRECTIONAL_LIGHT(4)
    #else
        FFVS_ACCUMULATE_LIGHT(4, FFVS_LIGHT_TYPE_4_VALUE)
    #endif
#endif
#if FFVS_LIGHT_TYPE_5_VALUE != 0
    #if FFVS_LIGHT_TYPE_5_VALUE == 3
        FFVS_ACCUMULATE_DIRECTIONAL_LIGHT(5)
    #else
        FFVS_ACCUMULATE_LIGHT(5, FFVS_LIGHT_TYPE_5_VALUE)
    #endif
#endif
#if FFVS_LIGHT_TYPE_6_VALUE != 0
    #if FFVS_LIGHT_TYPE_6_VALUE == 3
        FFVS_ACCUMULATE_DIRECTIONAL_LIGHT(6)
    #else
        FFVS_ACCUMULATE_LIGHT(6, FFVS_LIGHT_TYPE_6_VALUE)
    #endif
#endif
#if FFVS_LIGHT_TYPE_7_VALUE != 0
    #if FFVS_LIGHT_TYPE_7_VALUE == 3
        FFVS_ACCUMULATE_DIRECTIONAL_LIGHT(7)
    #else
        FFVS_ACCUMULATE_LIGHT(7, FFVS_LIGHT_TYPE_7_VALUE)
    #endif
#endif
#undef FFVS_ACCUMULATE_LIGHT
#undef FFVS_ACCUMULATE_DIRECTIONAL_LIGHT
#else
    Light Lights_[8];
    FillLightArray(Lights_);

    [unroll]
    for (uint i = 0; i < 8; i++)
    {
        const Light currentLight = Lights_[i];
        float type = FFVS_LIGHT_TYPE(i, currentLight);
        LightingOutput currentLightOutput;

        if (type != LIGHT_TYPE_NONE)
        {
            currentLightOutput = DoLight(currentLight, type, powers);

            totalLightOutput.Diffuse.Front.xyz += currentLightOutput.Diffuse.Front.xyz;
            totalLightOutput.Diffuse.Back.xyz += currentLightOutput.Diffuse.Back.xyz;
            totalLightOutput.Specular.Front.xyz += currentLightOutput.Specular.Front.xyz;
            totalLightOutput.Specular.Back.xyz += currentLightOutput.Specular.Back.xyz;
        }
    }
#endif

    return totalLightOutput;
}

TransformInfo DoTransform(const float4 position, const float3 normal, const float4 blendWeights)
{
    TransformInfo output;
    output.Position = float4(0, 0, 0, 0);
    output.Normal = float3(0, 0, 0);

#ifdef FIXED_FUNCTION_VERTEX_SHADER_VARIANT
#if FFVS_VERTEX_BLEND_MATRIX_COUNT_VALUE == 1 && FFVS_VERTEX_BLEND_CALC_LAST_WEIGHT_VALUE
    const float blendWeight0 = 1;
#else
    const float blendWeight0 = blendWeights[0];
#endif
    output.Position = mul(position, TransfoWorldView(0)) * blendWeight0;
    output.Normal = mul(normal, (float3x3) TransfoWorldViewIT(0)) * blendWeight0;

#if FFVS_VERTEX_BLEND_MATRIX_COUNT_VALUE >= 2
#if FFVS_VERTEX_BLEND_MATRIX_COUNT_VALUE == 2 && FFVS_VERTEX_BLEND_CALC_LAST_WEIGHT_VALUE
    const float blendWeight1 = 1 - blendWeights[0];
#else
    const float blendWeight1 = blendWeights[1];
#endif
    output.Position += mul(position, TransfoWorldView(1)) * blendWeight1;
    output.Normal += mul(normal, (float3x3) TransfoWorldViewIT(1)) * blendWeight1;
#endif

#if FFVS_VERTEX_BLEND_MATRIX_COUNT_VALUE >= 3
#if FFVS_VERTEX_BLEND_MATRIX_COUNT_VALUE == 3 && FFVS_VERTEX_BLEND_CALC_LAST_WEIGHT_VALUE
    const float blendWeight2 = 1 - blendWeights[0] - blendWeights[1];
#else
    const float blendWeight2 = blendWeights[2];
#endif
    output.Position += mul(position, TransfoWorldView(2)) * blendWeight2;
    output.Normal += mul(normal, (float3x3) TransfoWorldViewIT(2)) * blendWeight2;
#endif

#if FFVS_VERTEX_BLEND_MATRIX_COUNT_VALUE >= 4
#if FFVS_VERTEX_BLEND_CALC_LAST_WEIGHT_VALUE
    const float blendWeight3 = 1 - blendWeights[0] - blendWeights[1] - blendWeights[2];
#else
    const float blendWeight3 = blendWeights[3];
#endif
    output.Position += mul(position, TransfoWorldView(3)) * blendWeight3;
    output.Normal += mul(normal, (float3x3) TransfoWorldViewIT(3)) * blendWeight3;
#endif
#else
    const int matrices = FFVS_VERTEX_BLEND_MATRIX_COUNT;
    float lastBlend = 1;
    for (int i = 0; i < matrices; i++)
    {
        // Do we have to calculate the last blend value (never happens when there's already 4 matrices) ?
        const bool bCalcFinalWeight = (FFVS_VERTEX_BLEND_CALC_LAST_WEIGHT > 0) && (i == (matrices - 1));
        // Note : In case of X_D3DVBF_DISABLE, no prior weights have been deducted from lastBlend, so it will still be 1.
        // The number of matrices will also be 1, which effectively turns this into non-weighted single-matrix multiplications :
        const float blendWeight = bCalcFinalWeight ? lastBlend : blendWeights[i];
        // Reduce the blend weight for the final matrix :
        lastBlend -= blendWeights[i];
        // Add this matrix (multiplied by its blend weight) to the output :
        
        
        output.Position += mul(position, TransfoWorldView(i)) * blendWeight;
        output.Normal += mul(normal, (float3x3) TransfoWorldViewIT(i)) * blendWeight;
    }
#endif

    return output;
}

Material DoMaterial(const uint index, const float4 diffuseVertexColour, const float4 specularVertexColour,
    const bool diffuseDefault, const bool specularDefault)
{
    // Get the material from material state
#ifdef FIXED_FUNCTION_VERTEX_SHADER_VARIANT
    Material material = LoadSpecializedMaterial(index);
#else
    Material material = LoadMaterial(index);
#endif

    // Note : if (state.Modes.ColorVertex) no longer required because when disabled, CPU sets all MaterialSource's to D3DMCS_MATERIAL
    {
        // https://docs.microsoft.com/en-us/windows/win32/direct3d9/d3dmaterialcolorsource
        static const int D3DMCS_MATERIAL = 0;
        static const int D3DMCS_COLOR1 = 1;
        static const int D3DMCS_COLOR2 = 2;

        // If COLORVERTEX mode, AND the desired diffuse or specular colour is defined in the vertex declaration
        // Then use the vertex colour instead of the material

        if (!diffuseDefault)
        {
            if (FFVS_AMBIENT_MATERIAL_SOURCE == D3DMCS_COLOR1)
                material.Ambient = diffuseVertexColour;
            if (FFVS_DIFFUSE_MATERIAL_SOURCE == D3DMCS_COLOR1)
                material.Diffuse = diffuseVertexColour;
            if (FFVS_SPECULAR_MATERIAL_SOURCE == D3DMCS_COLOR1)
                material.Specular = diffuseVertexColour;
            if (FFVS_EMISSIVE_MATERIAL_SOURCE == D3DMCS_COLOR1)
                material.Emissive = diffuseVertexColour;
        }

        if (!specularDefault)
        {
            if (FFVS_AMBIENT_MATERIAL_SOURCE == D3DMCS_COLOR2)
                material.Ambient = specularVertexColour;
            if (FFVS_DIFFUSE_MATERIAL_SOURCE == D3DMCS_COLOR2)
                material.Diffuse = specularVertexColour;
            if (FFVS_SPECULAR_MATERIAL_SOURCE == D3DMCS_COLOR2)
                material.Specular = specularVertexColour;
            if (FFVS_EMISSIVE_MATERIAL_SOURCE == D3DMCS_COLOR2)
                material.Emissive = specularVertexColour;
        }
    }

    return material;
}

float DoFog(const VS_INPUT xIn)
{
    if (!FFVS_FOG_ENABLE)
        return 1; // No fog!
    // http://developer.download.nvidia.com/assets/gamedev/docs/Fog2.pdf

    // Obtain the fog depth value 'd'
    float fogDepth;

    if (FFVS_FOG_DEPTH_MODE == FOG_DEPTH_NONE)
        fogDepth = xIn.color[1].a; // In fixed-function mode, fog is passed in the specular alpha
    if (FFVS_FOG_DEPTH_MODE == FOG_DEPTH_RANGE)
        fogDepth = length(View.Position.xyz);
    if (FFVS_FOG_DEPTH_MODE == FOG_DEPTH_Z)
        fogDepth = abs(Projection.Position.z);
    if (FFVS_FOG_DEPTH_MODE == FOG_DEPTH_W)
        fogDepth = Projection.Position.w;
		
    return fogDepth;
}


float4 DoTexCoordResolved(const uint stage, const float4 passthroughTexCoord, const int generation,
    const float componentCount, const bool transformEnabled)
{
    // Texture transform flags
    // https://docs.microsoft.com/en-gb/windows/win32/direct3d9/d3dtexturetransformflags
    static const int D3DTTFF_DISABLE = 0;
    static const int D3DTTFF_COUNT1 = 1;
    static const int D3DTTFF_COUNT2 = 2;
    static const int D3DTTFF_COUNT3 = 3;
    static const int D3DTTFF_COUNT4 = 4;
    static const int D3DTTFF_PROJECTED = 256; // This is the only real flag

    // https://docs.microsoft.com/en-us/windows/win32/direct3d9/d3dtss-tci
    // Pre-shifted
    static const int TCI_PASSTHRU = 0;
    static const int TCI_CAMERASPACENORMAL = 1;
    static const int TCI_CAMERASPACEPOSITION = 2;
    static const int TCI_CAMERASPACEREFLECTIONVECTOR = 3;
    static const int TCI_OBJECT = 4; // Xbox
    static const int TCI_SPHERE = 5; // Xbox

    // Get texture coordinates
    // Coordinates are either from the vertex texcoord data
    // Or generated
    float4 texCoord = float4(0, 0, 0, 0);
    if (generation == TCI_PASSTHRU)
    {
        // Get from vertex data
        texCoord = passthroughTexCoord;

        // Make coordinates homogenous
        // For example, if title supplies (u, v)
        // We need to make transform (u, v, 1) to allow translation with a 3x3 matrix
        // We'll need to get this from the current FVF or VertexDeclaration
        // Test case: Modify pixel shader sample

       // TODO move alongside the texture transformation when it stops angering the HLSL compiler
        if (componentCount == 1)
            texCoord.yzw = float3(0, 0, 1);
        if (componentCount == 2)
            texCoord.zw = float2(1, 1); //testing: was texCoord.zw = float2(0, 1), (setting texCoord.z to 1 fix uv anim)
        if (componentCount == 3)
            texCoord.w = 1;
    } // Generate texture coordinates
    else if (generation == TCI_CAMERASPACENORMAL)
        texCoord = float4(View.Normal, 1);
    else if (generation == TCI_CAMERASPACEPOSITION)
        texCoord = View.Position;
    else
    {
        const float3 reflected = reflect(normalize(View.Position.xyz), View.Normal);

        if (generation == TCI_CAMERASPACEREFLECTIONVECTOR)
            texCoord.xyz = reflected;
        // else if TCI_OBJECT TODO is this just model position?
        else if (generation == TCI_SPHERE)
        {
            // TODO verify
            // http://www.bluevoid.com/opengl/sig99/advanced99/notes/node177.html
            const float3 R = reflected;
            const float p = sqrt(pow(R.x, 2) + pow(R.y, 2) + pow(R.z + 1, 2));
            texCoord.x = R.x / 2 * p + 0.5f;
            texCoord.y = R.y / 2 * p + 0.5f;
        }
    }

    // Transform the texture coordinates if requested
    if (transformEnabled) //issue is likely here
    {
        texCoord = mul(texCoord, TransfoTex(stage));
    }
        //

    // We always send four coordinates
    // If we are supposed to send less than four
    // then copy the last coordinate to the remaining coordinates
    // For D3DTTFF_PROJECTED, the value of the *last* coordinate is important
    // Test case: ProjectedTexture sample, which uses 3 coordinates
    // We'll need to implement the divide when D3D stops handling it for us?
    // https://docs.microsoft.com/en-us/windows/win32/direct3d9/d3dtexturetransformflags
    // padding makes no differences in LLE. LLE works with ProjectedTexture sample without padding, but to be devided by w is necessary.

    return texCoord;
}

#ifndef FIXED_FUNCTION_VERTEX_SHADER_VARIANT
float4 DoTexCoord(const uint stage, const VS_INPUT xIn, const TextureState TextureStates_[4])
{
    const TextureState tState = TextureStates_[stage];
    const int generation = FFVS_TEXCOORD_GENERATION(stage, tState);
    float4 passthroughTexCoord = 0;
    float componentCount = 0;
    if (generation == 0)
    {
        const uint texCoordIndex = abs(FFVS_TEXCOORD_INDEX(stage, tState));
        passthroughTexCoord = Get(xIn, texcoord0 + texCoordIndex);
        componentCount = FFVS_TEXCOORD_COMPONENT_COUNT(stage, texCoordIndex);
    }
    return DoTexCoordResolved(stage, passthroughTexCoord, generation, componentCount,
        FFVS_TEXTURE_TRANSFORM_ENABLE(stage, tState));
}
#endif

// Point size for Point Sprites
// https://docs.microsoft.com/en-us/windows/win32/direct3d9/point-sprites
// Test case: Point sprite sample
float DoPointSpriteSize()
{
#if defined(FIXED_FUNCTION_VERTEX_SHADER_VARIANT) && !FFVS_POINT_SPRITE_ENABLE_VALUE
    return PSRenderUpscaleFactor;
#else
    const PointSprite ps = GetPointSprite();

    float pointSize = ps.PointSize;
    const float A = ps.PointScaleABC.x;
    const float B = ps.PointScaleABC.y;
    const float C = ps.PointScaleABC.z;

    // Note : if (ps.PointScaleEnable) not required because when disabled, CPU sets RenderTargetHeight and PointScale _A to 1, and _B and _C to 0
    if (FFVS_POINT_SCALE_ENABLE)
    {
        const float eyeDistance = length(View.Position);
        const float factor = A + (B * eyeDistance) + (C * (eyeDistance * eyeDistance));

        pointSize *= ps.XboxRenderTargetHeight * sqrt(1 / factor);
    }

    
    return clamp(pointSize, ps.PointSize_Min, ps.PointSize_Max) * SRenderUpscaleFactor(ps);
#endif

}

VS_INPUT InitializeInputRegisters(const VS_INPUT xInput)
{
    VS_INPUT xIn;

#ifdef FIXED_FUNCTION_VERTEX_SHADER_VARIANT
#if FFVS_VERTEX_REGISTER_DEFAULT_MASK_VALUE & (1 << 0)
    xIn.pos = vRegisterDefaultValues(0);
#else
    xIn.pos = xInput.pos;
#endif
#if FFVS_VERTEX_REGISTER_DEFAULT_MASK_VALUE & (1 << 1)
    xIn.bw = vRegisterDefaultValues(1);
#else
    xIn.bw = xInput.bw;
#endif
#if FFVS_VERTEX_REGISTER_DEFAULT_MASK_VALUE & (1 << 2)
    xIn.normal = vRegisterDefaultValues(2);
#else
    xIn.normal = xInput.normal;
#endif
#if FFVS_VERTEX_REGISTER_DEFAULT_MASK_VALUE & (1 << 3)
    xIn.color[0] = vRegisterDefaultValues(3);
#else
    xIn.color[0] = xInput.color[0];
#endif
#if FFVS_VERTEX_REGISTER_DEFAULT_MASK_VALUE & (1 << 4)
    xIn.color[1] = vRegisterDefaultValues(4);
#else
    xIn.color[1] = xInput.color[1];
#endif
#if FFVS_VERTEX_REGISTER_DEFAULT_MASK_VALUE & (1 << 5)
    xIn.fogCoord = vRegisterDefaultValues(5).x;
#else
    xIn.fogCoord = xInput.fogCoord;
#endif
#if FFVS_VERTEX_REGISTER_DEFAULT_MASK_VALUE & (1 << 6)
    xIn.pointSize = vRegisterDefaultValues(6).x;
#else
    xIn.pointSize = xInput.pointSize;
#endif
#if FFVS_VERTEX_REGISTER_DEFAULT_MASK_VALUE & (1 << 7)
    xIn.backColor[0] = vRegisterDefaultValues(7);
#else
    xIn.backColor[0] = xInput.backColor[0];
#endif
#if FFVS_VERTEX_REGISTER_DEFAULT_MASK_VALUE & (1 << 8)
    xIn.backColor[1] = vRegisterDefaultValues(8);
#else
    xIn.backColor[1] = xInput.backColor[1];
#endif
#if FFVS_VERTEX_REGISTER_DEFAULT_MASK_VALUE & (1 << 9)
    xIn.texcoord[0] = vRegisterDefaultValues(9);
#else
    xIn.texcoord[0] = xInput.texcoord[0];
#endif
#if FFVS_VERTEX_REGISTER_DEFAULT_MASK_VALUE & (1 << 10)
    xIn.texcoord[1] = vRegisterDefaultValues(10);
#else
    xIn.texcoord[1] = xInput.texcoord[1];
#endif
#if FFVS_VERTEX_REGISTER_DEFAULT_MASK_VALUE & (1 << 11)
    xIn.texcoord[2] = vRegisterDefaultValues(11);
#else
    xIn.texcoord[2] = xInput.texcoord[2];
#endif
#if FFVS_VERTEX_REGISTER_DEFAULT_MASK_VALUE & (1 << 12)
    xIn.texcoord[3] = vRegisterDefaultValues(12);
#else
    xIn.texcoord[3] = xInput.texcoord[3];
#endif
    xIn.reserved[0] = 0;
    xIn.reserved[1] = 0;
    xIn.reserved[2] = 0;
#else
    // Initialize input registers from the vertex buffer data
    // Or use the register's default value (which can be changed by the title)
    [unroll]
    for (uint i = 0; i < 16; i++)
    {
        const float4 value = lerp(Get(xInput, i), vRegisterDefaultValues(i), FFVS_DEFAULT_REGISTER(i));

            // switch statements inexplicably don't work here
        if (i == position)
            xIn.pos = value;
        if (i == weight)
            xIn.bw = value;
        if (i == normal)
            xIn.normal = value;
        if (i == diffuse)
            xIn.color[0] = value;
        if (i == specular)
            xIn.color[1] = value;
        if (i == fogCoord)
            xIn.fogCoord = value.x; // Note : Untested
        if (i == pointSize)
            xIn.pointSize = value.x; // Note : Untested
        if (i == backDiffuse)
            xIn.backColor[0] = value;
        if (i == backSpecular)
            xIn.backColor[1] = value;
        if (i == texcoord0)
            xIn.texcoord[0] = value;
        if (i == texcoord1)
            xIn.texcoord[1] = value;
        if (i == texcoord2)
            xIn.texcoord[2] = value;
        if (i == texcoord3)
            xIn.texcoord[3] = value;
        if (i == reserved0)
            xIn.reserved[0] = value; // Note : Untested
        if (i == reserved1)
            xIn.reserved[1] = value; // Note : Untested
        if (i == reserved2)
            xIn.reserved[2] = value; // Note : Untested
    }
#endif

    return xIn; // Note : Untested setters are required to avoid "variable 'xIn' used without having been completely initialized" here
}

VS_OUTPUT main(const VS_INPUT xInput)
{
    
    VS_OUTPUT xOut;

    // Unpack 16 bool flags from 4 float4 constant registers
#ifndef FIXED_FUNCTION_VERTEX_SHADER_VARIANT
    UnpackRegisterDefaultFlags(vRegisterDefaultFlags);
#endif

    // TODO make sure this goes fast

    // Map default values
    VS_INPUT xIn = InitializeInputRegisters(xInput);
    

     // World + View transform with vertex blending
    View = DoTransform(xIn.pos, xIn.normal.xyz, xIn.bw);
    
    // Optionally normalize camera-space normals
    if (FFVS_NORMALIZE_NORMALS_ENABLE)
        View.Normal = normalize(View.Normal);
    
 
    
    // Projection transform
    Projection.Position = mul(View.Position, TransfoProj);
    // Normal unused...

    // Projection transform - final position
    xOut.oPos = Projection.Position;

    // Diffuse and specular for when lighting is disabled
    xOut.oD0 = xIn.color[0];
    xOut.oD1 = xIn.color[1];
    xOut.oB0 = xIn.backColor[0];
    xOut.oB1 = xIn.backColor[1];
    
    
  
    // Vertex lighting
    if (FFVS_LIGHTING_ENABLE) // TODO : Remove this check by incorporating this boolean into the variables used below (set DiffuseMaterialSource to D3DMCS_COLOR1, SpecularMaterialSource to D3DMCS_COLOR2, all other to D3DMCS_MATERIAL and their colors and TotalLightsAmbient to zero, etc)
    {
        // Materials
        Material material = DoMaterial(0, xIn.color[0], xIn.color[1],
            FFVS_DEFAULT_REGISTER(diffuse), FFVS_DEFAULT_REGISTER(specular));
#if !defined(FIXED_FUNCTION_VERTEX_SHADER_VARIANT) || FFVS_TWO_SIDED_LIGHTING_ENABLE_VALUE
        Material backMaterial = DoMaterial(1, xIn.backColor[0], xIn.backColor[1],
            FFVS_DEFAULT_REGISTER(backDiffuse), FFVS_DEFAULT_REGISTER(backSpecular));
#endif

        // Compute each lighting component
#if !defined(FIXED_FUNCTION_VERTEX_SHADER_VARIANT) || FFVS_SPECULAR_ENABLE_VALUE
#if !defined(FIXED_FUNCTION_VERTEX_SHADER_VARIANT) || FFVS_TWO_SIDED_LIGHTING_ENABLE_VALUE
        const float2 powers = float2(material.Power.x, backMaterial.Power.x);
#else
        const float2 powers = material.Power.xx;
#endif
#else
        const float2 powers = 0;
#endif
        const LightingOutput lighting = CalcLighting(powers);

        // Frontface
        material.Specular.rgb *= lighting.Specular.Front.xyz;
        material.Diffuse.rgb *= lighting.Diffuse.Front.xyz;
        material.Ambient.rgb *= TLightColorFront.xyz;
        xOut.oD0 = float4(material.Diffuse.rgb + material.Ambient.rgb + material.Emissive.rgb, material.Diffuse.a);
        xOut.oD1 = float4(material.Specular.rgb, 0);

#if !defined(FIXED_FUNCTION_VERTEX_SHADER_VARIANT) || FFVS_TWO_SIDED_LIGHTING_ENABLE_VALUE
        if (FFVS_TWO_SIDED_LIGHTING_ENABLE) // TODO : Same as above, for backface lighting variables
        {
            // Backface
            backMaterial.Specular.rgb *= lighting.Specular.Back.xyz;
            backMaterial.Diffuse.rgb *= lighting.Diffuse.Back.xyz;
            backMaterial.Ambient.rgb *= TLightColorBack.xyz;
            xOut.oB0 = float4(backMaterial.Diffuse.rgb + backMaterial.Ambient.rgb + backMaterial.Emissive.rgb, backMaterial.Diffuse.a);
            xOut.oB1 = float4(backMaterial.Specular.rgb, 0);
        }
#endif
    }

    // Colour
    xOut.oD0 = saturate(xOut.oD0);
    xOut.oD1 = saturate(xOut.oD1);
    xOut.oB0 = saturate(xOut.oB0);
    xOut.oB1 = saturate(xOut.oB1);

    // Fog
    xOut.oFog = DoFog(xIn);

    // Point Sprite
    xOut.oPts = DoPointSpriteSize();

    // Texture coordinates
#ifdef FIXED_FUNCTION_VERTEX_SHADER_VARIANT
    xOut.oT0 = DoTexCoordResolved(0, xIn.texcoord[FFVS_TEXCOORD_INDEX_0_VALUE],
        FFVS_TEXCOORD_GENERATION_0_VALUE, FFVS_TEXCOORD_COMPONENT_COUNT_0_VALUE,
        FFVS_TEXTURE_TRANSFORM_ENABLE_0_VALUE) / xboxTextureScale(0);
    xOut.oT1 = DoTexCoordResolved(1, xIn.texcoord[FFVS_TEXCOORD_INDEX_1_VALUE],
        FFVS_TEXCOORD_GENERATION_1_VALUE, FFVS_TEXCOORD_COMPONENT_COUNT_1_VALUE,
        FFVS_TEXTURE_TRANSFORM_ENABLE_1_VALUE) / xboxTextureScale(1);
    xOut.oT2 = DoTexCoordResolved(2, xIn.texcoord[FFVS_TEXCOORD_INDEX_2_VALUE],
        FFVS_TEXCOORD_GENERATION_2_VALUE, FFVS_TEXCOORD_COMPONENT_COUNT_2_VALUE,
        FFVS_TEXTURE_TRANSFORM_ENABLE_2_VALUE) / xboxTextureScale(2);
    xOut.oT3 = DoTexCoordResolved(3, xIn.texcoord[FFVS_TEXCOORD_INDEX_3_VALUE],
        FFVS_TEXCOORD_GENERATION_3_VALUE, FFVS_TEXCOORD_COMPONENT_COUNT_3_VALUE,
        FFVS_TEXTURE_TRANSFORM_ENABLE_3_VALUE) / xboxTextureScale(3);
#else
    TextureState texArray[4];
    FillTextureStateArray(texArray);
    xOut.oT0 = DoTexCoord(0, xIn, texArray) / xboxTextureScale(0);
    xOut.oT1 = DoTexCoord(1, xIn, texArray) / xboxTextureScale(1);
    xOut.oT2 = DoTexCoord(2, xIn, texArray) / xboxTextureScale(2);
    xOut.oT3 = DoTexCoord(3, xIn, texArray) / xboxTextureScale(3);
#endif




    return xOut;
}



/*struct VS_INPUT
{
    float4 position : POSITION;
    float4 color : COLOR;
    float4 texcoord : TEXCOORD0;
};

struct VS_OUTPUT
{
    float4 position : SV_Position;
    float4 color : COLOR0;
    float4 texcoord : TEXCOORD0;
};

VS_OUTPUT main(VS_INPUT input)
{
    VS_OUTPUT output;
    
    // Pass position directly through - already in clip space
    output.position = input.position;
    
    // Pass color through
    output.color = input.color;
    
    // Pass texcoord through
    output.texcoord = input.texcoord;
    
    return output;
}*/
