#include "pch.h"
#include <array>
#include <algorithm>
#include "vertex_declaration.h"
#include <map>
#include "vertex_shader.h"

//original code (mostly) re used from CXBX Reloaded

std::unordered_map<VertexDeclarationKey, HostVertexDeclaration*> g_HostVertexDeclarations;

class XboxVertexDeclarationConverter
{
protected:
	// Internal variables
	HostVertexDeclaration* pCurrentVertexDeclaration;
	HostVertexShaderStreamInfo* pCurrentVertexShaderStreamInfo = nullptr;
	bool IsFixedFunction;
	D3DVERTEXELEMENT9* pCurrentHostVertexElement;
	std::array<bool, 16> RegVIsPresentInDeclaration;

private:
#define D3DDECLUSAGE_UNSUPPORTED ((D3DDECLUSAGE)-1)

	D3DDECLUSAGE Xb2PCRegisterType(DWORD VertexRegister, BYTE& UsageIndex)
	{
		UsageIndex = 0;
		switch (VertexRegister) {
		case X_D3DVSDE_POSITION    /*= 0*/:
			return D3DDECLUSAGE_POSITION;
		case X_D3DVSDE_BLENDWEIGHT /*= 1*/:
			return D3DDECLUSAGE_BLENDWEIGHT;
		case X_D3DVSDE_NORMAL      /*= 2*/:
			return D3DDECLUSAGE_NORMAL;
		case X_D3DVSDE_DIFFUSE     /*= 3*/:
			return D3DDECLUSAGE_COLOR;
		case X_D3DVSDE_SPECULAR    /*= 4*/:
			UsageIndex = 1;
			return D3DDECLUSAGE_COLOR;
		case X_D3DVSDE_FOG         /*= 5*/:
			return D3DDECLUSAGE_FOG;
		case X_D3DVSDE_POINTSIZE   /*= 6*/:
			return D3DDECLUSAGE_PSIZE;
		case X_D3DVSDE_BACKDIFFUSE /*= 7*/:
			UsageIndex = 2;
			return D3DDECLUSAGE_COLOR;
		case X_D3DVSDE_BACKSPECULAR/*= 8*/:
			UsageIndex = 3;
			return D3DDECLUSAGE_COLOR;
		case X_D3DVSDE_TEXCOORD0   /*= 9*/:
			return D3DDECLUSAGE_TEXCOORD;
		case X_D3DVSDE_TEXCOORD1   /*=10*/:
			UsageIndex = 1;
			return D3DDECLUSAGE_TEXCOORD;
		case X_D3DVSDE_TEXCOORD2   /*=11*/:
			UsageIndex = 2;
			return D3DDECLUSAGE_TEXCOORD;
		case X_D3DVSDE_TEXCOORD3   /*=12*/:
			UsageIndex = 3;
			return D3DDECLUSAGE_TEXCOORD;
			// Unused registers. Assign them a semantic anyway so we don't have to worry about
			// binding a vertex declaration with them in it
		case 13: UsageIndex = 4; return D3DDECLUSAGE_TEXCOORD;
		case 14: UsageIndex = 5; return D3DDECLUSAGE_TEXCOORD;
		case 15: UsageIndex = 6; return D3DDECLUSAGE_TEXCOORD;
		default:
			return D3DDECLUSAGE_UNSUPPORTED;
		}
	}

	// VERTEX SHADER

