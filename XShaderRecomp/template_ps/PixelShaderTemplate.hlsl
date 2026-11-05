
// Source register modifier macro's, based on enum PS_INPUTMAPPING :
// TODO : Should all these 'max(0, x)' actually be 'saturate(x)'? This, because the operation may actually clamp the register value to the range [0..1]
#define s_sat(x)         saturate(x)        // PS_INPUTMAPPING_UNSIGNED_IDENTITY= 0x00L, // OK for final combiner      // Clamps negative x to 0 // Was : max(0, x), then abs(x) (Test case: Scaler)
#define s_comp(x)   (1 - saturate(x))       // PS_INPUTMAPPING_UNSIGNED_INVERT=   0x20L, // OK for final combiner      // Complements x (1-x)    // Was : 1- min(max(0, x), 1)
#define s_bx2(x)    (( 2 * max(0, x)) - 1)  // PS_INPUTMAPPING_EXPAND_NORMAL=     0x40L, // invalid for final combiner // Shifts range from [0..1] to [-1..1]
#define s_negbx2(x) ((-2 * max(0, x)) + 1)  // PS_INPUTMAPPING_EXPAND_NEGATE=     0x60L, // invalid for final combiner // Shifts range from [0..1] to [-1..1] and then negates
#define s_bias(x)         (max(0, x) - 0.5) // PS_INPUTMAPPING_HALFBIAS_NORMAL=   0x80L, // invalid for final combiner // Clamps negative x to 0 and then subtracts 0.5
#define s_negbias(x)     (-max(0, x) + 0.5) // PS_INPUTMAPPING_HALFBIAS_NEGATE=   0xa0L, // invalid for final combiner // Clamps negative x to 0, subtracts 0.5, and then negates
#define s_ident(x)                x         // PS_INPUTMAPPING_SIGNED_IDENTITY=   0xc0L, // invalid for final combiner // No modifier, x is passed without alteration
#define s_neg(x)                (-x)        // PS_INPUTMAPPING_SIGNED_NEGATE=     0xe0L, // invalid for final combiner // Negate

// Destination register modifier macro's, based on enum PS_COMBINEROUTPUT :
#define d_ident(x) x              // PS_COMBINEROUTPUT_IDENTITY=            0x00L, // 
#define d_bias(x) (x - 0.5)       // PS_COMBINEROUTPUT_BIAS=                0x08L, // Subtracts 0.5 from outputs
#define d_x2(x)  ( x        * 2)  // PS_COMBINEROUTPUT_SHIFTLEFT_1=         0x10L, // Scales outputs by 2
#define d_bx2(x) ((x - 0.5) * 2)  // PS_COMBINEROUTPUT_SHIFTLEFT_1_BIAS=    0x18L, // Subtracts 0.5 from outputs and scales by 2
#define d_x4(x)  ( x        * 4)  // PS_COMBINEROUTPUT_SHIFTLEFT_2=         0x20L, // Scales outputs by 4
#define d_bx4(x) ((x - 0.5) * 4)  // PS_COMBINEROUTPUT_SHIFTLEFT_2_BIAS=    0x28L, // Subtracts 0.5 from outputs and scales by 4
#define d_d2(x)  ( x        / 2)  // PS_COMBINEROUTPUT_SHIFTRIGHT_1=        0x30L, // Divides outputs by 2
#define d_bd2(x) ((x - 0.5) / 2)  // PS_COMBINEROUTPUT_SHIFTRIGHT_1_BIAS=   0x38L, // Subtracts 0.5 from outputs and divides by 2


#ifdef __spirv__

struct PushConstants
{
    uint64_t VertexShaderConstants;
    uint64_t PixelShaderConstants;
    uint64_t SharedConstants;
};

[[vk::push_constant]] ConstantBuffer<PushConstants> g_PushConstants;

// Sewer note: Read 16-byte aligned for perf.
#define REGISTER_ALIGNMENT 16
#define SC_REG_U(cN) vk::RawBufferLoad<uint4>(g_PushConstants.SharedConstants + (cN) * 16, REGISTER_ALIGNMENT)
#define SC_REG_F(cN) vk::RawBufferLoad<float4>(g_PushConstants.SharedConstants + (cN) * 16, REGISTER_ALIGNMENT)
#define PC_REG_F(cN) vk::RawBufferLoad<float4>(g_PushConstants.PixelShaderConstants + (cN) * 16, REGISTER_ALIGNMENT)

