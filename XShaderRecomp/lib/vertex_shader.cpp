
// Original code (mostly) by CXBX team

//#define _DEBUG_TRACK_VS

#include <sstream>
#include <unordered_map>
#include <array>
#include <bitset>
#include <filesystem>
#include "vertex_shader.h"
#include "shader.h"
#include <map>



static const char* vs_model_ = "vs_6_0";

// ****************************************************************************
// * Vertex shader function recompiler
// ****************************************************************************

namespace XboxVertexShaderDecoder
{
	// Xbox Vertex SHader microcode types

	enum VSH_OUTPUT_TYPE {
		OUTPUT_C = 0,
		OUTPUT_O
	};

	enum VSH_OUTPUT_MUX {
		OMUX_MAC = 0,
		OMUX_ILU
	};

	// Host intermediate vertex shader types

	enum VSH_FIELD_NAME {
		FLD_ILU = 0,
		FLD_MAC,
		FLD_CONST,
		FLD_V,
		// Input A
		FLD_A_NEG,
		FLD_A_SWZ_X,
		FLD_A_SWZ_Y,
		FLD_A_SWZ_Z,
		FLD_A_SWZ_W,
		FLD_A_R,
		FLD_A_MUX,
		// Input B
		FLD_B_NEG,
		FLD_B_SWZ_X,
		FLD_B_SWZ_Y,
		FLD_B_SWZ_Z,
		FLD_B_SWZ_W,
		FLD_B_R,
		FLD_B_MUX,
		// Input C
		FLD_C_NEG,
		FLD_C_SWZ_X,
		FLD_C_SWZ_Y,
		FLD_C_SWZ_Z,
		FLD_C_SWZ_W,
		FLD_C_R_HIGH,
		FLD_C_R_LOW,
		FLD_C_MUX,
		// Output
		FLD_OUT_MAC_MASK,
		FLD_OUT_R,
		FLD_OUT_ILU_MASK,
		FLD_OUT_O_MASK,
		FLD_OUT_ORB,
		FLD_OUT_ADDRESS,
		FLD_OUT_MUX,
		// Relative addressing
		FLD_A0X,
		// Final instruction
		FLD_FINAL
	};

	// Retrieves a number of bits in the instruction token
	static inline uint32_t VshGetFromToken(
		uint32_t* pShaderToken,
		uint8_t SubToken,
		uint8_t StartBit,
		uint8_t BitLength)
	{
		return (pShaderToken[SubToken] >> StartBit) & ~(0xFFFFFFFF << BitLength);
	}

	static uint8_t VshGetField(
		uint32_t* pShaderToken,
		VSH_FIELD_NAME FieldName)
	{
		// Used for xvu spec definition
		static const struct {
			uint8_t          SubToken;
			uint8_t          StartBit;
			uint8_t          BitLength;
		} FieldMapping[/*VSH_FIELD_NAME*/] = {
			// SubToken BitPos  BitSize
			{  1,   25,     3 }, // FLD_ILU,              
			{  1,   21,     4 }, // FLD_MAC,              
			{  1,   13,     8 }, // FLD_CONST,            
			{  1,    9,     4 }, // FLD_V,                
			// Input A
			{  1,    8,     1 }, // FLD_A_NEG,            
			{  1,    6,     2 }, // FLD_A_SWZ_X,          
			{  1,    4,     2 }, // FLD_A_SWZ_Y,          
			{  1,    2,     2 }, // FLD_A_SWZ_Z,          
			{  1,    0,     2 }, // FLD_A_SWZ_W,          
			{  2,   28,     4 }, // FLD_A_R,              
			{  2,   26,     2 }, // FLD_A_MUX,            
			// Input B
			{  2,   25,     1 }, // FLD_B_NEG,            
			{  2,   23,     2 }, // FLD_B_SWZ_X,          
			{  2,   21,     2 }, // FLD_B_SWZ_Y,          
			{  2,   19,     2 }, // FLD_B_SWZ_Z,          
			{  2,   17,     2 }, // FLD_B_SWZ_W,          
			{  2,   13,     4 }, // FLD_B_R,              
			{  2,   11,     2 }, // FLD_B_MUX,            
			// Input C
			{  2,   10,     1 }, // FLD_C_NEG,            
			{  2,    8,     2 }, // FLD_C_SWZ_X,          
			{  2,    6,     2 }, // FLD_C_SWZ_Y,          
			{  2,    4,     2 }, // FLD_C_SWZ_Z,          
			{  2,    2,     2 }, // FLD_C_SWZ_W,          
			{  2,    0,     2 }, // FLD_C_R_HIGH,         
			{  3,   30,     2 }, // FLD_C_R_LOW,          
			{  3,   28,     2 }, // FLD_C_MUX,            
			// Output
			{  3,   24,     4 }, // FLD_OUT_MAC_MASK,   
			{  3,   20,     4 }, // FLD_OUT_R,            
			{  3,   16,     4 }, // FLD_OUT_ILU_MASK,
			{  3,   12,     4 }, // FLD_OUT_O_MASK,
			{  3,   11,     1 }, // FLD_OUT_ORB,          
			{  3,    3,     8 }, // FLD_OUT_ADDRESS,      
			{  3,    2,     1 }, // FLD_OUT_MUX,          
			// Relative addressing
			{  3,    1,     1 }, // FLD_A0X,              
			// Final instruction
			{  3,    0,     1 }  // FLD_FINAL,            
		};

		return (uint8_t)(VshGetFromToken(pShaderToken,
			FieldMapping[FieldName].SubToken,
			FieldMapping[FieldName].StartBit,
			FieldMapping[FieldName].BitLength));
	}