	bool VshConvertToken_STREAMDATA_REG(DWORD VertexRegister, GuestVertexElement& slot)
	{
		DWORD XboxVertexElementDataType = slot.Format;

		// Does this attribute use no storage present the vertex (check this as early as possible to avoid needless processing) ?
		if (XboxVertexElementDataType == X_D3DVSDT_NONE)
		{

			// Handle tessellating attributes
			switch (slot.TessellationType) {
			case 0: return false; // AUTONONE
			case 1: // AUTONORMAL
				// Note : .Stream, .Offset and .Type are copied from pAttributeSlot->TessellationSource in a post-processing step below,
				// because these could all go through an Xbox to host conversion step, so must be copied over afterwards.
				pCurrentHostVertexElement->Method = D3DDECLMETHOD_CROSSUV; // for D3DVSD_TESSNORMAL
				pCurrentHostVertexElement->Usage = D3DDECLUSAGE_NORMAL; // TODO : Is this correct?
				pCurrentHostVertexElement->UsageIndex = 0; // Note : 1 would be wrong
				return true;
			case 2: // AUTOTEXCOORD
				// pCurrentHostVertexElement->Stream = 0; // The input stream is unused (but must be set to 0), which is the current default value
				// pCurrentHostVertexElement->Offset = 0; // The input offset is unused (but must be set to 0), which is the current default value
				pCurrentHostVertexElement->Type = D3DDECLTYPE_UNUSED; // The input type for D3DDECLMETHOD_UV must be D3DDECLTYPE_UNUSED (the output type implied by D3DDECLMETHOD_UV is D3DDECLTYPE_FLOAT2)
				pCurrentHostVertexElement->Method = D3DDECLMETHOD_UV; // For X_D3DVSD_MASK_TESSUV
				pCurrentHostVertexElement->Usage = D3DDECLUSAGE_NORMAL; // Note : In Fixed Function Vertex Pipeline, D3DDECLMETHOD_UV must specify usage D3DDECLUSAGE_TEXCOORD or D3DDECLUSAGE_BLENDWEIGHT. TODO : So, what to do?
				pCurrentHostVertexElement->UsageIndex = 1; // TODO ; Is this correct?
				return true;
			default:
				printf("invalid TessellationType\n");
				return false;
			}
		}

		WORD XboxVertexElementByteSize = 0; // When set above 0, implies NeedPatching
		BYTE HostVertexElementDataType = 0;
		WORD HostVertexElementByteSize = 0;

		switch (XboxVertexElementDataType)
		{
		case X_D3DVSDT_FLOAT1: // 0x12:
			HostVertexElementDataType = D3DDECLTYPE_FLOAT1;
			HostVertexElementByteSize = 1 * sizeof(float);
			break;
		case X_D3DVSDT_FLOAT2: // 0x22:
			HostVertexElementDataType = D3DDECLTYPE_FLOAT2;
			HostVertexElementByteSize = 2 * sizeof(float);
			break;
		case X_D3DVSDT_FLOAT3: // 0x32:
			HostVertexElementDataType = D3DDECLTYPE_FLOAT3;
			HostVertexElementByteSize = 3 * sizeof(float);
			break;
		case X_D3DVSDT_FLOAT4: // 0x42:
			HostVertexElementDataType = D3DDECLTYPE_FLOAT4;
			HostVertexElementByteSize = 4 * sizeof(float);
			break;
		case X_D3DVSDT_D3DCOLOR: // 0x40:
			HostVertexElementDataType = D3DDECLTYPE_D3DCOLOR;
			HostVertexElementByteSize = 1 * sizeof(uint32_t);
			break;
		case X_D3DVSDT_SHORT2: // 0x25:
			HostVertexElementDataType = D3DDECLTYPE_SHORT2;
			HostVertexElementByteSize = 2 * sizeof(int16_t);
			break;
		case X_D3DVSDT_SHORT4: // 0x45:
			HostVertexElementDataType = D3DDECLTYPE_SHORT4;
			HostVertexElementByteSize = 4 * sizeof(int16_t);
			break;
		case X_D3DVSDT_NORMSHORT1: // 0x11:
		
			HostVertexElementDataType = D3DDECLTYPE_SHORT2N;
			HostVertexElementByteSize = 2 * sizeof(int16_t);
	
			XboxVertexElementByteSize = 1 * sizeof(int16_t);
			break;
		case X_D3DVSDT_NORMSHORT2: // 0x21:

			HostVertexElementDataType = D3DDECLTYPE_SHORT2N;
			HostVertexElementByteSize = 2 * sizeof(int16_t);
			// No need for patching in D3D9

			break;
		case X_D3DVSDT_NORMSHORT3: // 0x31:
		
			HostVertexElementDataType = D3DDECLTYPE_SHORT4N;
			HostVertexElementByteSize = 4 * sizeof(int16_t);
	
			XboxVertexElementByteSize = 3 * sizeof(int16_t);
			break;
		case X_D3DVSDT_NORMSHORT4: // 0x41:

		{
			HostVertexElementDataType = D3DDECLTYPE_SHORT4N;
			HostVertexElementByteSize = 4 * sizeof(int16_t);
			// No need for patching in D3D9
		}

		break;
		case X_D3DVSDT_NORMPACKED3: // 0x16:
			HostVertexElementDataType = D3DDECLTYPE_FLOAT3;
			HostVertexElementByteSize = 3 * sizeof(float);
			XboxVertexElementByteSize = 1 * sizeof(uint32_t);
			break;
		case X_D3DVSDT_SHORT1: // 0x15:
			HostVertexElementDataType = D3DDECLTYPE_SHORT2;
			HostVertexElementByteSize = 2 * sizeof(int16_t);
			XboxVertexElementByteSize = 1 * sizeof(int16_t);
			break;
		case X_D3DVSDT_SHORT3: // 0x35:
			HostVertexElementDataType = D3DDECLTYPE_SHORT4;
			HostVertexElementByteSize = 4 * sizeof(int16_t);
			XboxVertexElementByteSize = 3 * sizeof(int16_t);
			break;
		case X_D3DVSDT_PBYTE1: // 0x14:

			HostVertexElementDataType = D3DDECLTYPE_UBYTE4N;
			HostVertexElementByteSize = 4 * sizeof(uint8_t);


			XboxVertexElementByteSize = 1 * sizeof(uint8_t);
			break;
		case X_D3DVSDT_PBYTE2: // 0x24:
			//if (g_D3DCaps.DeclTypes & D3DDTCAPS_UBYTE4N) {
		{
			HostVertexElementDataType = D3DDECLTYPE_UBYTE4N;
			HostVertexElementByteSize = 4 * sizeof(uint8_t);
		}

		XboxVertexElementByteSize = 2 * sizeof(uint8_t);
		break;
		case X_D3DVSDT_PBYTE3: // 0x34:
			//if (g_D3DCaps.DeclTypes & D3DDTCAPS_UBYTE4N) {
			HostVertexElementDataType = D3DDECLTYPE_UBYTE4N;
			HostVertexElementByteSize = 4 * sizeof(uint8_t);
			/**}
			else {
				HostVertexElementDataType = D3DDECLTYPE_FLOAT3;
				HostVertexElementByteSize = 3 * sizeof(float);
			}*/
			XboxVertexElementByteSize = 3 * sizeof(uint8_t);
			break;
		case X_D3DVSDT_PBYTE4: // 0x44:
			//if (g_D3DCaps.DeclTypes & D3DDTCAPS_UBYTE4N) {
		{
			HostVertexElementDataType = D3DDECLTYPE_UBYTE4N;
			HostVertexElementByteSize = 4 * sizeof(uint8_t);
			// No need for patching when PC supports D3DDECLTYPE_UBYTE4N
		}

		break;
		case X_D3DVSDT_FLOAT2H: // 0x72:
			HostVertexElementDataType = D3DDECLTYPE_FLOAT4;
			HostVertexElementByteSize = 4 * sizeof(float);
			XboxVertexElementByteSize = 3 * sizeof(float);
			break;
		case X_D3DVSDT_NONE: // 0x02:
			assert(false); // Should already be handled above
			break;
		default:
			printf("Unknown data type for D3DVSD_REG\n");
			return false;
		}

		assert(HostVertexElementDataType < D3DDECLTYPE_UNUSED);
		assert(HostVertexElementByteSize > 0);

		// Select new stream, if needed
		if ((pCurrentVertexShaderStreamInfo == nullptr)
			|| (pCurrentVertexShaderStreamInfo->XboxStreamIndex != slot.StreamIndex)) {
			assert(slot.StreamIndex < X_VSH_MAX_STREAMS);
			assert(pCurrentVertexDeclaration->NumberOfVertexStreams < X_VSH_MAX_STREAMS);

			pCurrentVertexShaderStreamInfo =
				&(pCurrentVertexDeclaration->VertexStreams[
					pCurrentVertexDeclaration->NumberOfVertexStreams++]);
			pCurrentVertexShaderStreamInfo->NeedPatch = FALSE;
			pCurrentVertexShaderStreamInfo->XboxStreamIndex = (WORD)slot.StreamIndex;
			pCurrentVertexShaderStreamInfo->HostVertexStride = (WORD)slot.Offset;
			pCurrentVertexShaderStreamInfo->NumberOfVertexElements = 0;
			// Dxbx note : Use Dophin(s), FieldRender, MatrixPaletteSkinning and PersistDisplay as a testcase
		}

		// save patching information
		assert(pCurrentVertexShaderStreamInfo->NumberOfVertexElements < X_VSH_MAX_ATTRIBUTES);

		HostVertexShaderStreamElement* pCurrentVertexShaderStreamElementInfo =
			&(pCurrentVertexShaderStreamInfo->VertexElements[
				pCurrentVertexShaderStreamInfo->NumberOfVertexElements++]);

		if (XboxVertexElementByteSize == 0) {
			XboxVertexElementByteSize = HostVertexElementByteSize;
		}
		else {
			pCurrentVertexShaderStreamInfo->NeedPatch |= TRUE;
		}

		pCurrentVertexShaderStreamElementInfo->XboxType = XboxVertexElementDataType;
		pCurrentVertexShaderStreamElementInfo->XboxByteSize = XboxVertexElementByteSize;
		pCurrentVertexShaderStreamElementInfo->HostDataType = HostVertexElementDataType;
		pCurrentVertexShaderStreamElementInfo->HostByteSize = HostVertexElementByteSize;

		// Convert to host vertex element
		pCurrentHostVertexElement->Stream = pCurrentVertexShaderStreamInfo->XboxStreamIndex; // Use Xbox stream index on host
		// FIXME Don't assume vertex elements are contiguous!
		pCurrentHostVertexElement->Offset = pCurrentVertexShaderStreamInfo->HostVertexStride;
		pCurrentHostVertexElement->Type = pCurrentVertexShaderStreamElementInfo->HostDataType;
		pCurrentHostVertexElement->Method = D3DDECLMETHOD_DEFAULT;
		if (IsFixedFunction)
		{
			pCurrentHostVertexElement->Usage = Xb2PCRegisterType(VertexRegister, /*&*/pCurrentHostVertexElement->UsageIndex);
		}
		else {
			// D3DDECLUSAGE_TEXCOORD can be useds for any user-defined data
			// We need this because there is no reliable way to detect the real usage
			// Xbox has no concept of 'usage types', it only requires a list of attribute register numbers.
			// So we treat them all as 'user-defined' with an Index of the Vertex Register Index
			// this prevents information loss in shaders due to non-matching dcl types!
			pCurrentHostVertexElement->Usage = D3DDECLUSAGE_TEXCOORD;
			pCurrentHostVertexElement->UsageIndex = (BYTE)VertexRegister;
		}

		pCurrentVertexShaderStreamInfo->HostVertexStride += HostVertexElementByteSize;

		return true;
	}

public:
	D3DVERTEXELEMENT9* Convert(X_VERTEXATTRIBUTEFORMAT* pXboxDeclaration, bool bIsFixedFunction, HostVertexDeclaration* pVertexDeclaration)
	{
		// Get a preprocessed copy of the original Xbox Vertex Declaration
		pCurrentVertexDeclaration = pVertexDeclaration;

		IsFixedFunction = bIsFixedFunction;

		RegVIsPresentInDeclaration.fill(false);

		// Mapping between Xbox register and the resulting host vertex element
		D3DVERTEXELEMENT9* HostVertexElementPerRegister[X_VSH_MAX_ATTRIBUTES] = { 0 };

		// For Direct3D9, we need to reserve the maximum number of elements, plus one token for D3DDECL_END :
		unsigned HostDeclarationSize = (X_VSH_MAX_ATTRIBUTES + 1) * sizeof(D3DVERTEXELEMENT9);

		D3DVERTEXELEMENT9* HostVertexElements = (D3DVERTEXELEMENT9*)calloc(1, HostDeclarationSize);
		pCurrentHostVertexElement = HostVertexElements;

		std::array<uint8_t, X_VSH_MAX_ATTRIBUTES> orderedRegisterIndices;
		for (uint8_t i = 0; i < orderedRegisterIndices.size(); i++)
			orderedRegisterIndices[i] = i;

		// Make sure we convert registers in order of offset, per stream
		// TODO fix elements with identical positions?
		std::sort(orderedRegisterIndices.begin(), orderedRegisterIndices.end(),
			[pXboxDeclaration](const auto& x, const auto& y)
			{
				auto regX = pXboxDeclaration->Slots[x];
				auto regY = pXboxDeclaration->Slots[y];
				return std::tie(regX.StreamIndex, regX.Offset)
					< std::tie(regY.StreamIndex, regY.Offset);
			});

		printf("[XSHR] Parsing vertex declaration\n");
		for (size_t i = 0; i < orderedRegisterIndices.size(); i++) {
			auto regIndex = orderedRegisterIndices[i];
			auto& slot = pXboxDeclaration->Slots[regIndex];
			if (slot.Format > X_D3DVSDT_NONE) {
				// Set Direct3D9 vertex element (declaration) members :
				if (VshConvertToken_STREAMDATA_REG(regIndex, slot))
				{
					// Add this register to the list of declared registers
					RegVIsPresentInDeclaration[regIndex] = true;
					// Remember a pointer to this register
					HostVertexElementPerRegister[regIndex] = pCurrentHostVertexElement;
					pCurrentHostVertexElement++;
				}
			}
		}

		*pCurrentHostVertexElement = D3DDECL_END();

		// Post-process host vertex elements that have a D3DDECLMETHOD_CROSSUV method :
		for (int AttributeIndex = 0; AttributeIndex < X_VSH_MAX_ATTRIBUTES; AttributeIndex++)
		{
			auto pHostElement = HostVertexElementPerRegister[AttributeIndex];
			if (pHostElement == nullptr)
				continue;
			if (pHostElement->Method == D3DDECLMETHOD_CROSSUV)
			{
				int TessellationSource = pXboxDeclaration->Slots[AttributeIndex].TessellationSource;
				auto pSourceElement = HostVertexElementPerRegister[TessellationSource];
				// Copy over the Stream, Offset and Type of the host vertex element that serves as 'TessellationSource' :
				pHostElement->Stream = pSourceElement->Stream;
				pHostElement->Offset = pSourceElement->Offset;
				pHostElement->Type = pSourceElement->Type;
				// Note, the input type for D3DDECLMETHOD_CROSSUV can be D3DDECLTYPE_FLOAT[43], D3DDECLTYPE_D3DCOLOR, D3DDECLTYPE_UBYTE4, or D3DDECLTYPE_SHORT4
				// (the output type implied by D3DDECLMETHOD_CROSSUV is D3DDECLTYPE_FLOAT3).
				// TODO : Should we assert this?
			}
		}

		// Ensure valid ordering of the vertex declaration (http://doc.51windows.net/Directx9_SDK/graphics/programmingguide/gettingstarted/vertexdeclaration/vertexdeclaration.htm)
		// In particular "All vertex elements for a stream must be consecutive and sorted by offset"
		// Note : Xbox slots might use non-ordered stream indices, so we can't rely on the output ordering of our converted elements!
		std::sort(/*First=*/HostVertexElements, /*Last=*/pCurrentHostVertexElement, /*Pred=*/[](const auto& x, const auto& y)
			{ return std::tie(x.Stream, x.Method, x.Offset) < std::tie(y.Stream, y.Method, y.Offset); });

		// Record which registers are in the vertex declaration
		for (size_t i = 0; i < RegVIsPresentInDeclaration.size(); i++) {
			pVertexDeclaration->vRegisterInDeclaration[i] = RegVIsPresentInDeclaration[i];
		}


		return HostVertexElements;
	}
};


