#include "pch.h"
#include "pixel_shader.h"
#include "shader.h"


// Original code (mostly) by CXBX team

// Note : On a hardware level, there are only 4 pixel shaders instructions present in the Nvidia NV2A GPU :
// - xdd (dot/dot/discard) > calculating AB=A.B and CD=C.D
// - xdm (dot/mul/discard) > calculating AB=A.B and CD=C*D
// - xmmc (mul/mul/mux)    > calculating AB=A*B and CD=C*D and Mux=AB?CD
// - xmma (mul/mul/sum)    > calculating AB=A*B and CD=C*D and Sum=AB+CD
// (One of the implications is, that once a dot-product is issued, no Sum or Mux operation is possible.)
// All other instructions (mov, add, sub, mul, lrp, dp3) are compiled into one of these 4 using varying arguments.
// All 4 instruction specify up to three output registers, all of which must be unique (or be discarded).
//
// Apart from the r0,r1 and t0-t3 registers, the NV2A allows writing to the v0,v1 (this conflicts with PS.1.3!)
//
// The precision of registers is also different; On the Xbox, all 4 color components (RGBA) for constant registers
// range from 0.0 to 1.0 (with 8 bits of precision), while all other registers (r, t and v) range from -1.0 to 1.0.
//
// This is different from native PS.1.3 in which constant registers suddenly have a range -1.0 to 1.0, but vertex
// registers (v0 and v1) range from 0.0 to 1.0 instead, and the temporary and texture registers have a range
// from negative 'MaxPixelShaderValue' to positive 'MaxPixelShaderValue', which value must at least be 1.0
// (but depending on hardware capabilities can be higher).
//
// TODO : Correct emulation should correct these differences; The range of constant-registers must be converted
// from 0.0-1.0 to -1.0-1.0, and vertex-registers must be converted from -1.0..1.0 to 0.0..1.0 (if anything like
// that is at all possible!)
//
// register | Xbox range | Native range | Xbox      | Native    |
//  C0..C8  |  0.0 - 1.0 !   -1.0 - 1.0 | readonly  | readonly  |
//  R0..R1  | -1.0 - 1.0 |   -1.0 - 1.0 | writeable | writeable |
//  T0..T3  | -1.0 - 1.0 |   -1.0 - 1.0 | writeable | writeable |
//  V0..V1  | -1.0 - 1.0 !    0.0 - 1.0 | writeable ! readonly  |
//
// "-C0_bias_x2" shifts range from [ 0..1] to [-1..1]
// "-V0_bias_d2" shifts range from [-1..1] to [ 0..1]

/* RPSRegisterObject */

void RPSRegisterObject::Decode(uint8_t Value)
{
	Reg = (PS_REGISTER)(Value & PS_REGISTER_MASK); // = 0x0f

	// Validate correctness (see NOTE below)
	if (Reg == 6) 
		printf("Unknown PS_REGISTER : 6\n");
	if (Reg == 7) 
		printf("Unknown PS_REGISTER : 7\n");
}


/* RPSInputRegister */

void RPSInputRegister::Decode(uint8_t Value, unsigned stage_nr, bool isRGB)
{
	RPSRegisterObject::Decode(Value);

	Channel = (PS_CHANNEL)(Value & PS_CHANNEL_MASK); // = 0x10
	InputMapping = (PS_INPUTMAPPING)(Value & PS_INPUTMAPPING_MASK); // = 0xe0

	if (stage_nr == 9) {
		// In final combiner stage, convert C0 into FC0, and C1 into FC1, to discern them as separate registers
		if (Reg == PS_REGISTER_C0) Reg = PS_REGISTER_FC0;
		if (Reg == PS_REGISTER_C1) Reg = PS_REGISTER_FC1;
	}

	// Validate correctness (see NOTE below)
	if (stage_nr <= X_PSH_COMBINECOUNT) {
		if (Reg == PS_REGISTER_FOG) {
			if (!isRGB) 
				printf("PS_REGISTER_FOG input not allowed in Alpha register combiner\n");
			else if (Channel == PS_CHANNEL_ALPHA) 
				printf("PS_REGISTER_FOG.a input not allowed in RGB register combiner\n");
		}
		if (Reg == PS_REGISTER_V1R0_SUM) printf("PS_REGISTER_V1R0_SUM input only allowed in final combiner\n");
		if (Reg == PS_REGISTER_EF_PROD) printf("PS_REGISTER_EF_PROD input only allowed in final combiner\n");
	}
	else { // final combiner
		if (InputMapping == PS_INPUTMAPPING_EXPAND_NORMAL) printf("PS_INPUTMAPPING_EXPAND_NORMAL not allowed in final combiner\n");
		if (InputMapping == PS_INPUTMAPPING_EXPAND_NEGATE) printf("PS_INPUTMAPPING_EXPAND_NEGATE not allowed in final combiner\n");
		if (InputMapping == PS_INPUTMAPPING_HALFBIAS_NORMAL) printf("PS_INPUTMAPPING_HALFBIAS_NORMAL not allowed in final combiner\n");
		if (InputMapping == PS_INPUTMAPPING_HALFBIAS_NEGATE) printf("PS_INPUTMAPPING_HALFBIAS_NEGATE not allowed in final combiner\n");
		if (InputMapping == PS_INPUTMAPPING_SIGNED_IDENTITY) printf("PS_INPUTMAPPING_SIGNED_IDENTITY not allowed in final combiner\n");
		if (InputMapping == PS_INPUTMAPPING_SIGNED_NEGATE) printf("PS_INPUTMAPPING_SIGNED_NEGATE not allowed in final combiner\n");
	}
}

/* RPSCombinerOutput */

void RPSCombinerOutput::Decode(uint8_t Value, uint16_t PSInputs, unsigned stage_nr, bool isRGB)
{
	RPSRegisterObject::Decode(Value);

	// Decode PSAlphaInputs / PSRGBInputs :
	Input[0].Decode((uint8_t)(PSInputs >> 8), stage_nr, isRGB);
	Input[1].Decode((uint8_t)(PSInputs >> 0), stage_nr, isRGB);

	// Validate correctness (see NOTE below)
	if (Reg == PS_REGISTER_C0) printf("PS_REGISTER_C0 not allowed as output\n");
	if (Reg == PS_REGISTER_C1) printf("PS_REGISTER_C1 not allowed as output\n");
	if (Reg == PS_REGISTER_FOG) printf("PS_REGISTER_FOG not allowed as output\n");
	if (Reg == PS_REGISTER_V1R0_SUM) printf("PS_REGISTER_V1R0_SUM not allowed as output\n");
	if (Reg == PS_REGISTER_EF_PROD) printf("PS_REGISTER_EF_PROD not allowed as output\n");
}