	// Converts the C register address to disassembly format
	static inline int16_t ConvertCRegister(const int16_t CReg)
	{
		return ((((CReg >> 5) & 7) - 3) * 32) + (CReg & 31);
	}

	static VSH_IMD_PARAMETER VshGetIntermediateParam(
		uint32_t* pShaderToken,
		VSH_FIELD_NAME FLD_MUX,
		VSH_FIELD_NAME FLD_NEG,
		uint16_t R,
		uint16_t V,
		uint16_t C)
	{
		VSH_IMD_PARAMETER param{};
		param.Type = (VSH_IMD_PARAMETER_TYPE)VshGetField(pShaderToken, FLD_MUX);
		switch (param.Type) {
		case PARAM_R:
			param.Address = R;
			break;
		case PARAM_V:
			param.Address = V;
			break;
		case PARAM_C:
			param.Address = C;
			break;
		default:
			printf("parameter type unknown\n");
		}

		int d = FLD_NEG - FLD_A_NEG;
		param.Neg = VshGetField(pShaderToken, (VSH_FIELD_NAME)(d + FLD_A_NEG)) > 0;
		param.Swizzle[0] = (VSH_SWIZZLE)VshGetField(pShaderToken, (VSH_FIELD_NAME)(d + FLD_A_SWZ_X));
		param.Swizzle[1] = (VSH_SWIZZLE)VshGetField(pShaderToken, (VSH_FIELD_NAME)(d + FLD_A_SWZ_Y));
		param.Swizzle[2] = (VSH_SWIZZLE)VshGetField(pShaderToken, (VSH_FIELD_NAME)(d + FLD_A_SWZ_Z));
		param.Swizzle[3] = (VSH_SWIZZLE)VshGetField(pShaderToken, (VSH_FIELD_NAME)(d + FLD_A_SWZ_W));

		return param;
	}