#define texture2D_0   SC_REG_U(0).x
#define texture2D_1   SC_REG_U(0).y
#define texture2D_2   SC_REG_U(0).z
#define texture2D_3   SC_REG_U(0).w

#define texture3D_0   SC_REG_U(4).x

#define textureCube_0 SC_REG_U(8).x

// two stages per register: stage i is at element (i >> 1), .xy for even, .zw for odd.
#define texCoordMin_(i) SC_REG_F(89 + (i))

#define sampler_0  SC_REG_U(12).x
#define sampler_1  SC_REG_U(12).y
#define sampler_2  SC_REG_U(12).z
#define sampler_3  SC_REG_U(12).w

#define c0_(i) PC_REG_F(0 + (i))
#define c1_(i) PC_REG_F(8 + (i))

#define FC0  PC_REG_F(16)
#define FC1  PC_REG_F(17)
#define c_fog  PC_REG_F(18)

#define BEM(i) PC_REG_F(19 + (i))
#define LUM(i) PC_REG_F(23 + (i))

#define FRONTFACE_FACTOR PC_REG_F(27)
#define FOGINFO  PC_REG_F(28)
#define FOGENABLE PC_REG_F(29)



#else

cbuffer PixelShaderConstants : register(b1, space4)
{
    // Constant registers
    float4 c0__[8] : packoffset(c0);
    float4 c1__[8] : packoffset(c8);
    
    // Constant registers used only in final combiner stage (xfc 'opcode'):
    float4 FC0_ : packoffset(c16); // Note : Maps to PSH_XBOX_CONSTANT_FC0, must be generated as argument to xfc instead of C0
    float4 FC1_ : packoffset(c17); // Note : Maps to PSH_XBOX_CONSTANT_FC1, must be generated as argument to xfc instead of C1
    
    // other
    float4 c_fog_ : packoffset(c18); // Note : Maps to PSH_XBOX_CONSTANT_FOG, assigned to fog.rgb

    // Constant registers used only in final combiner stage (part 2):
    float4 BEM_[4] : packoffset(c19); // Note : PSH_XBOX_CONSTANT_BEM for 4 texture stages
    float4 LUM_[4] : packoffset(c23); // Note : PSH_XBOX_CONSTANT_LUM for 4 texture stages
    float4 FRONTFACE_FACTOR_ : packoffset(c27); // Note : PSH_XBOX_CONSTANT_LUM for 4 texture stages
    float4 FOGINFO_ : packoffset(c28);
    float4 FOGENABLE_ : packoffset(c29);
    
}


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
    
    float4 texCoordMin__[8] : packoffset(c89);

};

#define texCoordMin_(i) texCoordMin__[i]
#define c0_(i) c0__[i]
#define c1_(i) c1__[i]

#define FC0  FC0_
#define FC1  FC1_
#define c_fog c_fog_

#define BEM(i) BEM_[i]
#define LUM(i) LUM_[i]

#define FRONTFACE_FACTOR FRONTFACE_FACTOR_
#define FOGINFO FOGINFO_
#define FOGENABLE FOGENABLE_

#endif