VertexDeclarationKey GetXboxVertexAttributesKey(X_VERTEXATTRIBUTEFORMAT* pXboxVertexAttributeFormat, bool isFixedFunction)
{

	auto attributeHash = XXH3_64bits((void*)pXboxVertexAttributeFormat, sizeof(X_VERTEXATTRIBUTEFORMAT));
	// For now, we use different declarations depending on if the fixed function pipeline
	// is in use, even if the attributes are the same
	return isFixedFunction ? attributeHash : attributeHash ^ 1;
}

//std::unordered_map<VertexDeclarationKey, HostVertexDeclaration*> g_HostVertexDeclarations;


static bool FreeHostVertexDeclaration(HostVertexDeclaration* pHostVertexDeclaration)
{
	if (pHostVertexDeclaration)
	{
		free(pHostVertexDeclaration);
		return true;
	}

	return false;
}

void RegisterHostVertexDeclaration(VertexDeclarationKey CacheKey, HostVertexDeclaration* pHostVertexDeclaration)
{
	auto it = g_HostVertexDeclarations.find(CacheKey);
	if (it != g_HostVertexDeclarations.end() && it->second != nullptr)
	{
		FreeHostVertexDeclaration(it->second); // Avoid memory leak
	}

	g_HostVertexDeclarations[CacheKey] = pHostVertexDeclaration;
}