/* RPSCombinerStageChannel */

void RPSCombinerStageChannel::Decode(uint32_t PSInputs, uint32_t PSOutputs, unsigned stage_nr, bool isRGB)
{
	// Decode PSAlphaOutputs / PSRGBOutputs and PSAlphaInputs / PSRGBInputs :
	OutputCD.Decode((uint8_t)(PSOutputs >> 0), (uint16_t)(PSInputs >> 0), stage_nr, isRGB);
	OutputAB.Decode((uint8_t)(PSOutputs >> 4), (uint16_t)(PSInputs >> 16), stage_nr, isRGB);
	OutputMUX_SUM.Decode((uint8_t)(PSOutputs >> 8));

	// Get the combiner output flags :
	PS_COMBINEROUTPUT CombinerOutputFlags = (PS_COMBINEROUTPUT)(PSOutputs >> 12);

	// Decompose the combiner output flags :
	OutputCD.DotProduct = (CombinerOutputFlags & PS_COMBINEROUTPUT_CD_DOT_PRODUCT) > 0; // False=Multiply, True=DotProduct
	OutputAB.DotProduct = (CombinerOutputFlags & PS_COMBINEROUTPUT_AB_DOT_PRODUCT) > 0; // False=Multiply, True=DotProduct
	AB_CD_MUX = (CombinerOutputFlags & PS_COMBINEROUTPUT_AB_CD_MUX) > 0; // False=AB+CD, True=MUX(AB,CD) based on R0.a
	CombinerOutputMapping = (PS_COMBINEROUTPUT_OUTPUTMAPPING)(CombinerOutputFlags & PS_COMBINEROUTPUT_OUTPUTMAPPING_MASK); // = 0x38
	OutputCD.BlueToAlpha = (CombinerOutputFlags & PS_COMBINEROUTPUT_CD_BLUE_TO_ALPHA) >> 6; // 0=Alpha-to-Alpha, 1=Blue-to-Alpha
	OutputAB.BlueToAlpha = (CombinerOutputFlags & PS_COMBINEROUTPUT_AB_BLUE_TO_ALPHA) >> 7; // 0=Alpha-to-Alpha, 1=Blue-to-Alpha

	// Discover test-cases (see TODO below)
	// Check for 'discard-all-outputs'
	if (OutputAB.DotProduct || OutputCD.DotProduct) {
		if ((OutputAB.Reg == PS_REGISTER_DISCARD) && (OutputCD.Reg == PS_REGISTER_DISCARD)) 
			printf("All two outputs discarded\n");
	}
	else {
		// if ((OutputAB.Reg == PS_REGISTER_DISCARD) && (OutputCD.Reg == PS_REGISTER_DISCARD) && (OutputMUX_SUM.Reg == PS_REGISTER_DISCARD)) LOG_TEST_CASE("All three outputs discarded"); // Test-case : XDK sample : Minnaert (on Stage2.Alpha)
	}

	// Validate correctness (see NOTE below)
	if ((PSOutputs & ~0x000FFFFF) > 0) 
		printf("Unknown PS_COMBINEROUTPUT flag bits detected\n");
	if (CombinerOutputMapping == PS_COMBINEROUTPUT_OUTPUTMAPPING_SHIFTLEFT_2_BIAS) 
		printf("PS_COMBINEROUTPUT_SHIFTLEFT_2_BIAS unsupported on NV2A?\n");
	if (CombinerOutputMapping == PS_COMBINEROUTPUT_OUTPUTMAPPING_SHIFTRIGHT_1_BIAS)
		printf("PS_COMBINEROUTPUT_SHIFTRIGHT_1_BIAS unsupported on NV2A?\n");
	if (isRGB) {
		if (OutputMUX_SUM.Reg != PS_REGISTER_DISCARD) {
			if (OutputCD.DotProduct) 
				printf("PS_COMBINEROUTPUT_CD_DOT_PRODUCT detected without PS_REGISTER_DISCARD in MUX_SUM\n");
			if (OutputAB.DotProduct) 
				printf("PS_COMBINEROUTPUT_AB_DOT_PRODUCT detected without PS_REGISTER_DISCARD in MUX_SUM\n");
		}
		if (OutputCD.DotProduct) {
			if (!OutputAB.DotProduct) 
				printf("PS_COMBINEROUTPUT_CD_DOT_PRODUCT detected without PS_COMBINEROUTPUT_AB_DOT_PRODUCT (so, xmd 'opcode')\n"); // Need test-cases  Note : Undefined xmd (mul/dot) *is* supported in PixelShaderTemplate.hlsl
		}
	}
	else { // DotProduct and BlueToAlpha are not valid for Alpha
		if (OutputCD.DotProduct)  
			printf("PS_COMBINEROUTPUT_CD_DOT_PRODUCT shouldn't be set for Alpha\n");
		if (OutputAB.DotProduct)  
			printf("PS_COMBINEROUTPUT_AB_DOT_PRODUCT shouldn't be set for Alpha\n");
		if (OutputCD.BlueToAlpha) 
			printf("PS_COMBINEROUTPUT_CD_BLUE_TO_ALPHA shouldn't be set for Alpha\n");
		if (OutputAB.BlueToAlpha) 
			printf("PS_COMBINEROUTPUT_AB_BLUE_TO_ALPHA shouldn't be set for Alpha\n");
	}
}

/* RPSFinalCombiner */