	static bool VshConvertToIntermediate(uint32_t* pShaderToken, IntermediateVertexShader* pShader)
	{
		// First get the instruction(s).
		VSH_ILU ILU = (VSH_ILU)VshGetField(pShaderToken, FLD_ILU);
		VSH_MAC MAC = (VSH_MAC)VshGetField(pShaderToken, FLD_MAC);
		if (MAC > MAC_ARL)
			printf("Unknown MAC\n");

		// MAC,ILU output R register
		int16_t RAddress = VshGetField(pShaderToken, FLD_OUT_R);

		// Test for paired opcodes
		bool bIsPaired = (MAC != MAC_NOP) && (ILU != ILU_NOP);

		VSH_IMD_MAC_OP MacOp{};
		VSH_IMD_ILU_OP IluOp{};

		// Set up input registers
		int16_t AR = VshGetField(pShaderToken, FLD_A_R);
		int16_t BR = VshGetField(pShaderToken, FLD_B_R);
		int16_t CR = VshGetField(pShaderToken, FLD_C_R_HIGH) << 2 | VshGetField(pShaderToken, FLD_C_R_LOW);
		int16_t V = VshGetField(pShaderToken, FLD_V);
		int16_t C = ConvertCRegister(VshGetField(pShaderToken, FLD_CONST));

		// Check if there's a MAC opcode
		if (MAC != MAC_NOP && MAC <= MAC_ARL) {
			MacOp.Opcode = MAC;

			if (bIsPaired && RAddress == 1) {
				// Ignore paired MAC opcodes that write to R1
			}
			else if (MAC == MAC_ARL) {
				MacOp.Dest.Type = IMD_DEST_A0X;
				MacOp.Dest.Mask = MASK_X;
			}
			else {
				MacOp.Dest.Type = IMD_DEST_R;
				MacOp.Dest.Address = RAddress;
				MacOp.Dest.Mask = VshGetField(pShaderToken, FLD_OUT_MAC_MASK);
			}

			if (MAC >= MAC_MOV) {
				MacOp.Parameters[MacOp.ParamCount++] = VshGetIntermediateParam(pShaderToken, FLD_A_MUX, FLD_A_NEG, AR, V, C);
			}

			if (MAC == MAC_MUL || (MAC >= MAC_MAD && MAC <= MAC_SGE)) {
				MacOp.Parameters[MacOp.ParamCount++] = VshGetIntermediateParam(pShaderToken, FLD_B_MUX, FLD_B_NEG, BR, V, C);
			}

			if (MAC == MAC_ADD || MAC == MAC_MAD) {
				MacOp.Parameters[MacOp.ParamCount++] = VshGetIntermediateParam(pShaderToken, FLD_C_MUX, FLD_C_NEG, CR, V, C);
			}
		}

		// Check if there's an ILU opcode
		if (ILU != ILU_NOP) {
			// Paired ILU opcodes will only write to R1
			IluOp.Opcode = ILU;
			IluOp.Dest.Type = IMD_DEST_R;
			IluOp.Dest.Address = bIsPaired ? 1 : RAddress;
			IluOp.Dest.Mask = VshGetField(pShaderToken, FLD_OUT_ILU_MASK);
			IluOp.Parameter = VshGetIntermediateParam(pShaderToken, FLD_C_MUX, FLD_C_NEG, CR, V, C);
		}

		// Output register
		VSH_OUTPUT_MUX OutputMux = (VSH_OUTPUT_MUX)VshGetField(pShaderToken, FLD_OUT_MUX);
		int16_t OutputAddress = VshGetField(pShaderToken, FLD_OUT_ADDRESS);
		VSH_IMD_DEST_TYPE OutputType;
		if ((VSH_OUTPUT_TYPE)VshGetField(pShaderToken, FLD_OUT_ORB) == OUTPUT_C) {
			OutputType = IMD_DEST_C;
			OutputAddress = ConvertCRegister(OutputAddress);
		}
		else { // OUTPUT_O:
			OutputType = IMD_DEST_O;
			OutputAddress = OutputAddress & 0xF;
		}

		VSH_IMD_INSTR imd{};
		imd.MAC = MacOp;
		imd.ILU = IluOp;
		imd.IndexesWithA0_X = VshGetField(pShaderToken, FLD_A0X) > 0;
		imd.ORegSource = OutputMux == OMUX_MAC ? SRC_MAC : SRC_ILU;
		imd.ORegDest.Type = OutputType;
		imd.ORegDest.Address = OutputAddress;
		imd.ORegDest.Mask = VshGetField(pShaderToken, FLD_OUT_O_MASK);

		pShader->Instructions.push_back(imd);

		return VshGetField(pShaderToken, FLD_FINAL) == 0;
	}
};