HostVertexDeclaration* FetchCachedHostVertexDeclaration(VertexDeclarationKey CacheKey)
{
	auto it = g_HostVertexDeclarations.find(CacheKey);
	if (it != g_HostVertexDeclarations.end())
	{
		return it->second;
	}

	return nullptr;
}

D3DVERTEXELEMENT9* EmuRecompileVshDeclaration
(
	X_VERTEXATTRIBUTEFORMAT* pXboxDeclaration,
	bool                  bIsFixedFunction,
	HostVertexDeclaration* pVertexDeclaration
)
{
	XboxVertexDeclarationConverter Converter;

	D3DVERTEXELEMENT9* pHostVertexElements = Converter.Convert(pXboxDeclaration, bIsFixedFunction, pVertexDeclaration);

	return pHostVertexElements;
}

// X_D3DVertexShader.Flags values :
#define X_VERTEXSHADER_FLAG_WRITE           (1 <<  0) // = 0x0001 // Set for Xbox ShaderType != X_VST_NORMAL 
#define X_VERTEXSHADER_FLAG_PASSTHROUGH     (1 <<  1) // = 0x0002
#define X_VERTEXSHADER_FLAG_STATE           (1 <<  3) // = 0x0008 // Set for Xbox ShaderType == X_VST_STATE
#define X_VERTEXSHADER_FLAG_PROGRAM         (1 <<  4) // = 0x0010 // Set when X_D3DVertexShader was created with assigned function data; introduced after XDK 3948; don't use directly, use g_X_VERTEXSHADER_FLAG_PROGRAM instead
#define X_VERTEXSHADER_FLAG_HASDIFFUSE      (1 << 10) // = 0x0400 Corresponds to X_D3DUSAGE_PERSISTENTDIFFUSE
#define X_VERTEXSHADER_FLAG_HASSPECULAR     (1 << 11) // = 0x0800 Corresponds to X_D3DUSAGE_PERSISTENTSPECULAR
#define X_VERTEXSHADER_FLAG_HASBACKDIFFUSE  (1 << 12) // = 0x1000 Corresponds to X_D3DUSAGE_PERSISTENTBACKDIFFUSE
#define X_VERTEXSHADER_FLAG_HASBACKSPECULAR (1 << 13) // = 0x2000 Corresponds to X_D3DUSAGE_PERSISTENTBACKSPECULAR