void RPSFinalCombiner::Decode(const uint32_t PSFinalCombinerInputsABCD, const uint32_t PSFinalCombinerInputsEFG)
{
	Input[0].Decode((uint8_t)(PSFinalCombinerInputsABCD >> 24), /*stage_nr=*/9, /*isRGB=*/true);
	Input[1].Decode((uint8_t)(PSFinalCombinerInputsABCD >> 16), /*stage_nr=*/9, /*isRGB=*/true);
	Input[2].Decode((uint8_t)(PSFinalCombinerInputsABCD >> 8), /*stage_nr=*/9, /*isRGB=*/true);
	Input[3].Decode((uint8_t)(PSFinalCombinerInputsABCD >> 0), /*stage_nr=*/9, /*isRGB=*/true);
	Input[4].Decode((uint8_t)(PSFinalCombinerInputsEFG >> 24), /*stage_nr=*/9, /*isRGB=*/true);
	Input[5].Decode((uint8_t)(PSFinalCombinerInputsEFG >> 16), /*stage_nr=*/9, /*isRGB=*/true);
	Input[6].Decode((uint8_t)(PSFinalCombinerInputsEFG >> 8), /*stage_nr=*/9, /*isRGB=*/false); // Note : Final combiner input G must be a single component, and must thus be decoded as Alpha
	PS_FINALCOMBINERSETTING FinalCombinerSettingFlags = (PS_FINALCOMBINERSETTING)((PSFinalCombinerInputsEFG >> 0) & 0xFF);

	ComplementV1 = (FinalCombinerSettingFlags & PS_FINALCOMBINERSETTING_COMPLEMENT_V1) > 0;
	ComplementR0 = (FinalCombinerSettingFlags & PS_FINALCOMBINERSETTING_COMPLEMENT_R0) > 0;
	ClampSum = (FinalCombinerSettingFlags & PS_FINALCOMBINERSETTING_CLAMP_SUM) > 0;

	// Discover test-cases (see TODO below)
	// if (Input[0].Channel != PS_CHANNEL_ALPHA) LOG_TEST_CASE("PS_CHANNEL_RGB/PS_CHANNEL_BLUE detected on final combiner A input"); // Note : test-case ModifyPixelShader uses PS_REGISTER_FOG.rgb and seems to expect .rgb handling (not PS_CHANNEL_BLUE's .b)
	if (Input[4].Channel == PS_CHANNEL_ALPHA) 
		printf("PS_CHANNEL_ALPHA detected on final combiner E input\n"); // Need test-case to determine how this should behave (calculating EF_PROD) : .aaa instead of .rgb?
	if (Input[5].Channel == PS_CHANNEL_ALPHA) 
		printf("PS_CHANNEL_ALPHA detected on final combiner F input\n"); // Need test-case to determine how this should behave (calculating EF_PROD) : .aaa instead of .rgb?
	// if (Input[6].Channel == PS_CHANNEL_BLUE) LOG_TEST_CASE("PS_CHANNEL_ALPHA detected on final combiner G input"); // PS_CHANNEL_BLUE (==0==PS_CHANNEL_RGB) uses G.b
	// if (Input[6].Channel == PS_CHANNEL_ALPHA) LOG_TEST_CASE("PS_CHANNEL_ALPHA detected on final combiner G input"); // PS_CHANNEL_ALPHA (==1) uses .a  Test-case : XDK samples BumpDemo,BumpEarth,BumpLens,Explosion

	// Validate correctness (see NOTE below)
	if ((FinalCombinerSettingFlags & ~0xE0) > 0) 
		printf("Unknown FinalCombinerSetting bits detected\n");
}

/* DecodedRegisterCombiner */