// Get the function size excluding the final field
size_t GetVshFunctionSize(uint32_t* pXboxFunction) {
	auto curToken = (uint32_t*)pXboxFunction;

	while (!XboxVertexShaderDecoder::VshGetField(curToken, XboxVertexShaderDecoder::FLD_FINAL)) {
		curToken += X_VSH_INSTRUCTION_SIZE; // TODO use a struct to represent these instructions
	}

	curToken += X_VSH_INSTRUCTION_SIZE; // For the final instruction

	return (curToken - pXboxFunction) * sizeof(uint32_t);
}



void DestRegisterHlsl(std::stringstream& hlsl, VSH_IMD_DEST& dest) {
	static const char* OReg_Name[/*VSH_OREG_NAME*/] = {
		"oPos",
		"???",
		"???",
		"oD0",
		"oD1",
		"oFog",
		"oPts",
		"oB0",
		"oB1",
		"oT0",
		"oT1",
		"oT2",
		"oT3",
		"???",
		"???",
		"a0.x"
	};

	switch (dest.Type) {
	case IMD_DEST_C:
		// Access the HLSL capital C[] constants array, with the index bias applied :
		// TODO : Avoid out-of-bound writes (perhaps writing to a reserved index?)
		hlsl << "C[" << dest.Address + X_D3DSCM_CORRECTION << "]";
		printf("Vertex shader writes to constant table\n");
		break;
	case IMD_DEST_R:
		hlsl << "r" << dest.Address;
		break;
	case IMD_DEST_O:
		assert(dest.Address < OREG_A0X);
		hlsl << OReg_Name[dest.Address];
		break;
	case IMD_DEST_A0X:
		hlsl << "a0";
		break;
	default:
		assert(false);
		break;
	}
}

void DestMaskHlsl(std::stringstream& hlsl, VSH_IMD_DEST& dest)
{
	// Write the mask as a separate argument to the opcode defines
	// (No space, so that "dest,mask, ..." looks close to "dest.mask, ...")
	hlsl << ",";

	// Detect oFog masks other than x
	if (dest.Type == IMD_DEST_O &&
		dest.Address == OREG_OFOG &&
		dest.Mask != MASK_X)
	{
		printf("Vertex shader uses oFog mask other than x\n");
		printf("WARNING oFog mask was %#x\n", dest.Mask);
		hlsl << "x"; // write to x instead
		return;
	}

	// Write the mask
	if (dest.Mask & MASK_X) hlsl << "x";
	if (dest.Mask & MASK_Y) hlsl << "y";
	if (dest.Mask & MASK_Z) hlsl << "z";
	if (dest.Mask & MASK_W) hlsl << "w";
}

void ParameterHlsl(std::stringstream& hlsl, VSH_IMD_PARAMETER& param, bool IndexesWithA0_X, bool useTemp)
{
	static const char* RegisterName[/*VSH_PARAMETER_TYPE*/] = {
		"?", // PARAM_UNKNOWN = 0,
		"r", // PARAM_R,          // Temporary (scRatch) registers
		"v", // PARAM_V,          // Vertex registers
		"c", // PARAM_C,          // Constant registers, set by SetVertexShaderConstant
		"oPos" // PARAM_O // = 0??
	};

	if (param.Neg) {
		hlsl << "-";
	}

	if (useTemp) {
		hlsl << "temp";
	}
	else if (param.Type == PARAM_C) {
		// Access constant registers through our HLSL c() function,
		// which allows dumping negative indices (like Xbox shaders),
		// and which returns zero when out-of-bounds indices are passed in:
		if (IndexesWithA0_X) {
			if (param.Address == 0) {
				hlsl << "c(a0.x)"; // Hide the offset if it's 0
			}
			else if (param.Address < 0) {
				hlsl << "c(a0.x" << param.Address << ")"; // minus is part of the offset
			}
			else {
				hlsl << "c(a0.x+" << param.Address << ")"; // show addition character
			}
		}
		else {
			hlsl << "c(" << param.Address << ")";
		}
	}
	else {
		hlsl << RegisterName[param.Type] << param.Address;
	}

	// Write the swizzle if we need to
	// Only bother printing the swizzle if it is not the default .xyzw
	if (!(param.Swizzle[0] == SWIZZLE_X &&
		param.Swizzle[1] == SWIZZLE_Y &&
		param.Swizzle[2] == SWIZZLE_Z &&
		param.Swizzle[3] == SWIZZLE_W)) {
		// We'll try to simplify swizzles if we can
		// If all swizzles are the same, we only need to write one out
		unsigned swizzles = 1;

		// Otherwise, we need to use the full swizzle
		if (param.Swizzle[0] != param.Swizzle[1] ||
			param.Swizzle[0] != param.Swizzle[2] ||
			param.Swizzle[0] != param.Swizzle[3]) {
			// Note, we can't remove trailing repeats, like in VS asm,
			// as it may change the type from float4 to float3, float2 or float1!
			swizzles = 4;
		}

		hlsl << ".";
		for (unsigned i = 0; i < swizzles; i++) {
			hlsl << "xyzw"[param.Swizzle[i]];
		}
	}
}