static uint32_t  g_X_VERTEXSHADER_FLAG_PROGRAM = X_VERTEXSHADER_FLAG_PROGRAM;

#define X_D3DFVF_TEXCOORDSIZE_SHIFT(Index) ((Index) * 2 + 16)

static X_D3DVertexShader g_Xbox_VertexShader_ForFVF = {};

static X_D3DVertexShader* XboxVertexShaderFromFVF(size_t xboxFvf)
{
	// Note : FVFs don't tessellate, all slots read from stream zero, therefore
	// the following zero-initialization of StreamIndex (like all other fields)
	// is never updated below.
	g_Xbox_VertexShader_ForFVF = { 0 };

	// Shorthand, glueing earlier implementation below to global g_Xbox_VertexShader_ForFVF variable :
	X_VERTEXATTRIBUTEFORMAT& declaration = g_Xbox_VertexShader_ForFVF.VertexAttribute;

	static DWORD X_D3DVSDT_FLOAT[] = { 0, X_D3DVSDT_FLOAT1, X_D3DVSDT_FLOAT2, X_D3DVSDT_FLOAT3, X_D3DVSDT_FLOAT4 };

	static const DWORD InvalidXboxFVFBits = X_D3DFVF_RESERVED0 | X_D3DFVF_RESERVED1 /* probably D3DFVF_PSIZE if detected */
		| 0x0000F000 // Bits between texture count and the texture formats
		| 0xFF000000; // All bits above the four alllowed texture formats


	// Position & Blendweights
	int32_t nrPositionFloats = 3;
	int32_t nrBlendWeights = 0;
	uint32_t offset = 0;
	DWORD position = (xboxFvf & X_D3DFVF_POSITION_MASK);
	if (xboxFvf == 0)
	{
		std::string pos = std::to_string(position);
		printf("xboxFvF is null, position is equal %s\n", pos.c_str());
	}

	switch (position) {
	case 0: nrPositionFloats = 0; break;
	case X_D3DFVF_XYZ: /*nrPositionFloats is set to 3 by default*/ break;
	case X_D3DFVF_XYZRHW: nrPositionFloats = 4; g_Xbox_VertexShader_ForFVF.Flags |= X_VERTEXSHADER_FLAG_PASSTHROUGH; break;
	case X_D3DFVF_XYZB1:
		nrBlendWeights = 1;
		break;
	case X_D3DFVF_XYZB2:
		nrBlendWeights = 2;
		break;
	case X_D3DFVF_XYZB3:
		nrBlendWeights = 3;
		break;
	case X_D3DFVF_XYZB4:
		nrBlendWeights = 4;
		break;
	case X_D3DFVF_POSITION_MASK: /*Keep nrPositionFloats set to 3*/  break;
		UNREACHABLE;
	}

	// Assign vertex element (attribute) slots
	GuestVertexElement* pSlot;

	// Write Position
	if (nrPositionFloats > 0)
	{
		pSlot = &declaration.Slots[X_D3DVSDE_POSITION];
		pSlot->Format = X_D3DVSDT_FLOAT[nrPositionFloats];
		pSlot->Offset = offset;
		offset += sizeof(float) * nrPositionFloats;
		// Write Blend Weights
		if (nrBlendWeights > 0)
		{
			pSlot = &declaration.Slots[X_D3DVSDE_BLENDWEIGHT];
			pSlot->Format = X_D3DVSDT_FLOAT[nrBlendWeights];
			pSlot->Offset = offset;
			offset += sizeof(float) * nrBlendWeights;
		}
	}

	// Write Normal, Diffuse, and Specular
	if (xboxFvf & X_D3DFVF_NORMAL)
	{
		pSlot = &declaration.Slots[X_D3DVSDE_NORMAL];
		pSlot->Format = X_D3DVSDT_FLOAT[3];
		pSlot->Offset = offset;
		offset += sizeof(float) * 3;
	}

	if (xboxFvf & X_D3DFVF_DIFFUSE)
	{
		g_Xbox_VertexShader_ForFVF.Flags |= X_VERTEXSHADER_FLAG_HASDIFFUSE;
		pSlot = &declaration.Slots[X_D3DVSDE_DIFFUSE];
		pSlot->Format = X_D3DVSDT_D3DCOLOR;
		pSlot->Offset = offset;
		offset += sizeof(uint32_t) * 1;
	}

	if (xboxFvf & X_D3DFVF_SPECULAR)
	{
		g_Xbox_VertexShader_ForFVF.Flags |= X_VERTEXSHADER_FLAG_HASSPECULAR;
		pSlot = &declaration.Slots[X_D3DVSDE_SPECULAR];
		pSlot->Format = X_D3DVSDT_D3DCOLOR;
		pSlot->Offset = offset;
		offset += sizeof(uint32_t) * 1;
	}

	// Write Texture Coordinates
	int32_t textureCount = (xboxFvf & X_D3DFVF_TEXCOUNT_MASK) >> X_D3DFVF_TEXCOUNT_SHIFT;

	if (textureCount > 4)
		textureCount = 4; // Safeguard, since the X_D3DFVF_TEXCOUNT bitfield could contain invalid values (5 up to 15)

	for (int i = 0; i < textureCount; i++)
	{
		auto FVFTextureFormat = (xboxFvf >> X_D3DFVF_TEXCOORDSIZE_SHIFT(i)) & 0x003;

		int32_t numberOfCoordinates = ((FVFTextureFormat + 1) & 3) + 1; // ((input   +1 ) &3 ) +1 ) = output

		assert(numberOfCoordinates > 0);

		pSlot = &declaration.Slots[X_D3DVSDE_TEXCOORD0 + i];
		pSlot->Format = X_D3DVSDT_FLOAT[numberOfCoordinates];
		pSlot->Offset = offset;
		offset += sizeof(float) * numberOfCoordinates;
		// Update the VertexShader texture Dimensionality field here as well
		g_Xbox_VertexShader_ForFVF.Dimensionality[i] = numberOfCoordinates;
	}

	// Make sure all unused slots have a X_D3DVSDT_NONE format
	for (uint32_t i = 0; i < X_VSH_MAX_ATTRIBUTES; i++)
	{
		pSlot = &declaration.Slots[i];
		if (pSlot->Format == 0)
			pSlot->Format = X_D3DVSDT_NONE;

	}

	// Return the global g_Xbox_VertexShader_ForFVF variable 
	return &g_Xbox_VertexShader_ForFVF;
}