void DecodedRegisterCombiner::GetPSTextureModes(X_D3DPIXELSHADERDEF* pPSDef, PS_TEXTUREMODES psTextureModes[X_D3DTS_STAGECOUNT])
{
	for (int i = 0; i < X_D3DTS_STAGECOUNT; i++) 
	{
		psTextureModes[i] = (PS_TEXTUREMODES)((pPSDef->PSTextureModes >> (i * 5)) & PS_TEXTUREMODES_MASK);

		// Discover test-cases (see TODO below)
		// if (psTextureModes[i] == PS_TEXTUREMODES_NONE) LOG_TEST_CASE("PS_TEXTUREMODES_NONE");
		// if (psTextureModes[i] == PS_TEXTUREMODES_PROJECT2D) LOG_TEST_CASE("PS_TEXTUREMODES_PROJECT2D");
		if (psTextureModes[i] == PS_TEXTUREMODES_PROJECT3D) 
			printf("PS_TEXTUREMODES_PROJECT3D\n"); // Test-case: XDK sample TechCertGame,NoSortAlphaBlend,VolumeLight
		if (psTextureModes[i] == PS_TEXTUREMODES_CUBEMAP) 
			printf("PS_TEXTUREMODES_CUBEMAP\n"); // Test-case : XDK sample TechCertGame,Minnaert  
		if (psTextureModes[i] == PS_TEXTUREMODES_PASSTHRU) 
			printf("PS_TEXTUREMODES_PASSTHRU\n"); // Test-case : XDK sample BumpDemo 
		if (psTextureModes[i] == PS_TEXTUREMODES_CLIPPLANE) 
			printf("PS_TEXTUREMODES_CLIPPLANE\n"); // Test-case : XDK sample UserClipPlane  T
		// if (psTextureModes[i] == PS_TEXTUREMODES_BUMPENVMAP) LOG_TEST_CASE("PS_TEXTUREMODES_BUMPENVMAP"); // Test-case : XDK sample BumpEarth, BumpLens
		if (psTextureModes[i] == PS_TEXTUREMODES_BUMPENVMAP_LUM) 
			printf("PS_TEXTUREMODES_BUMPENVMAP_LUM\n"); // Test-case : XDK sample BumpEarth  
		if (psTextureModes[i] == PS_TEXTUREMODES_BRDF) 
			printf("PS_TEXTUREMODES_BRDF\n");
		if (psTextureModes[i] == PS_TEXTUREMODES_DOT_ST) 
			printf("PS_TEXTUREMODES_DOT_ST\n");
		if (psTextureModes[i] == PS_TEXTUREMODES_DOT_ZW) 
			printf("PS_TEXTUREMODES_DOT_ZW\n");
		if (psTextureModes[i] == PS_TEXTUREMODES_DOT_RFLCT_DIFF) 
			printf("PS_TEXTUREMODES_DOT_RFLCT_DIFF\n");
		if (psTextureModes[i] == PS_TEXTUREMODES_DOT_RFLCT_SPEC) 
			printf("PS_TEXTUREMODES_DOT_RFLCT_SPEC\n");
		if (psTextureModes[i] == PS_TEXTUREMODES_DOT_STR_3D) 
			printf("PS_TEXTUREMODES_DOT_STR_3D\n");
		if (psTextureModes[i] == PS_TEXTUREMODES_DOT_STR_CUBE) 
			printf("PS_TEXTUREMODES_DOT_STR_CUBE\n");
		if (psTextureModes[i] == PS_TEXTUREMODES_DPNDNT_AR) 
			printf("PS_TEXTUREMODES_DPNDNT_AR\n");
		if (psTextureModes[i] == PS_TEXTUREMODES_DPNDNT_GB) 
			printf("PS_TEXTUREMODES_DPNDNT_GB\n");
		if (psTextureModes[i] == PS_TEXTUREMODES_DOTPRODUCT) 
			printf("PS_TEXTUREMODES_DOTPRODUCT\n");
		if (psTextureModes[i] == PS_TEXTUREMODES_DOT_RFLCT_SPEC_CONST)
			printf("PS_TEXTUREMODES_DOT_RFLCT_SPEC_CONST\n");

		// Validate correctness (see NOTE below)
		if (psTextureModes[i] == PS_TEXTUREMODES_BUMPENVMAP) if (i < 1) 
			printf("PS_TEXTUREMODES_BUMPENVMAP only allowed in stage 1, 2 or 3\n");
		if (psTextureModes[i] == PS_TEXTUREMODES_BUMPENVMAP_LUM) if (i < 1) 
			printf("PS_TEXTUREMODES_BUMPENVMAP_LUM only allowed in stage 1, 2 or 3\n");
		if (psTextureModes[i] == PS_TEXTUREMODES_BRDF) if (i < 2) 
			printf("PS_TEXTUREMODES_BRDF only allowed in stage 2 or 3\n");
		if (psTextureModes[i] == PS_TEXTUREMODES_DOT_ST) {
			if (i < 2) printf("PS_TEXTUREMODES_DOT_ST only allowed in stage 2 or 3\n");
			if (psTextureModes[i - 1] != PS_TEXTUREMODES_DOTPRODUCT)
				printf("PS_TEXTUREMODES_DOT_ST only allowed after PS_TEXTUREMODES_DOTPRODUCT\n");
		}
		if (psTextureModes[i] == PS_TEXTUREMODES_DOT_ZW) {
			if (i < 2) printf("PS_TEXTUREMODES_DOT_ZW only allowed in stage 2 or 3\n");
			if (psTextureModes[i - 1] != PS_TEXTUREMODES_DOTPRODUCT) printf("PS_TEXTUREMODES_DOT_ZW only allowed after PS_TEXTUREMODES_DOTPRODUCT\n");
		}
		if (psTextureModes[i] == PS_TEXTUREMODES_DOT_RFLCT_DIFF) if (i != 2) printf("PS_TEXTUREMODES_DOT_RFLCT_DIFF only allowed in stage 2\n");
		if (psTextureModes[i] == PS_TEXTUREMODES_DOT_RFLCT_SPEC) if (i < 3) printf("PS_TEXTUREMODES_DOT_RFLCT_SPEC only allowed in stage 3\n");
		if (psTextureModes[i] == PS_TEXTUREMODES_DOT_STR_3D) if (i < 3) printf("PS_TEXTUREMODES_DOT_STR_3D only allowed in stage 3\n");
		if (psTextureModes[i] == PS_TEXTUREMODES_DOT_STR_CUBE) if (i < 3) printf("PS_TEXTUREMODES_DOT_STR_CUBE only allowed in stage 1, 2 or 3\n");
		if (psTextureModes[i] == PS_TEXTUREMODES_DPNDNT_AR) if (i < 1) printf("PS_TEXTUREMODES_DPNDNT_AR only allowed in stage 1, 2 or 3\n");
		if (psTextureModes[i] == PS_TEXTUREMODES_DPNDNT_GB) if (i < 1) printf("PS_TEXTUREMODES_DPNDNT_GB only allowed in stage 1, 2 or 3\n");
		if (psTextureModes[i] == PS_TEXTUREMODES_DOTPRODUCT) if (i < 1 || i > 2) printf("PS_TEXTUREMODES_DOTPRODUCT only allowed in stage 1 or 2\n");
		if (psTextureModes[i] == PS_TEXTUREMODES_DOT_RFLCT_SPEC_CONST) if (i < 3) printf("PS_TEXTUREMODES_DOT_RFLCT_SPEC_CONST only allowed in 3\n");
		if (psTextureModes[i] > PS_TEXTUREMODES_DOT_RFLCT_SPEC_CONST) printf("Invalid PS_TEXTUREMODES in stage?\n");
	}

	// Validate correctness (see NOTE below)
	if ((pPSDef->PSTextureModes & ~0x000FFFFF) > 0) 
		printf("Unknown PSTextureModes bits detected\n");
}

void DecodedRegisterCombiner::GetPSDotMapping(X_D3DPIXELSHADERDEF* pPSDef, PS_DOTMAPPING psDotMapping[X_D3DTS_STAGECOUNT])
{
	psDotMapping[0] = (PS_DOTMAPPING)(0);
	for (int i = 1; i < X_D3DTS_STAGECOUNT; i++) {
		psDotMapping[i] = (PS_DOTMAPPING)((pPSDef->PSDotMapping >> ((i - 1) * 4)) & PS_DOTMAPPING_MASK);

		// Discover test-cases (see TODO below)
		// if (psDotMapping[i] == PS_DOTMAPPING_ZERO_TO_ONE) LOG_TEST_CASE("PS_DOTMAPPING_ZERO_TO_ONE"); // Note : Most common scenario, no need for test-cases
		if (psDotMapping[i] == PS_DOTMAPPING_MINUS1_TO_1_D3D) printf("PS_DOTMAPPING_MINUS1_TO_1_D3D\n"); // Test-case : XDK samples BumpDemo, Minnaert
		if (psDotMapping[i] == PS_DOTMAPPING_MINUS1_TO_1_GL) printf("PS_DOTMAPPING_MINUS1_TO_1_GL\n");
		if (psDotMapping[i] == PS_DOTMAPPING_MINUS1_TO_1) printf("PS_DOTMAPPING_MINUS1_TO_1\n");
		if (psDotMapping[i] == PS_DOTMAPPING_HILO_1) printf("PS_DOTMAPPING_HILO_1\n");
		if (psDotMapping[i] == PS_DOTMAPPING_HILO_HEMISPHERE_D3D) printf("PS_DOTMAPPING_HILO_HEMISPHERE_D3D\n");
		if (psDotMapping[i] == PS_DOTMAPPING_HILO_HEMISPHERE_GL) printf("PS_DOTMAPPING_HILO_HEMISPHERE_GL\n");
		if (psDotMapping[i] == PS_DOTMAPPING_HILO_HEMISPHERE) printf("PS_DOTMAPPING_HILO_HEMISPHERE\n");
	}

	// Validate correctness (see NOTE below)
	if ((pPSDef->PSDotMapping & ~0x00000777) > 0) printf("Unknown PSDotMapping bits detected\n");
}