void BuildShader(IntermediateVertexShader* pShader, std::stringstream& hlsl)
{
	// HLSL strings for all MAC opcodes, indexed with VSH_MAC
	static std::string VSH_MAC_HLSL[/*VSH_MAC*/] = {
		/*MAC_NOP:*/"",
		/*MAC_MOV:*/"x_mov",
		/*MAC_MUL:*/"x_mul",
		/*MAC_ADD:*/"x_add",
		/*MAC_MAD:*/"x_mad",
		/*MAC_DP3:*/"x_dp3",
		/*MAC_DPH:*/"x_dph",
		/*MAC_DP4:*/"x_dp4",
		/*MAC_DST:*/"x_dst",
		/*MAC_MIN:*/"x_min",
		/*MAC_MAX:*/"x_max",
		/*MAC_SLT:*/"x_slt",
		/*MAC_SGE:*/"x_sge",
		/*MAC_ARL:*/"x_arl",
					"",
					"" // VSH_MAC 2 final values of the 4 bits are undefined/unknown  TODO : Investigate their effect (if any) and emulate that as well
	};

	// HLSL strings for all ILU opcodes, indexed with VSH_ILU
	static std::string VSH_ILU_HLSL[/*VSH_ILU*/] = {
		/*ILU_NOP:*/"",
		/*ILU_MOV:*/"x_mov",
		/*ILU_RCP:*/"x_rcp",
		/*ILU_RCC:*/"x_rcc",
		/*ILU_RSQ:*/"x_rsq",
		/*ILU_EXP:*/"x_expp",
		/*ILU_LOG:*/"x_logp",
		/*ILU_LIT:*/"x_lit" // = 7 - all values of the 3 bits are used
	};

	auto WriteOp = [&](
		const std::string& opcode,
		VSH_IMD_DEST dest,
		int paramCount, VSH_IMD_PARAMETER* params,
		bool indexesWithA0_X,
		bool iluUseTempParam
		) {
			// opcode(dest, a, b, c);
			hlsl << "\n  " << opcode << "(";

			DestRegisterHlsl(hlsl, dest);
			DestMaskHlsl(hlsl, dest);

			for (int i = 0; i < paramCount; i++) {
				hlsl << ", ";
				ParameterHlsl(hlsl, params[i], indexesWithA0_X, iluUseTempParam);
			}

			hlsl << ");";
		};

	for (size_t i = 0; i < pShader->Instructions.size(); i++) {
		VSH_IMD_INSTR& in = pShader->Instructions[i];

		// Paired if both MAC and ILU write to a dest register
		bool isPaired =
			in.MAC.Opcode != MAC_NOP &&
			in.ILU.Opcode != ILU_NOP &&
			(in.MAC.Dest.Mask || in.ORegSource == SRC_MAC) &&
			(in.ILU.Dest.Mask || in.ORegSource == SRC_ILU);

		// If there are two "paired" instructions that need to run "simultaneously",
		// we need to prevent the output of the first instruction interfering
		// with the input of the second instruction
		// If the MAC output is the same as the ILU input
		// we will use a temp variable to hold the ILU input
		VSH_IMD_DEST* iluTemp = nullptr;
		if (isPaired) {
			if (in.MAC.Dest.Address == in.ILU.Parameter.Address &&
				(in.MAC.Dest.Type == IMD_DEST_C && in.ILU.Parameter.Type == PARAM_C ||
					in.MAC.Dest.Type == IMD_DEST_R && in.ILU.Parameter.Type == PARAM_R ||
					in.MAC.Dest.Type == IMD_DEST_A0X && in.ILU.Parameter.Type == PARAM_C && in.IndexesWithA0_X)) {
				// Normal MAC output matches ILU input
				iluTemp = &in.MAC.Dest;
			}
			else if (in.ORegSource == SRC_MAC &&
				in.ORegDest.Type == IMD_DEST_O && in.ORegDest.Address == 0 &&
				in.ILU.Parameter.Type == PARAM_R && in.ILU.Parameter.Address == 12) {
				// OReg MAC output matches ILU input
				// Note oPos is the same as r12
				iluTemp = &in.ORegDest;
			}

			if (iluTemp) {
				// MAC and ILU use the same register.
				// This is fine unless the ILU op uses a component written to by the MAC op
				bool conflict = false;
				for (int s = 0; s < 4; s++) {
					auto swizzle = in.ILU.Parameter.Swizzle[s];
					if (iluTemp->Mask & MASK_X && swizzle == SWIZZLE_X ||
						iluTemp->Mask & MASK_Y && swizzle == SWIZZLE_Y ||
						iluTemp->Mask & MASK_Z && swizzle == SWIZZLE_Z ||
						iluTemp->Mask & MASK_W && swizzle == SWIZZLE_W) {
						conflict = true;
						break;
					}
				}
				if (!conflict) {
					iluTemp = nullptr; // We don't need a temp after all
				}
			}
		}

		if (iluTemp) {
			// Write the ILU input to a temp
			hlsl << "\n  " << "temp = ";
			DestRegisterHlsl(hlsl, *iluTemp);
			hlsl << ";";
		}

		// Write MAC op
		if (in.MAC.Opcode != MAC_NOP) {
			if (in.MAC.Dest.Mask) {
				WriteOp(VSH_MAC_HLSL[in.MAC.Opcode], in.MAC.Dest, in.MAC.ParamCount, in.MAC.Parameters, in.IndexesWithA0_X, false);
			}
			if (in.ORegSource == SRC_MAC && in.ORegDest.Mask) {
				WriteOp(VSH_MAC_HLSL[in.MAC.Opcode], in.ORegDest, in.MAC.ParamCount, in.MAC.Parameters, in.IndexesWithA0_X, false);
			}
		}

		// Write ILU op
		if (in.ILU.Opcode != ILU_NOP) {
			if (in.ILU.Dest.Mask) {
				WriteOp(VSH_ILU_HLSL[in.ILU.Opcode], in.ILU.Dest, 1, &in.ILU.Parameter, in.IndexesWithA0_X, iluTemp);
			}
			if (in.ORegSource == SRC_ILU && in.ORegDest.Mask) {
				WriteOp(VSH_ILU_HLSL[in.ILU.Opcode], in.ORegDest, 1, &in.ILU.Parameter, in.IndexesWithA0_X, iluTemp);
			}
		}

		hlsl << "\n"; // Group operations by instruction
	}
}