inline bool VshHandleIsVertexShader(size_t Handle) { return (Handle & X_D3DFVF_RESERVED0) ? true : false; }
inline bool VshHandleIsFVF(size_t Handle) { return !VshHandleIsVertexShader(Handle); }
inline bool VshHandleIsPassthrough(size_t Handle) {
	return VshHandleIsFVF(Handle) && ((Handle & X_D3DFVF_POSITION_MASK) == X_D3DFVF_XYZRHW);
}

X_D3DVertexShader* GetXboxVertexShaderForHandle(size_t Handle)
{
	if (VshHandleIsVertexShader(Handle))
	{
		return VshHandleToXboxVertexShader(Handle);
	}
	else
	{
		return XboxVertexShaderFromFVF(Handle);
	}
}

X_D3DVertexShader* GetXboxVertexShader(size_t handle)
{
	X_D3DVertexShader* pXboxVertexShader = GetXboxVertexShaderForHandle(handle);
	return pXboxVertexShader;
}


static X_VERTEXATTRIBUTEFORMAT* GetVertexShaderAttributes(X_D3DVertexShader* pXboxVertexShader)
{
	return &(pXboxVertexShader->VertexAttribute);
}

X_VERTEXATTRIBUTEFORMAT* GetXboxVertexAttributeFormat(size_t handle)
{

	X_D3DVertexShader* pXboxVertexShader = GetXboxVertexShader(handle);
	if (pXboxVertexShader == 0)
	{
		printf("Error getting vertex shader\n");
		return nullptr;
	}

	return GetVertexShaderAttributes(pXboxVertexShader);
}


