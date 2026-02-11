#include "common_ps.hlsli"

struct PS_INPUT // Declared identical to vertex shader output (see VS_OUTPUT)
{
	float2 iPos : VPOS;   // Screen space x,y pixel location
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
	float  iFF  : VFACE; // Front facing if > 0
};

struct PS_OUTPUT
{
	float4 oR0 : COLOR;
};

PS_OUTPUT main(const PS_INPUT xIn)
{
	// fogging
	const float fogDepth      =   xIn.iFog.x; // Don't abs this value!
	const int   fogTableMode  =   FOGINFO.x;
	const float fogDensity    =   FOGINFO.y;
	const float fogStart      =   FOGINFO.z;
	const float fogEnd        =   FOGINFO.w;  

	const int FOG_TABLE_NONE    = 0;
	const int FOG_TABLE_EXP     = 1;
	const int FOG_TABLE_EXP2    = 2;
	const int FOG_TABLE_LINEAR  = 3;
 
          float fogFactor;
	
	if(FOGENABLE == 0){
	    fogFactor = 1;
	}
	else
		{
    if(fogTableMode == FOG_TABLE_NONE) 
        fogFactor = fogDepth;  
    if(fogTableMode == FOG_TABLE_EXP) 
        fogFactor = 1 / exp(fogDepth * fogDensity); // 1 / e^(d * density)
    if(fogTableMode == FOG_TABLE_EXP2) 
        fogFactor = 1 / exp(pow(fogDepth * fogDensity, 2)); // 1 / e^((d * density)^2)
    if(fogTableMode == FOG_TABLE_LINEAR) 
        fogFactor = (fogEnd - fogDepth) / (fogEnd - fogStart);
	}
	  
	// Local constants
	const float4 zero = 0;
	const float4 half_ = 0.5; // = s_negbias(zero)
	const float4 one = 1; // = s_comp(zero)
	const float4 black = float4(0, 0, 0, 1); // opaque black
	const float4 iT[4] = { xIn.iT0, xIn.iT1, xIn.iT2, xIn.iT3 }; // Map input texture coordinates to an array, for indexing purposes

	// Xbox register variables
	float4 r0, r1;         // Temporary registers
	float4 t[4];           // Texture coordinate registers
	float4 v0, v1;         // Vertex color registers
	float4 _discard;       // Write-only discard 'register' (we assume the HLSL compilers' optimization pass will remove assignments to this)
	float4 fog;            // Read-only fog register, reading alpha is only allowed in final combiner
	float4 sum, prod;      // Special purpose registers for xfc (final combiner) operation

	// Helper variables
	int stage = 0;         // Write-only variable, emitted as prefix-comment before each 'opcode', used in C0 and C1 macro's (and should thus get optimized away), initialized to zero for use of C0 in PS_TEXTUREMODES_DOT_RFLCT_SPEC_CONST
	float4 tmp;
	float H, L;            // HILO (high/low) temps
	float dot_[4];
	float3 dm;             // Dot mapping temporary
	float3 n;              // Normal vector (based on preceding dot_[] values)
	float3 s;              // Actual texture coordinate sampling coordinates (temporary)
	float4 v;              // Texture value (temporary)

	// Determine if this is a front face or backface
	bool isFrontFace = (xIn.iFF * FRONTFACE_FACTOR) >= 0;

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