uint GetTextureStage(uint slot, uint type)
{
    switch (type)
    {
        case 1:
        default:
            if (slot == 0)
                return texture2D_0;
            else if (slot == 1)
                return texture2D_1;
            else if (slot == 2)
                return texture2D_2;
            else if (slot == 3)
                return texture2D_3;
            break;
        case 2:
            return texture3D_0;
        case 3:
            return textureCube_0;
    }
    
    return texture2D_0;
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



#define CM_LT(c) if(c < 0) clip(-1); // = PS_COMPAREMODE_[RSTQ]_LT
#define CM_GE(c) if(c >= 0) clip(-1); // = PS_COMPAREMODE_[RSTQ]_GE


	// Hardcoded state will be inserted here
    // <HARDCODED STATE GOES HERE>
	// End hardcoded state

// PS_COMBINERCOUNT_UNIQUE_C0 steers whether for C0 to use combiner stage-specific constants c0_0 .. c0_7, or c0_0 for all stages
#ifdef PS_COMBINERCOUNT_UNIQUE_C0
#define C0 c0_(stage) // concatenate stage to form c0_0 .. c0_7
#else // PS_COMBINERCOUNT_SAME_C0
#define C0 c0_(0) // always resolve to c0_0
#endif

// PS_COMBINERCOUNT_UNIQUE_C1 steers whether for C1 to use combiner stage-specific constants c1_0 .. c1_7, or c1_0 for all stages
#ifdef PS_COMBINERCOUNT_UNIQUE_C1
#define C1 c1_(stage) // concatenate stage to form c1_0 .. c1_7
#else // PS_COMBINERCOUNT_SAME_C1
#define C1 c1_(0) // always resolve to c1_0
#endif

// PS_COMBINERCOUNT_MUX_MSB steers the 'muxing' operation in the XMMC opcode,
// checking either the Most Significant Bit (MSB) or Least (LSB) of the r0 register.
// (In practice, LSB is seldom encountered, we have zero known test-cases.)
#ifdef PS_COMBINERCOUNT_MUX_MSB
#define FCS_MUX (r0.a >= 0.5) // Check r0.a MSB; Having range upto 1 this should be equal to : (((r0.a * 255) /*mod 256*/) >= 128)
#else // PS_COMBINERCOUNT_MUX_LSB
#define FCS_MUX (((r0.a * 255) % 2) >= 1) // Check r0.b LSB; Get LSB by converting 1 into 255 (highest 8-bit value) and using modulo 2. TODO : Verify correctness
#endif

// PS_FINALCOMBINERSETTING_COMPLEMENT_V1, when defined, applies a modifier to the v1 input when calculating the sum register
#ifdef PS_FINALCOMBINERSETTING_COMPLEMENT_V1
#define FCS_V1 s_comp // making it use 1-complement,
#else
#define FCS_V1 s_ident // otherwise identity mapping.
#endif

// PS_FINALCOMBINERSETTING_COMPLEMENT_R0, when defined, applies a modifier to the r0 input when calculating the sum register
#ifdef PS_FINALCOMBINERSETTING_COMPLEMENT_R0
#define FCS_R0 s_comp // making it use 1-complement,
#else
#define FCS_R0 s_ident // otherwise identity mapping.
#endif

// PS_FINALCOMBINERSETTING_CLAMP_SUM, when defined, applies a modifier to the sum register
#ifdef PS_FINALCOMBINERSETTING_CLAMP_SUM
#define FCS_SUM s_sat // making it clamp negative to zero,
#else
#define FCS_SUM s_ident // otherwise identity mapping. TODO : Confirm correctness
#endif

#define xdot(s0, s1) dot((s0).rgb, (s1).rgb)

// Xbox supports only one 'pixel shader' opcode, but bit flags tunes it's function;
// Here, effective all 5 Xbox opcodes, extended with a variable macro {xop_m(m,...)} for destination modifier :
// Note : Since both d0 AND d1 could be the same output register, calculation of d2 can re-use only one (d0 or d1)
#define xmma(d0, d1, d2,  s0, s1, s2, s3, m, tmp) tmp = d0 = m(s0 * s1); d1 = m(s2 * s3); d2 =           d1 + tmp // PS_COMBINEROUTPUT_AB_CD_SUM=           0x00L, // 3rd output is AB+CD
#define xmmc(d0, d1, d2,  s0, s1, s2, s3, m, tmp) tmp = d0 = m(s0 * s1); d1 = m(s2 * s3); d2 = FCS_MUX ? d1 : tmp // PS_COMBINEROUTPUT_AB_CD_MUX=           0x04L, // 3rd output is MUX(AB,CD) based on R0.a

#define xdm(d0, d1,  s0, s1, s2, s3, m) d0 = m(xdot(s0 , s1)); d1 = m(     s2 * s3 )                              // PS_COMBINEROUTPUT_AB_DOT_PRODUCT=      0x02L, // RGB only // PS_COMBINEROUTPUT_CD_MULTIPLY=         0x00L,
#define xdd(d0, d1,  s0, s1, s2, s3, m) d0 = m(xdot(s0 , s1)); d1 = m(xdot(s2 , s3))                              // PS_COMBINEROUTPUT_CD_DOT_PRODUCT=      0x01L, // RGB only // PS_COMBINEROUTPUT_AB_MULTIPLY=         0x00L, 
#define xmd(d0, d1,  s0, s1, s2, s3, m) d0 = m(     s0 * s1 ); d1 = m(xdot(s2 , s3))                              // PS_COMBINEROUTPUT_AB_DOT_PRODUCT=      0x02L, // RGB only // PS_COMBINEROUTPUT_CD_MULTIPLY=         0x01L,

// After the register combiner stages, there's one (optional) final combiner step, consisting of 4 parts;
// All the 7 final combiner inputs operate on rgb only and clamp negative input to zero:
#define fcin(r) saturate(r)
// Special purpose registers prod and sum operate on rgb only, and have alpha set to zero
#define xfc_sum sum = FCS_SUM(float4(FCS_V1(fcin(v1.rgb)) + FCS_R0(fcin(r0.rgb)), 0)) // Note : perform sum first, so prod can use its result
#define xfc_prod(e, f) prod = float4(fcin(e) * fcin(f), 0) // Note : prod can't have modifiers
// Color and Alpha calculations are performed, potentially using sum and/or prod and/or fog registers
#define xfc_rgb(a, b, c, d) r0.rgb = lerp(fcin(c), fcin(b), fcin(a)) + fcin(d) // Note : perform rgb and alpha last, so prod and sum can be used as inputs
#define xfc_alpha(g) r0.a = fcin(g)

// Glue them all together, so we can generate a one-liner closing off the stages :
#define xfc(a, b, c, d, e, f, g) xfc_sum; xfc_prod(e, f); xfc_rgb(a, b, c, d); xfc_alpha(g)
// Note : If xfc is not generated (when PSFinalCombinerInputsABCD and PSFinalCombinerEFG are both 0), r0.rgba is still returned as pixel shader output

// GLSL : https://www.khronos.org/registry/OpenGL-Refpages/gl4/html/mix.xhtml
//  mix(x,  y,  a )  x*(1-a ) +  y*a
// 
// HLSL : https://docs.microsoft.com/en-us/windows/win32/direct3dhlsl/dx-graphics-hlsl-lerp
// lerp(x,  y,  s )  x*(1-s ) +  y*s == x + s(y-x)
// lerp(s2, s1, s0) s2*(1-s0) + s1*s0

float m21d(const float input)
{
    int tmp = (int) (input * 255); // Convert float 0..1 into byte 0..255
    tmp -= 128; // 0 lowers to -128, 128 lowers to 0, 255 lowers to 127
    return (float) tmp / 127; // -128 scales to -1.007874016, 0 scales to 0.0, 127 scales to 1.0
}

float m21g(const float input)
{
    int tmp = (int) (input * 255); // Convert float 0..1 into byte 0..255
    if (tmp >= 128)
    {
        tmp -= 256; // 128 lowers to -128, 255 lowers to -1
    } // 0 stays 0, 127 stays 127

    return ((float) tmp + 0.5) / 127.5;
}

float m21(const float input)
{
    int tmp = (int) (input * 255); // Convert float 0..1 into byte 0..255
    if (tmp >= 128)
    {
        tmp -= 256; // 128 lowers to -128, 255 lowers to -1
    } // 0 stays 0, 127 stays 127

    return (float) tmp / 127; // -128 scales to -1.007874016, 0 scales to 0.0, 127 scales to 1.0
}

float hls(float input) // 0..65535 range
{
    float tmp = (float) (input);
    tmp = (input < 32768) ? tmp / 32767 : (tmp - 65536) / 32767; // -1..1
    return (float) tmp;
}

float hlu(float input) // 0..65535 range
{
    return (float) input / 65535; // 0..1
}

float p2(float input) // power of 2
{
    return input * input;
}

// Note : each component seems already in range [0..1], but two must be combined into one
             
#define TwoIntoOne(a,b) (((a * 256) + b) * 255) 
#define CalcHiLo(in) H = TwoIntoOne(in.x, in.y); L = TwoIntoOne(in.z, in.w) // TODO : Verify whether this works at all !


// Dot mappings over the output value of a (4 component 8 bit unsigned) texture stage register into a (3 component float) vector value, for use in a dot product calculation:
#define PS_DOTMAPPING_ZERO_TO_ONE(in)         dm = in.rgb                                          // :r8g8b8a8->(r,g,b):                                                   0x00=>0,                       0xff=>1 thus : output =                     (input / 0xff  )
#define PS_DOTMAPPING_MINUS1_TO_1_D3D(in)     dm = float3(m21d(in.x), m21d(in.y), m21d(in.z))      // :r8g8b8a8->(r,g,b):               0x00=>-128/127,         0x01=>-1,   0x80=>0,                       0xff=>1 thus : output =                                        ((input - 0x100  ) / 0x7f  )
#define PS_DOTMAPPING_MINUS1_TO_1_GL(in)      dm = float3(m21g(in.x), m21g(in.y), m21g(in.z))      // :r8g8b8a8->(r,g,b):                                       0x80=>-1,   0x00=>0,                       0x7f=>1 thus : output =  (input < 0x80  ) ? (input / 0x7f  ) : ((input - 0x100  ) / 0x80  ) (see https://en.wikipedia.org/wiki/Two's_complement)
#define PS_DOTMAPPING_MINUS1_TO_1(in)         dm = float3(m21( in.x), m21( in.y), m21( in.z))      // :r8g8b8a8->(r,g,b):               0x80=>-128/127,        ?0x81=>-1,   0x00=>0,                       0x7f=>1 thus : output =  (input < 0x80  ) ? (input / 0x7f  ) : ((input - 0x100  ) / 0x7f  ) (see https://en.wikipedia.org/wiki/Two's_complement)

#define PS_DOTMAPPING_HILO_1(in)              CalcHiLo(in); dm = float3(hlu(H), hlu(L), 1)                   // :H16L16  ->(H,L,1):                                                 0x0000=>0,                     0xffff=>1 thus : output =                     (input / 0xffff)
#define PS_DOTMAPPING_HILO_HEMISPHERE_D3D(in) CalcHiLo(in); dm = float3(hls(H), hls(L), sqrt(1-p2(H)-p2(L))) // :H16L16  ->(H,L,sqrt(1-H^2-L^2)):?                      0x8000=>-1, 0x0000=>0, 0x7fff=32767/32768            thus : output =                                        ((input - 0x10000) / 0x7fff)
#define PS_DOTMAPPING_HILO_HEMISPHERE_GL(in)  CalcHiLo(in); dm = float3(hls(H), hls(L), sqrt(1-p2(H)-p2(L))) // :H16L16  ->(H,L,sqrt(1-H^2-L^2)):?                      0x8000=>-1, 0x0000=>0,                     0x7fff=>1 thus : output =  (input < 0x8000) ? (input / 0x7fff) : ((input - 0x10000) / 0x8000)
#define PS_DOTMAPPING_HILO_HEMISPHERE(in)     CalcHiLo(in); dm = float3(hls(H), hls(L), sqrt(1-p2(H)-p2(L))) // :H16L16  ->(H,L,sqrt(1-H^2-L^2)): 0x8000=>-32768/32767, 0x8001=>-1, 0x0000=>0,                     0x7fff=>1 thus : output =  (input < 0x8000) ? (input / 0x7fff) : ((input - 0x10000) / 0x7fff)

// Declare one sampler per each {Sampler Type, Texture Stage} combination

Texture2D<float4> g_Texture2DDescriptorHeap[] : register(t0, space0);
Texture3D<float4> g_Texture3DDescriptorHeap[] : register(t0, space1);
TextureCube<float4> g_TextureCubeDescriptorHeap[] : register(t0, space2);
SamplerState g_SamplerDescriptorHeap[] : register(s0, space3);

// Declare alphakill as a variable (avoiding a constant, to allow false's to be optimized away) :
#ifndef ALPHAKILL
#define ALPHAKILL {false, false, false, false}
#endif
static bool alphakill[4] = ALPHAKILL;

float4 PostProcessTexel(const int ts, float4 t)
{
    if (alphakill[ts])
        if (t.a == 0)
            discard;

    return t;
}

// Edge bleed fix
// Smallest texture coordinate that is safe to sample for this stage
// Those are not null only for RT that have the RT edge bleed (garbage data top left)
// see texCoordMin in SharedConstants struct on the CPU side

float2 GetTexCoordMin(uint slot)
{
    float4 packed = texCoordMin_(slot >> 1);
    return (slot & 1) ? packed.zw : packed.xy;
}

// Actual texture sampling per texture stage (ts), using the sampling vector (s) as input,
// abstracting away the specifics of accessing above sampler declarations (usefull for future Direct3D 10+ sampler arrays)
float4 Sample2D(int ts, float3 s)
{
    // Edge bleed fix: Make sure to not read the unwritten border of upscaled render target
    // We guard regular tex, if they get a zero bound, we can keep their negative coordinate and thus their wrap addressing.
    const float2 texCoordMin = GetTexCoordMin(ts);
    if (texCoordMin.x > 0.0f)
        s.xy = max(s.xy, texCoordMin);
        
    float4 result = g_Texture2DDescriptorHeap[GetTextureStage(ts, 1)].Sample(g_SamplerDescriptorHeap[GetSamplerState(ts)], s.xy); // Ignores s.z (and whatever it's set to, will be optimized away by the compiler, see [1] below)
    return PostProcessTexel(ts, result);
}

float4 Sample3D(int ts, float3 s)
{
    float4 result = g_Texture3DDescriptorHeap[GetTextureStage(ts, 2)].Sample(g_SamplerDescriptorHeap[GetSamplerState(ts)], s.xyz);
    return PostProcessTexel(ts, result);
}

float4 Sample6F(int ts, float3 s)
{
    float4 result = g_TextureCubeDescriptorHeap[GetTextureStage(ts, 3)].Sample(g_SamplerDescriptorHeap[GetSamplerState(ts)], s.xyz);
    return PostProcessTexel(ts, result);
}


float3 DoBumpEnv(const float4 TexCoord, const float4 BumpEnvMat, const float4 src)
{
	// Convert the input bump map (source texture) value range into two's complement signed values (from (0, +1) to (-1, +1), using s_bx2):
    const float4 BumpMap = s_bx2(src); // Note : medieval discovered s_bias improved JSRF, PatrickvL changed it into s_bx2 thanks to http://www.rastertek.com/dx11tut20.html
	// TODO : The above should be removed, and replaced by some form of COLORSIGN handling, which may not be possible inside this pixel shader, because filtering-during-sampling would cause artifacts.

    const float u = TexCoord.x + (BumpEnvMat.x * BumpMap.r) + (BumpEnvMat.z * BumpMap.g); // Or : TexCoord.x + dot(BumpEnvMat.xz, BumpMap.rg)
    const float v = TexCoord.y + (BumpEnvMat.y * BumpMap.r) + (BumpEnvMat.w * BumpMap.g); // Or : TexCoord.y + dot(BumpEnvMat.yw, BumpMap.rg)

    return float3(u, v, 0);
}

// Map texture registers to their array elements. Having texture registers in an array allows indexed access to them
#define t0 t[0]
#define t1 t[1]
#define t2 t[2]
#define t3 t[3]

// Resolve a stage number via 'input texture (index) mapping' to it's corresponding output texture register (rgba?)
#define src(ts) t[PS_INPUTTEXTURE_[ts]]

// Calculate the dot result for a given texture stage. Since any given stage is input-mapped to always be less than or equal the stage it appears in, this won't cause read-ahead issues
// Test case: BumpDemo demo
#define CalcDot(ts) PS_DOTMAPPING_ ## ts(src(ts)); dot_[ts] = dot(iT[ts].xyz, dm)

// Addressing operations

// Clamps input texture coordinates to the range [0..1]
// Note alpha is passed through rather than set to one like ps_1_3 'texcoord'
// Test case: Metal Arms (menu skybox clouds, alpha is specifically set in the VS)
#define Passthru(ts)  float4(saturate(iT[ts]))
#define Brdf(ts)      float3(t[ts-2].y,  t[ts-1].y,  t[ts-2].x - t[ts-1].x) // TODO : Complete 16 bit phi/sigma retrieval from float4 texture register. Perhaps use CalcHiLo?
#define Normal2(ts)   float3(dot_[ts-1], dot_[ts],   0)                     // Preceding and current stage dot result. Will be input for Sample2D.
#define Normal3(ts)   float3(dot_[ts-2], dot_[ts-1], dot_[ts])              // Two preceding and current stage dot result.
#define Eye           float3(iT[1].w,    iT[2].w,    iT[3].w)               // 4th (q) component of input texture coordinates 1, 2 and 3. Only used by texm3x3vspec/PS_TEXTUREMODES_DOT_RFLCT_SPEC, always at stage 3. TODO : Map iT[1/2/3] through PS_INPUTTEXTURE_[]?
#define Reflect(n, e) 2 * (dot(n, e) / dot(n, n)) * n - e                   // https://documentation.help/directx8_c/texm3x3vspec.htm
#define BumpEnv(ts)   DoBumpEnv(iT[ts], BEM(ts), src(ts))                   // Will be input for Sample2D.
#define LSO(ts)       (LUM(ts).x * src(ts).b) + LUM(ts).y                   // Uses PSH_XBOX_CONSTANT_LUM .x = D3DTSS_BUMPENVLSCALE .y = D3DTSS_BUMPENVLOFFSET

// Implementations for all possible texture modes, with stage as argument (prefixed with valid stages and corresponding pixel shader 1.3 assembly texture addressing instructions)
// For ease of understanding, all follow this plan : Optional specifics, or dot calculation (some with normal selection) and sampling vector determination. All end by deriving a value and assigning this to the stage's texture register.

#define PS_TEXTUREMODES_NONE(ts)                                                                    v = black;           t[ts] = v // Seems to work
#define PS_TEXTUREMODES_PROJECT2D(ts)                                          s = iT[ts].xyz;   v = Sample2D(ts, s); t[ts] = v // Seems to work (are x/w and y/w implicit?) [1]
/*0123 tex          */
#define PS_TEXTUREMODES_PROJECT3D(ts)                                          s = iT[ts].xyz;      v = Sample3D(ts, s); t[ts] = v // Seems to work (is z/w implicit?)
/*0123 tex          */
#define PS_TEXTUREMODES_CUBEMAP(ts)                                            s = iT[ts].xyz;      v = Sample6F(ts, s); t[ts] = v // TODO : Test
#define PS_TEXTUREMODES_PASSTHRU(ts)                                                                v = Passthru(ts);    t[ts] = v // Seems to work
#define PS_TEXTUREMODES_CLIPPLANE(ts)            PS_COMPAREMODE_ ## ts(iT[ts]);                     v = black;           t[ts] = v // Seems to work (setting black to texture register, in case it gets read)
#define PS_TEXTUREMODES_BUMPENVMAP(ts)                                         s = BumpEnv(ts);     v = Sample2D(ts, s); t[ts] = v // Seems to work
#define PS_TEXTUREMODES_BUMPENVMAP_LUM(ts)       PS_TEXTUREMODES_BUMPENVMAP(ts);                    v.rgb *= LSO(ts);    t[ts] = v // TODO : Test
#define PS_TEXTUREMODES_BRDF(ts)                                               s = Brdf(ts);        v = Sample3D(ts, s); t[ts] = v // TODO : Test (t[ts-2] is 16 bit eyePhi,eyeSigma; t[ts-1] is lightPhi,lightSigma)
#define PS_TEXTUREMODES_DOT_ST(ts)               CalcDot(ts); n = Normal2(ts); s = n;               v = Sample2D(ts, s); t[ts] = v // TODO : Test
#define PS_TEXTUREMODES_DOT_ZW(ts)               CalcDot(ts); n = Normal2(ts); if (n.y==0) v=1;else v = n.x / n.y;       t[ts] = v // TODO : Make depth-check use result of division, but how?
#define PS_TEXTUREMODES_DOT_RFLCT_DIFF(ts)       CalcDot(ts); n = Normal2(ts); s = n;               v = Sample6F(ts, s); t[ts] = v // TODO : Test
#define PS_TEXTUREMODES_DOT_RFLCT_SPEC(ts)       CalcDot(ts); n = Normal3(ts); s = Reflect(n, Eye); v = Sample6F(ts, s); t[ts] = v // TODO : Test
#define PS_TEXTUREMODES_DOT_STR_3D(ts)           CalcDot(ts); n = Normal3(ts); s = n;               v = Sample3D(ts, s); t[ts] = v // TODO : Test
#define PS_TEXTUREMODES_DOT_STR_CUBE(ts)         CalcDot(ts); n = Normal3(ts); s = n;               v = Sample6F(ts, s); t[ts] = v // TODO : Test
#define PS_TEXTUREMODES_DPNDNT_AR(ts)                                          s = src(ts).arg;     v = Sample2D(ts, s); t[ts] = v // TODO : Test [1]
#define PS_TEXTUREMODES_DPNDNT_GB(ts)                                          s = src(ts).gba;     v = Sample2D(ts, s); t[ts] = v // TODO : Test [1]

#define PS_TEXTUREMODES_DOTPRODUCT(ts)           CalcDot(ts);                                       v = float4(dm, 0);   t[ts] = v // TODO : Test all dot mapping (setting texture register, in case it gets read) 
#define PS_TEXTUREMODES_DOT_RFLCT_SPEC_CONST(ts) CalcDot(ts); n = Normal3(ts); s = Reflect(n, C0);  v = Sample6F(ts, s); t[ts] = v // TODO : Test


struct PS_INPUT // Declared identical to vertex shader output (see VS_OUTPUT)
{
    float4 iPos : SV_Position; // Screen space x,y pixel location (changed from float 2 IPos)
	float4 iD0  : COLOR0; // Front-facing primary (diffuse) vertex color (clamped to 0..1)
	float4 iD1  : COLOR1; // Front-facing secondary (specular) vertex color (clamped to 0..1)
	float  iFog : FOG;
	float  iPts : PSIZE;
	float4 iB0  : TEXCOORD4; // Back-facing primary (diffuse) vertex color (clamped to 0..1)
	float4 iB1  : TEXCOORD5; // Back-facing secondary (specular) vertex color (clamped to 0..1)
	float4 iT0  : TEXCOORD0; // Texture Coord 0
	float4 iT1  : TEXCOORD1; // Texture Coord 1
	float4 iT2  : TEXCOORD2; // Texture Coord 2
	float4 iT3  : TEXCOORD3; // Texture Coord 3
    bool iFF : SV_IsFrontFace; // Front facing if true (changed from float VFACE to bool SV_IsFrontFace for modern shader support)
};

struct PS_OUTPUT
{
    float4 oR0 : SV_Target0;
};

PS_OUTPUT main(const PS_INPUT xIn)
{
	// fogging
    const float fogDepth = xIn.iFog.x; // Don't abs this value!
    const int fogTableMode = FOGINFO.x;
    const float fogDensity = FOGINFO.y;
    const float fogStart = FOGINFO.z;
    const float fogEnd = FOGINFO.w;

    const int FOG_TABLE_NONE = 0;
    const int FOG_TABLE_EXP = 1;
    const int FOG_TABLE_EXP2 = 2;
    const int FOG_TABLE_LINEAR = 3;
 
    float fogFactor;
	
    if (FOGENABLE.x == 0)
    {
        fogFactor = 1;
    }
    else
    {
        if (fogTableMode == FOG_TABLE_NONE) 
            fogFactor = fogDepth;
        if (fogTableMode == FOG_TABLE_EXP) 
            fogFactor = 1 / exp(fogDepth * fogDensity); // 1 / e^(d * density)
        if (fogTableMode == FOG_TABLE_EXP2) 
            fogFactor = 1 / exp(pow(fogDepth * fogDensity, 2)); // 1 / e^((d * density)^2)
        if (fogTableMode == FOG_TABLE_LINEAR) 
            fogFactor = (fogEnd - fogDepth) / (fogEnd - fogStart);
    }
	  
	// Local constants
    const float4 zero = 0;
    const float4 half_ = 0.5; // = s_negbias(zero)
    const float4 one = 1; // = s_comp(zero)
    const float4 black = float4(0, 0, 0, 1); // opaque black
    const float4 iT[4] = { xIn.iT0, xIn.iT1, xIn.iT2, xIn.iT3 }; // Map input texture coordinates to an array, for indexing purposes

	// Xbox register variables
    float4 r0, r1; // Temporary registers
    float4 t[4]; // Texture coordinate registers
    float4 v0, v1; // Vertex color registers
    float4 _discard; // Write-only discard 'register' (we assume the HLSL compilers' optimization pass will remove assignments to this)
    float4 fog; // Read-only fog register, reading alpha is only allowed in final combiner
    float4 sum, prod; // Special purpose registers for xfc (final combiner) operation

	// Helper variables
    int stage = 0; // Write-only variable, emitted as prefix-comment before each 'opcode', used in C0 and C1 macro's (and should thus get optimized away), initialized to zero for use of C0 in PS_TEXTUREMODES_DOT_RFLCT_SPEC_CONST
    float4 tmp;
    float H, L; // HILO (high/low) temps
    float dot_[4];
    float3 dm; // Dot mapping temporary
    float3 n; // Normal vector (based on preceding dot_[] values)
    float3 s; // Actual texture coordinate sampling coordinates (temporary)
    float4 v; // Texture value (temporary)

	// Determine if this is a front face or backface
    bool isFrontFace = (FRONTFACE_FACTOR.x == 0) ? true : ((FRONTFACE_FACTOR.x > 0) ? xIn.iFF : !xIn.iFF);
	// Initialize variables
    r0 = r1 = black; // Note : r0.a/r1.a will be overwritten by t0.a/t1.a (opaque_black will be retained for PS_TEXTUREMODES_NONE)
	// Note : VFACE/FrontFace has been unreliable, investigate again if some test-case shows bland colors
    v0 = isFrontFace ? xIn.iD0 : xIn.iB0; // Diffuse front/back
    v1 = isFrontFace ? xIn.iD1 : xIn.iB1; // Specular front/back
    fog = float4(c_fog.rgb, saturate(fogFactor)); // color from PSH_XBOX_CONSTANT_FOG, alpha from vertex shader output / pixel shader input

	// Xbox shader program will be inserted here
    // <XBOX SHADER PROGRAM GOES HERE>
	// End Xbox shader program

	// Copy r0.rgba to output
    PS_OUTPUT xOut;

    xOut.oR0 = r0;

    return xOut;
}