HostVertexDeclaration* HostGetVertexDeclaration(size_t handle, const bool isFixedFunction)
{
	X_VERTEXATTRIBUTEFORMAT* pXboxVertexAttributeFormat = GetXboxVertexAttributeFormat(handle);

	auto XboxVertexAttributesKey = GetXboxVertexAttributesKey(pXboxVertexAttributeFormat, isFixedFunction);
	HostVertexDeclaration* pHostVertexDeclaration = FetchCachedHostVertexDeclaration(XboxVertexAttributesKey);
	if (pHostVertexDeclaration == nullptr)
	{
		pHostVertexDeclaration = (HostVertexDeclaration*)calloc(1, sizeof(HostVertexDeclaration));

		// Convert Xbox vertex attributes towards host Direct3D 9 vertex element
		D3DVERTEXELEMENT9* pRecompiledVertexElements = EmuRecompileVshDeclaration(
			pXboxVertexAttributeFormat,
			isFixedFunction,
			pHostVertexDeclaration);


		// store the vertex elements
		pHostVertexDeclaration->pHostVertexElements = pRecompiledVertexElements;


	/*	auto vertexElement_ = pRecompiledVertexElements;
		printf("Guest Vertex elements logs\n");
		int index = 0;
		while (vertexElement_->Stream != 0xFF && vertexElement_->Type != D3DDECLTYPE_UNUSED)
		{
			printf("Stream[%d], %d\n", index, vertexElement_->Stream);
			printf("type[%d], %d\n", index, vertexElement_->Type);
			printf("Offset[%d], %d\n", index, vertexElement_->Offset);
			printf("Method[%d], %d\n", index, vertexElement_->Method);
			printf("Usage[%d], %d\n", index, vertexElement_->Usage);
			printf("Index[%d], %d\n", index, vertexElement_->UsageIndex);
			++vertexElement_;
			++index;
		}*/

		// Cache resulting declarations from given inputs
		pHostVertexDeclaration->Key = XboxVertexAttributesKey;
		RegisterHostVertexDeclaration(XboxVertexAttributesKey, pHostVertexDeclaration);
	}

	return pHostVertexDeclaration;
}