extern HRESULT CompileShader
(
	std::string hlsl_str,
	const char* shader_profile,
	IDxcBlob** ppHostShader,
	const char* pSourceName,
	bool compileSpirv = false
);

#include <fstream>
// recompile xbox vertex shader function
void CompileVertexShader
(
	IntermediateVertexShader* pIntermediateShader,
	IDxcBlob** ppHostShader,
	const int32_t type,
	bool exportHLSL)
{
	assert(pIntermediateShader->Instructions.size() > 0);

	// Combine the shader template with the shader program
	auto hlsl_stream = std::stringstream();
	hlsl_stream << g_ShaderSources.vertexShaderTemplateHlsl[type][0]; // Start with the HLSL template header
	BuildShader(pIntermediateShader, hlsl_stream);
	hlsl_stream << g_ShaderSources.vertexShaderTemplateHlsl[type][1]; // Finish with the HLSL template footer
	std::string hlsl_str = hlsl_stream.str();

	if (exportHLSL)
	{
		static int count;
		//printf("Create Vertex Shader ID %d\n", count);
		std::string debugName = "VertexShader" + std::to_string(count++) + (std::string)".hlsl";
		std::ofstream  outFile2(debugName, std::ios::app);
		//outFile2 << std::hex << shaderHash << '\n' << '\n';

		outFile2 << hlsl_str << '\n';
		outFile2.close();

	}

	std::string s = template_vs[type] + ".hlsl";
	const char* notionalSourceName = s.c_str();
	CompileShader(hlsl_str, vs_model_, ppHostShader, notionalSourceName);

}