void DecodedRegisterCombiner::GetPSCompareModes(X_D3DPIXELSHADERDEF* pPSDef, bool psCompareModes[X_D3DTS_STAGECOUNT][4])
{
	for (int i = 0; i < X_D3DTS_STAGECOUNT; i++) {
		uint32_t CompareMode = (pPSDef->PSCompareMode >> (i * 4)) & PS_COMPAREMODE_MASK;
		psCompareModes[i][0] = (CompareMode & PS_COMPAREMODE_S_GE) > 0;
		psCompareModes[i][1] = (CompareMode & PS_COMPAREMODE_T_GE) > 0;
		psCompareModes[i][2] = (CompareMode & PS_COMPAREMODE_R_GE) > 0;
		psCompareModes[i][3] = (CompareMode & PS_COMPAREMODE_Q_GE) > 0;
	}

	// Validate correctness (see NOTE below)
	if ((pPSDef->PSCompareMode & ~0x0000FFFF) > 0) 
		printf("Unknown PSCompareMode bits detected\n");
}

void DecodedRegisterCombiner::GetPSInputTexture(X_D3DPIXELSHADERDEF* pPSDef, int32_t psInputTexture[X_D3DTS_STAGECOUNT])
{
	psInputTexture[0] = -1; // Stage 0 has no predecessors (should not be used)
	psInputTexture[1] = 0; // Stage 1 can only use stage 0
	psInputTexture[2] = (pPSDef->PSInputTexture >> 16) & 0x1; // Stage 2 can use stage 0 or 1
	psInputTexture[3] = (pPSDef->PSInputTexture >> 20) & 0x3; // Stage 3 can only use stage 0, 1 or 2

	// Discover test-cases (see TODO below)
	if (psInputTexture[2] == 0) printf("PS_INPUTTEXTURE(2) uses texture 0\n");
	// if (psInputTexture[2] == 1) LOG_TEST_CASE("PS_INPUTTEXTURE(2) uses texture 1"); // Test-case : XDK sample BumpEarth,Explosion,ZSprite
	if (psInputTexture[3] == 0) printf("PS_INPUTTEXTURE(3) uses texture 0\n");
	// if (psInputTexture[3] == 1) LOG_TEST_CASE("PS_INPUTTEXTURE(3) uses texture 1"); // Test-case : XDK sample Explosion,ZSprite
	if (psInputTexture[3] == 2) printf("PS_INPUTTEXTURE(3) uses texture 2\n");

	// Validate correctness (see NOTE below)
	if (psInputTexture[3] == 3) printf("PS_INPUTTEXTURE(3) incorrectly uses texture 3\n");
	if ((pPSDef->PSInputTexture & ~0x00310000) > 0) printf("Unknown PSInputTexture bits detected\n");
}

void DecodedRegisterCombiner::Decode(X_D3DPIXELSHADERDEF* pPSDef)
{
	NumberOfCombiners = (pPSDef->PSCombinerCount >> 0) & 0xF;
	uint32_t CombinerCountFlags = (pPSDef->PSCombinerCount >> 8); // = PS_COMBINERCOUNTFLAGS

	CombinerMuxesOnMsb = (CombinerCountFlags & PS_COMBINERCOUNT_MUX_MSB) > 0;
	CombinerHasUniqueC0 = (CombinerCountFlags & PS_COMBINERCOUNT_UNIQUE_C0) > 0;
	CombinerHasUniqueC1 = (CombinerCountFlags & PS_COMBINERCOUNT_UNIQUE_C1) > 0;

	hasFinalCombiner = (pPSDef->PSFinalCombinerInputsABCD > 0) || (pPSDef->PSFinalCombinerInputsEFG > 0);

	GetPSTextureModes(pPSDef, PSTextureModes);
	GetPSCompareModes(pPSDef, PSCompareMode);
	GetPSDotMapping(pPSDef, PSDotMapping);
	GetPSInputTexture(pPSDef, PSInputTexture);

	for (unsigned i = 0; i < NumberOfCombiners; i++) {
		Combiners[i].RGB.Decode(pPSDef->PSRGBInputs[i], pPSDef->PSRGBOutputs[i], /*stage_nr=*/i, /*isRGB=*/true);
		Combiners[i].Alpha.Decode(pPSDef->PSAlphaInputs[i], pPSDef->PSAlphaOutputs[i], /*stage_nr=*/i, /*isRGB=*/false);
	}

	if (hasFinalCombiner) {
		FinalCombiner.Decode(pPSDef->PSFinalCombinerInputsABCD, pPSDef->PSFinalCombinerInputsEFG);
	}

	TexModeAdjust = ((pPSDef->PSFinalCombinerConstants >> PS_GLOBALFLAGS_SHIFT) & PS_GLOBALFLAGS_TEXMODE_ADJUST) > 0;

	// Discover test-cases 
	if (NumberOfCombiners == 0) 
		printf("NumberOfCombiners is zero\n");

	if (!CombinerMuxesOnMsb) 
		printf("PS_COMBINERCOUNT_MUX_LSB detected\n"); 

	if (TexModeAdjust) 
		printf("PS_GLOBALFLAGS_TEXMODE_ADJUST detected\n");

	// Validate correctness (see NOTE below)
	if (NumberOfCombiners > 8) 
		printf("NumberOfCombiners bigger than maximum (of 8)\n");

	if ((pPSDef->PSCombinerCount & ~0x0001110F) > 0) 
		printf("Unknown PSCombinerCount bits detected\n");
}

// * TODO : For all "Discover test-cases" LOG_TEST_CASE's that lack sufficient test-case mentions, find some, note them in an EOL comment, and comment out the entire check.
// * NOTE : For all "Validate correctness" LOG_TEST_CASE's that ever get hit, investigate what caused it, what should be done, implement that, and update the verification.

/* PSH_RECOMPILED_SHADER */

typedef struct s_CxbxPSDef {
	X_D3DPIXELSHADERDEF PSDef;
	X_D3DRESOURCETYPE ActiveTextureTypes[X_D3DTS_STAGECOUNT];
	bool DecodedTexModeAdjust;
	bool DecodedHasFinalCombiner;
	bool RenderStateFogEnable;
	bool RenderStateSpecularEnable;
	bool AlphaKill[4]; // Read from XboxTextureStates.Get(stage, xbox::X_D3DTSS_ALPHAKILL);

	bool IsEquivalent(const s_CxbxPSDef& Another)
	{
		// Only compare the [*]-marked members, which forms the unique shader declaration (ignore the constants and most Xbox Direct3D8 run-time fields) :
		// [*] DWORD    PSAlphaInputs[8];          // X_D3DRS_PSALPHAINPUTS0..X_D3DRS_PSALPHAINPUTS7 : Alpha inputs for each stage
		// [*] DWORD    PSFinalCombinerInputsABCD; // X_D3DRS_PSFINALCOMBINERINPUTSABCD : Final combiner inputs
		// [*] DWORD    PSFinalCombinerInputsEFG;  // X_D3DRS_PSFINALCOMBINERINPUTSEFG : Final combiner inputs (continued)
		if (memcmp(&(PSDef.PSAlphaInputs[0]), &(Another.PSDef.PSAlphaInputs[0]), (8 + 1 + 1) * sizeof(DWORD)) != 0)
			return false;

		// [-] DWORD    PSConstant0[8];            // X_D3DRS_PSCONSTANT0_0..X_D3DRS_PSCONSTANT0_7 : C0 for each stage
		// [-] DWORD    PSConstant1[8];            // X_D3DRS_PSCONSTANT1_0..X_D3DRS_PSCONSTANT1_7 : C1 for each stage
		// [*] DWORD    PSAlphaOutputs[8];         // X_D3DRS_PSALPHAOUTPUTS0..X_D3DRS_PSALPHAOUTPUTS7 : Alpha output for each stage
		// [*] DWORD    PSRGBInputs[8];            // X_D3DRS_PSRGBINPUTS0..X_D3DRS_PSRGBINPUTS7 : RGB inputs for each stage
		// [*] DWORD    PSCompareMode;             // X_D3DRS_PSCOMPAREMODE : Compare modes for clipplane texture mode
		if (memcmp(&(PSDef.PSAlphaOutputs[0]), &(Another.PSDef.PSAlphaOutputs[0]), (8 + 8 + 1) * sizeof(DWORD)) != 0)
			return false;

		// [-] DWORD    PSFinalCombinerConstant0;  // X_D3DRS_PSFINALCOMBINERCONSTANT0 : C0 in final combiner
		// [-] DWORD    PSFinalCombinerConstant1;  // X_D3DRS_PSFINALCOMBINERCONSTANT1 : C1 in final combiner
		// [*] DWORD    PSRGBOutputs[8];           // X_D3DRS_PSRGBOUTPUTS0..X_D3DRS_PSRGBOUTPUTS7 : Stage 0 RGB outputs
		// [*] DWORD    PSCombinerCount;           // X_D3DRS_PSCOMBINERCOUNT : Active combiner count (Stages 0-7)
		// [*] DWORD    PSTextureModes;            // X_D3DRS_PS_RESERVED (copied from out-of-range X_D3DRS_PSTEXTUREMODES) : Texture addressing modes
		// [*] DWORD    PSDotMapping;              // X_D3DRS_PSDOTMAPPING : Input mapping for dot product modes
		// [*] DWORD    PSInputTexture;            // X_D3DRS_PSINPUTTEXTURE : Texture source for some texture modes
		if (memcmp(&(PSDef.PSRGBOutputs[0]), &(Another.PSDef.PSRGBOutputs[0]), (8 + 1 + 1 + 1 + 1) * sizeof(DWORD)) != 0)
			return false;

		// [-] DWORD    PSC0Mapping;               // Mapping of c0 regs to D3D constants
		// [-] DWORD    PSC1Mapping;               // Mapping of c1 regs to D3D constants
		// [*] DWORD    PSFinalCombinerConstants;  // Final combiner constant mapping
		// Note : From PSFinalCombinerConstants, only the PS_GLOBALFLAGS_TEXMODE_ADJUST flag must correspond
		if (DecodedTexModeAdjust != Another.DecodedTexModeAdjust)
			return false;

		for (unsigned i = 0; i < X_D3DTS_STAGECOUNT; i++)
			if (AlphaKill[i] != Another.AlphaKill[i])
				return false;

		// All ActiveTextureTypes must correspond as well (otherwise the recompiled shader would sample incorrectly) :
		for (unsigned i = 0; i < X_D3DTS_STAGECOUNT; i++)
			if (ActiveTextureTypes[i] != Another.ActiveTextureTypes[i])
				return false;

		// Fail if they don't correspond in their use of the final combiner unit
		if (DecodedHasFinalCombiner != Another.DecodedHasFinalCombiner)
			return false;

		// If they don't use the final combiner unit
		if (!DecodedHasFinalCombiner) {
			// Fail if they don't correspond on the render states that impact AdjustFinalCombiner
			if (RenderStateFogEnable != Another.RenderStateFogEnable)
				return false;

			if (RenderStateSpecularEnable != Another.RenderStateSpecularEnable)
				return false;
		}

		return true;
	}

	void SnapshotRuntimeVariables()
	{

	}

	void AdjustTextureModes(DecodedRegisterCombiner& RC)
	{
		// if this flag is set, the texture mode for each texture stage is adjusted as follows:
		if (RC.TexModeAdjust) {
			for (int i = 0; i < X_D3DTS_STAGECOUNT; i++) {
				// First, disable not-assigned textures
				if (ActiveTextureTypes[i] == X_D3DRTYPE_NONE) {
					RC.PSTextureModes[i] = PS_TEXTUREMODES_NONE;
					continue;
				}

				// Then adjust some texture mode according to the currently active textures, so that the shader will use the appropriate sampling method
				switch (RC.PSTextureModes[i]) {
				case PS_TEXTUREMODES_PROJECT2D:
				case PS_TEXTUREMODES_PROJECT3D:
				case PS_TEXTUREMODES_CUBEMAP:
					if (ActiveTextureTypes[i] == X_D3DRTYPE_CUBETEXTURE)
						RC.PSTextureModes[i] = PS_TEXTUREMODES_CUBEMAP;
					else
						if (ActiveTextureTypes[i] == X_D3DRTYPE_VOLUMETEXTURE)
							// TODO : Also do this for DepthBuffers (but not EmuXBFormatIsLinear!) :
							// || EmuXBFormatIsDepthBuffer(GetXboxPixelContainerFormat(g_pXbox_SetTexture[i])) in { X_D3DFMT_D24S8, X_D3DFMT_F24S8, X_D3DFMT_D16, X_D3DFMT_F16}
							RC.PSTextureModes[i] = PS_TEXTUREMODES_PROJECT3D;
						else
							RC.PSTextureModes[i] = PS_TEXTUREMODES_PROJECT2D;
					break;
				case PS_TEXTUREMODES_DOT_STR_3D:
				case PS_TEXTUREMODES_DOT_STR_CUBE:
					if (ActiveTextureTypes[i] == X_D3DRTYPE_CUBETEXTURE)
						RC.PSTextureModes[i] = PS_TEXTUREMODES_DOT_STR_CUBE;
					else
						RC.PSTextureModes[i] = PS_TEXTUREMODES_DOT_STR_3D;
					break;
				}
			}
		}
		else {
			// Texture modes were specified manually - but fix them up if necessary
			for (int i = 0; i < X_D3DTS_STAGECOUNT; i++) {
				// Fixup sampling cube textures with PROJECT2D

				if (ActiveTextureTypes[i] == X_D3DRTYPE_CUBETEXTURE && RC.PSTextureModes[i] == PS_TEXTUREMODES_PROJECT2D) {
					printf("PROJECT2D sampling is used with a cubemap texture - using CUBEMAP sampling instead\n");
					RC.PSTextureModes[i] = PS_TEXTUREMODES_CUBEMAP;
				}

	
				if (ActiveTextureTypes[i] == X_D3DRTYPE_CUBETEXTURE && RC.PSTextureModes[i] == PS_TEXTUREMODES_DOT_STR_3D) {
					printf("DOT_STR_3D sampling is used with a cubemap texture - using DOT_STR_CUBE sampling instead\n");
					RC.PSTextureModes[i] = PS_TEXTUREMODES_DOT_STR_CUBE;
				}
			}
		}
	}

	void AdjustFinalCombiner(DecodedRegisterCombiner& RC)
	{
		if (RC.hasFinalCombiner) 
			return;

		// Since we're HLE'ing Xbox D3D, mimick how it configures the final combiner when PSDef doesn't :
		// TODO : Use the same final combiner when no pixel shader is set! Possibly by generating a DecodedRegisterCombiner with PSCombinerCount zero?
		// (This forms the entire Xbox fixed function pixel pipeline, which uses only two renderstates : X_D3DRS_SPECULARENABLE and X_D3DRS_SPECULARENABLE.)
		//
		// If X_D3DRS_FOGENABLE, configure final combiner to perform this operation :
		//   if (X_D3DRS_SPECULARENABLE) r0.rgb = lerp(fog.rgb, r0.rgb, fog.a) + v1.rgb;
		//                          else r0.rgb = lerp(fog.rgb, r0.rgb, fog.a);
		//   r0.a = abs(r0.a);
		// Otherwise, if not X_D3DRS_FOGENABLE, configure final combiner to perform this operation :
		//   if (X_D3DRS_SPECULARENABLE) r0.rgb = r0.rgb + v1.rgb;
		//                          else r0.rgb = r0.rgb;
		// Remember : 
		//   xfc.rgb = lerp(C, B, A) + D
		//   xfc.a = G.b
		// Whereby A, B, C and G can use the two xfc-special purpose registers :
		//   V1R0 = V1 + R0
		//   EFPROD = E * F
		// ( Or in shorthand : sum=r0+v1, prod=s4*s5, r0.rgb=s0*s1+{1-s0}*s2+s3, r0.a=s6.b )
		RC.FinalCombiner.Input[0/*A*/].Channel = PS_CHANNEL_ALPHA;
		RC.FinalCombiner.Input[0/*A*/].Reg = PS_REGISTER_FOG;
		RC.FinalCombiner.Input[1/*B*/].Reg = PS_REGISTER_R0;
		// If fog is disabled, blend R0 with itself
		RC.FinalCombiner.Input[2/*C*/].Reg = RenderStateFogEnable ? PS_REGISTER_FOG : PS_REGISTER_R0;
		RC.FinalCombiner.Input[3/*D*/].Reg = RenderStateSpecularEnable ? PS_REGISTER_V1 : PS_REGISTER_ZERO;
		RC.FinalCombiner.Input[4/*E*/].Reg = PS_REGISTER_ZERO; // Note : Not really needed, should be 0 already
		RC.FinalCombiner.Input[5/*F*/].Reg = PS_REGISTER_ZERO; // Note : Not really needed, should be 0 already
		RC.FinalCombiner.Input[6/*G*/].Reg = PS_REGISTER_R0;
		RC.FinalCombiner.Input[6/*G*/].Channel = PS_CHANNEL_ALPHA;
	}

	void PerformRuntimeAdjustments(DecodedRegisterCombiner& RC)
	{
		RC.AlphaKill[0] = AlphaKill[0];
		RC.AlphaKill[1] = AlphaKill[1];
		RC.AlphaKill[2] = AlphaKill[2];
		RC.AlphaKill[3] = AlphaKill[3];
		AdjustTextureModes(RC);
		AdjustFinalCombiner(RC);
	}
}
HostPSDef;