Microsoft::WRL::ComPtr<IDxcBlob> AsyncCreateVertexShader(IntermediateVertexShader intermediateShader, bool exportHLSL) {


	Microsoft::WRL::ComPtr<IDxcBlob> pCompiledShader;
	IDxcBlob* rawPtr = nullptr;

	CompileVertexShader(
		&intermediateShader,
		&pCompiledShader,
		0, //for now default to 0 we will add detection later through vertex declaration and instruction analysis
		exportHLSL
	);


	pCompiledShader.Attach(rawPtr); // Attach the raw pointer to the ComPtr, taking ownership of it


	return pCompiledShader;
}

struct LazyVertexShader {
	bool isReady = false;
	void* pHostVertexShader = nullptr;
	int referenceCount = 0;
	std::vector<uint8_t> bytecode;
	// Store the compiled blob directly instead of future
	Microsoft::WRL::ComPtr<IDxcBlob> compiledBlob;
};

class ShaderCache {
public:
	static ShaderCache& Instance() {
		static ShaderCache instance;
		return instance;
	}

	LazyVertexShader* AddShader(LazyVertexShader&& shader) {
		std::lock_guard<std::mutex> lock(mutex_);
		shaders_.push_back(std::move(shader));
		return &shaders_.back();
	}

	void Clear() {
		std::lock_guard<std::mutex> lock(mutex_);
		shaders_.clear();
	}

private:
	std::vector<LazyVertexShader> shaders_;
	std::mutex mutex_;
};

extern void ParseVshFunction
(
	// Pointer to raw Xbox vertex shader instruction slots
	DWORD* pXboxFunction,
	IntermediateVertexShader* pShader
)
{
	// Decode the vertex shader program tokens into an intermediate representation
	auto pCurToken = (uint32_t*)pXboxFunction;

	// Decode until we hit a token marked final
	// Note : CxbxSetVertexShaderSlots makes sure this always stops
	// after X_VSH_MAX_INSTRUCTION_COUNT, by setting FLD_FINAL in there.
	while (XboxVertexShaderDecoder::VshConvertToIntermediate(pCurToken, pShader)) {
		pCurToken += X_VSH_INSTRUCTION_SIZE;
	}
}

const uint8_t* CreateRecompiledShader(uint32_t* pXboxFunction, DWORD* pXboxFunctionSize, size_t* outSize, bool exportHLSL)
{
	IntermediateVertexShader intermediateShader;

	*pXboxFunctionSize = GetVshFunctionSize(pXboxFunction);

	// Parse into intermediate format
	ParseVshFunction((DWORD*)pXboxFunction, &intermediateShader);

	// We're going to create a new shader
	auto newShader = LazyVertexShader();
	newShader.referenceCount = 1;

	if (intermediateShader.Instructions.empty() == false)
	{
		// Use std::async with the fixed function
		auto compileResult = std::async(
			std::launch::async,
			AsyncCreateVertexShader,
			std::move(intermediateShader),  // Move to avoid copy issues
			exportHLSL
		);

		newShader.compiledBlob = compileResult.get();

		// Copy to bytecode buffer
		newShader.bytecode.resize(newShader.compiledBlob->GetBufferSize());
		memcpy(
			newShader.bytecode.data(),
			newShader.compiledBlob->GetBufferPointer(),
			newShader.compiledBlob->GetBufferSize()
		);
		newShader.isReady = true;

		// Store in library-owned cache
		auto* cachedShader = ShaderCache::Instance().AddShader(std::move(newShader));

		*outSize = cachedShader->bytecode.size();
		return cachedShader->bytecode.data();  // Return pointer to library-owned memory
	}
	else
	{
		printf("[XShaderRecomp] WARNING: Empty vertex shader function\n");
	}

	return nullptr;
}