void RecompilePixelShader(HostPSDef& CompletePSDef)
{
	DecodedRegisterCombiner RC = {};
	RC.Decode(&(CompletePSDef.PSDef));
	CompletePSDef.PerformRuntimeAdjustments(RC);	
} 


// Mapping indices of Xbox register combiner constants to host pixel shader constants;
// The first 16 are identity-mapped (C0_1 .. C0_7 are C0 .. C7 on host, C1_0 .. C1_7 are C8 .. C15 on host) :
constexpr int PSH_XBOX_CONSTANT_C0 = 0; // = 0..15
// Then two final combiner constants :
constexpr int PSH_XBOX_CONSTANT_FC0 = PSH_XBOX_CONSTANT_C0 + PSH_XBOX_MAX_C_REGISTER_COUNT; // = 16
constexpr int PSH_XBOX_CONSTANT_FC1 = PSH_XBOX_CONSTANT_FC0 + 1; // = 17
// Fog requires a constant (as host PS1.4 doesn't support the FOG register)
constexpr int PSH_XBOX_CONSTANT_FOG = PSH_XBOX_CONSTANT_FC1 + 1; // = 18
// Bump Environment Material registers
constexpr int PSH_XBOX_CONSTANT_BEM = PSH_XBOX_CONSTANT_FOG + 1; // = 19..22
// Bump map Luminance registers
constexpr int PSH_XBOX_CONSTANT_LUM = PSH_XBOX_CONSTANT_BEM + 4; // = 23..26
// Which winding order to consider as the front face
constexpr int PSH_XBOX_CONSTANT_FRONTFACE_FACTOR = PSH_XBOX_CONSTANT_LUM + 4; // = 27
// Fog table information {Table mode, density, start and end}
constexpr int CXBX_D3DPS_CONSTREG_FOGINFO = PSH_XBOX_CONSTANT_FRONTFACE_FACTOR + 1; // = 28
//Fog enable flag
constexpr int PSH_XBOX_CONSTANT_FOGENABLE = CXBX_D3DPS_CONSTREG_FOGINFO + 1; // = 29
// This concludes the set of constants that need to be set on host :
constexpr int PSH_XBOX_CONSTANT_MAX = PSH_XBOX_CONSTANT_FOGENABLE + 1; // = 30

std::string_view GetD3DTOPString(int d3dtop) 
{
	static constexpr std::string_view opToString[] = {
#ifdef ENABLE_FF_ALPHAKILL
		"X_D3DTOP_DISABLE", // 0 (Was UNDEFINED, but that doesn't compile)
#else
		"UNDEFINED", // 0
#endif
		"X_D3DTOP_DISABLE", // 1
		"X_D3DTOP_SELECTARG1", // 2
		"X_D3DTOP_SELECTARG2", // 3
		"X_D3DTOP_MODULATE", // 4
		"X_D3DTOP_MODULATE2X", // 5
		"X_D3DTOP_MODULATE4X", // 6
		"X_D3DTOP_ADD", // 7
		"X_D3DTOP_ADDSIGNED", // 8
		"X_D3DTOP_ADDSIGNED2X", // 9
		"X_D3DTOP_SUBTRACT", // 10
		"X_D3DTOP_ADDSMOOTH", // 11
		"X_D3DTOP_BLENDDIFFUSEALPHA", // 12
		"X_D3DTOP_BLENDCURRENTALPHA", // 13
		"X_D3DTOP_BLENDTEXTUREALPHA", // 14
		"X_D3DTOP_BLENDFACTORALPHA", // 15
		"X_D3DTOP_BLENDTEXTUREALPHAPM", // 16
		"X_D3DTOP_PREMODULATE", // 17
		"X_D3DTOP_MODULATEALPHA_ADDCOLOR", // 18
		"X_D3DTOP_MODULATECOLOR_ADDALPHA", // 19
		"X_D3DTOP_MODULATEINVALPHA_ADDCOLOR", // 20
		"X_D3DTOP_MODULATEINVCOLOR_ADDALPHA", // 21
		"X_D3DTOP_DOTPRODUCT3", // 22
		"X_D3DTOP_MULTIPLYADD", // 23
		"X_D3DTOP_LERP", // 24
		"X_D3DTOP_BUMPENVMAP", // 25
		"X_D3DTOP_BUMPENVMAPLUMINANCE", // 26
	};

#ifdef ENABLE_FF_ALPHAKILL
	if (d3dtop < 0 || d3dtop > 26) {
#else
	if (d3dtop < 1 || d3dtop > 26) {
#endif
		printf("Unmapped texture operation %d\n", d3dtop);
		d3dtop = 0; // undefined
	}

	return opToString[d3dtop];
	}


const float X_D3DTA_COMPLEMENT = 0x00000010;  // take 1.0 - x (read modifier)
const float X_D3DTA_ALPHAREPLICATE = 0x00000020;  // replicate alpha to color components (read modifier)
// Get a string equivalent of '<Texture Argument> + <Modifier>'
std::string GetD3DTASumString(int d3dta, bool allowModifier = true)
{


	static const std::string argToString[] = {
		"X_D3DTA_DIFFUSE", // 0
		"X_D3DTA_CURRENT", // 1
		"X_D3DTA_TEXTURE", // 2
		"X_D3DTA_TFACTOR", // 3
		"X_D3DTA_SPECULAR", // 4
		"X_D3DTA_TEMP", // 5
		"X_D3DTA_CONSTANT", // 6
		"UNDEFINED", // 7
	};

	// Write a texture argument
	const int flagMask = 0x30;
	int iFlags = d3dta & flagMask;
	int i = d3dta & ~flagMask;

	if (i < 0 || i > 6) {
		printf("Unmapped texture argument %d on texture arg\n", i);
		i = 7; // undefined
	}

	auto str = argToString[i];
	if (iFlags) {
		if (!allowModifier) {
			printf("Modifier not expected on texture argument\n");
		}

		if (iFlags == X_D3DTA_COMPLEMENT)
			str += " + X_D3DTA_COMPLEMENT";
		else if (iFlags == X_D3DTA_ALPHAREPLICATE)
			str += " + X_D3DTA_ALPHAREPLICATE";
		else {
			printf("Unmapped texture modifier %d\n", iFlags);
			str += " /* + UNKNOWN MODIFIER */";
		}
	}

	return str;
}