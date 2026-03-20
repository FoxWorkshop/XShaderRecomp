#ifndef _WIN32
#include <cstddef>
#include <cstdint>
#ifndef BYTE
typedef unsigned char BYTE;
#endif
#ifndef WORD
typedef uint16_t WORD;
#endif
#ifndef DWORD
typedef uint32_t DWORD;
#endif
#ifndef UINT
typedef unsigned int UINT;
#endif
#ifndef BOOL
typedef bool BOOL;
#endif
#endif

#define X_VSH_MAX_ATTRIBUTES          16
#define X_VSH_MAX_STREAMS             16
#define X_VSH_MAX_INSTRUCTION_COUNT   136  // The maximum Xbox shader instruction count

// FVF Definitions
#define X_D3DFVF_RESERVED0        0x001
#define X_D3DFVF_XYZ              0x002
#define X_D3DFVF_XYZRHW           0x004
#define X_D3DFVF_XYZB1            0x006
#define X_D3DFVF_XYZB2            0x008
#define X_D3DFVF_XYZB3            0x00a
#define X_D3DFVF_XYZB4            0x00c
#define X_D3DFVF_POSITION_MASK    0x00E
#define X_D3DFVF_NORMAL           0x010
#define X_D3DFVF_RESERVED1        0x020
#define X_D3DFVF_DIFFUSE          0x040
#define X_D3DFVF_SPECULAR         0x080
#define X_D3DFVF_TEXCOUNT_MASK    0xf00
#define X_D3DFVF_TEXCOUNT_SHIFT   8
#define X_D3DFVF_TEX0             0x000
#define X_D3DFVF_TEX1             0x100
#define X_D3DFVF_TEX2             0x200
#define X_D3DFVF_TEX3             0x300
#define X_D3DFVF_TEX4             0x400
#define X_D3DFVF_TEX5             0x500
#define X_D3DFVF_TEX6             0x600
#define X_D3DFVF_TEX7             0x700
#define X_D3DFVF_TEX8             0x800
#define X_D3DFVF_TEXTUREFORMAT1   0x003
#define X_D3DFVF_TEXTUREFORMAT2   0x000
#define X_D3DFVF_TEXTUREFORMAT3   0x001
#define X_D3DFVF_TEXTUREFORMAT4   0x002


typedef uint64_t VertexDeclarationKey;

typedef enum _D3DDECLTYPE
{
	D3DDECLTYPE_FLOAT1 = 0,  // 1D float expanded to (value, 0., 0., 1.)
	D3DDECLTYPE_FLOAT2 = 1,  // 2D float expanded to (value, value, 0., 1.)
	D3DDECLTYPE_FLOAT3 = 2,  // 3D float expanded to (value, value, value, 1.)
	D3DDECLTYPE_FLOAT4 = 3,  // 4D float
	D3DDECLTYPE_D3DCOLOR = 4,  // 4D packed unsigned bytes mapped to 0. to 1. range
	// Input is in D3DCOLOR format (ARGB) expanded to (R, G, B, A)
	D3DDECLTYPE_UBYTE4 = 5,  // 4D unsigned byte
	D3DDECLTYPE_SHORT2 = 6,  // 2D signed short expanded to (value, value, 0., 1.)
	D3DDECLTYPE_SHORT4 = 7,  // 4D signed short

	// The following types are valid only with vertex shaders >= 2.0


	D3DDECLTYPE_UBYTE4N = 8,  // Each of 4 bytes is normalized by dividing to 255.0
	D3DDECLTYPE_SHORT2N = 9,  // 2D signed short normalized (v[0]/32767.0,v[1]/32767.0,0,1)
	D3DDECLTYPE_SHORT4N = 10,  // 4D signed short normalized (v[0]/32767.0,v[1]/32767.0,v[2]/32767.0,v[3]/32767.0)
	D3DDECLTYPE_USHORT2N = 11,  // 2D unsigned short normalized (v[0]/65535.0,v[1]/65535.0,0,1)
	D3DDECLTYPE_USHORT4N = 12,  // 4D unsigned short normalized (v[0]/65535.0,v[1]/65535.0,v[2]/65535.0,v[3]/65535.0)
	D3DDECLTYPE_UDEC3 = 13,  // 3D unsigned 10 10 10 format expanded to (value, value, value, 1)
	D3DDECLTYPE_DEC3N = 14,  // 3D signed 10 10 10 format normalized and expanded to (v[0]/511.0, v[1]/511.0, v[2]/511.0, 1)
	D3DDECLTYPE_FLOAT16_2 = 15,  // Two 16-bit floating point values, expanded to (value, value, 0, 1)
	D3DDECLTYPE_FLOAT16_4 = 16,  // Four 16-bit floating point values
	D3DDECLTYPE_UNUSED = 17,  // When the type field in a decl is unused.
} D3DDECLTYPE;

#define D3DDECL_END() {0xFF,0,D3DDECLTYPE_UNUSED,0,0,0}
typedef enum _D3DDECLUSAGE
{
	D3DDECLUSAGE_POSITION = 0,
	D3DDECLUSAGE_BLENDWEIGHT,   // 1
	D3DDECLUSAGE_BLENDINDICES,  // 2
	D3DDECLUSAGE_NORMAL,        // 3
	D3DDECLUSAGE_PSIZE,         // 4
	D3DDECLUSAGE_TEXCOORD,      // 5
	D3DDECLUSAGE_TANGENT,       // 6
	D3DDECLUSAGE_BINORMAL,      // 7
	D3DDECLUSAGE_TESSFACTOR,    // 8
	D3DDECLUSAGE_POSITIONT,     // 9
	D3DDECLUSAGE_COLOR,         // 10
	D3DDECLUSAGE_FOG,           // 11
	D3DDECLUSAGE_DEPTH,         // 12
	D3DDECLUSAGE_SAMPLE,        // 13
} D3DDECLUSAGE;

typedef enum _D3DDECLMETHOD
{
	D3DDECLMETHOD_DEFAULT = 0,
	D3DDECLMETHOD_PARTIALU,
	D3DDECLMETHOD_PARTIALV,
	D3DDECLMETHOD_CROSSUV,    // Normal
	D3DDECLMETHOD_UV,
	D3DDECLMETHOD_LOOKUP,               // Lookup a displacement map
	D3DDECLMETHOD_LOOKUPPRESAMPLED,     // Lookup a pre-sampled displacement map
} D3DDECLMETHOD;

struct GuestVertexElement
{
	DWORD StreamIndex;
	DWORD Offset;
	DWORD Format;
	BYTE TessellationType;
	BYTE TessellationSource;
	BYTE Padding0;
	BYTE Padding1;
};


typedef struct _D3DVERTEXELEMENT9
{
	WORD    Stream;     // Stream index
	WORD    Offset;     // Offset in the stream in bytes
	BYTE    Type;       // Data type
	BYTE    Method;     // Processing method
	BYTE    Usage;      // Semantics
	BYTE    UsageIndex; // Semantic index
} D3DVERTEXELEMENT9, * LPD3DVERTEXELEMENT9;

typedef struct _HostVertexShaderStreamElement
{
	UINT XboxType; // The stream element data type (xbox)
	UINT XboxByteSize; // The stream element data size (xbox)
	BYTE HostDataType; // The stream element data type (pc)
	UINT HostByteSize; // The stream element data size (pc)
}
HostVertexShaderStreamElement;



typedef struct _HostVertexShaderStreamInfo
{
	BOOL  NeedPatch;       // This is to know whether it's data which must be patched
	WORD HostVertexStride;
	DWORD NumberOfVertexElements;        // Number of the stream data types
	WORD XboxStreamIndex;
	HostVertexShaderStreamElement VertexElements[X_VSH_MAX_ATTRIBUTES];
}
HostVertexShaderStreamInfo;


typedef struct _HostVertexDeclaration
{
	VertexDeclarationKey Key;
	HostVertexShaderStreamInfo VertexStreams[X_VSH_MAX_STREAMS]; // Note : VertexStreams is indexed by a counter, NOT StreamIndex!
	D3DVERTEXELEMENT9* pHostVertexElements;
	UINT NumberOfVertexStreams; // The number of streams the vertex shader uses
	bool vRegisterInDeclaration[X_VSH_MAX_ATTRIBUTES];
}
HostVertexDeclaration;

// ******************************************************************
struct X_VERTEXATTRIBUTEFORMAT
{
	// Note : Alignment looks okay even without #pragma pack(1) / #include "AlignPrefix1.h" (and it's closure)
	GuestVertexElement Slots[X_VSH_MAX_ATTRIBUTES];
};


const int X_D3DVSDE_VERTEX = -1; // Xbox extension for Begin/End drawing - equivalent to POSITION
const int X_D3DVSDE_POSITION = 0; // Corresponds to X_D3DFVF_XYZ
const int X_D3DVSDE_BLENDWEIGHT = 1; // Corresponds to X_D3DFVF_XYZB1? (was X_D3DFVF_XYZRHW?)
const int X_D3DVSDE_NORMAL = 2; // Corresponds to X_D3DFVF_NORMAL
const int X_D3DVSDE_DIFFUSE = 3; // Corresponds to X_D3DFVF_DIFFUSE
const int X_D3DVSDE_SPECULAR = 4; // Corresponds to X_D3DFVF_SPECULAR
const int X_D3DVSDE_FOG = 5; // Xbox extension
const int X_D3DVSDE_POINTSIZE = 6; // Dxbx addition
const int X_D3DVSDE_BACKDIFFUSE = 7; // Xbox extension
const int X_D3DVSDE_BACKSPECULAR = 8; // Xbox extension
const int X_D3DVSDE_TEXCOORD0 = 9; // Corresponds to X_D3DFVF_TEX1 (not X_D3DFVF_TEX0, which means no textures are present)
const int X_D3DVSDE_TEXCOORD1 = 10; // Corresponds to X_D3DFVF_TEX2
const int X_D3DVSDE_TEXCOORD2 = 11; // Corresponds to X_D3DFVF_TEX3
const int X_D3DVSDE_TEXCOORD3 = 12; // Corresponds to X_D3DFVF_TEX4


// bit declarations for _Type fields
const int X_D3DVSDT_FLOAT1 = 0x12; // 1D float expanded to (value, 0.0, 0.0, 1.0)
const int X_D3DVSDT_FLOAT2 = 0x22; // 2D float expanded to (value, value, 0.0, 1.0)
const int X_D3DVSDT_FLOAT3 = 0x32; // 3D float expanded to (value, value, value, 1.0) In double word format this is ARGB, or in byte ordering it would be B, G, R, A.
const int X_D3DVSDT_FLOAT4 = 0x42; // 4D float
const int X_D3DVSDT_D3DCOLOR = 0x40; // 4D packed unsigned bytes mapped to 0.0 to 1.0 range
//const int X_D3DVSDT_UBYTE4      = 0x05; // 4D unsigned byte   Dxbx note : Not supported on Xbox ?
const int X_D3DVSDT_SHORT2 = 0x25; // 2D signed short expanded to (value, value, 0.0, 1.0)
const int X_D3DVSDT_SHORT4 = 0x45; // 4D signed short

//  Xbox only declarations :
const int X_D3DVSDT_NORMSHORT1 = 0x11; // xbox ext. 1D signed, normalized short expanded to (value, 0.0, 0.0, 1.0). Signed, normalized shorts map from -1.0 to 1.0.
const int X_D3DVSDT_NORMSHORT2 = 0x21; // xbox ext. 2D signed, normalized short expanded to (value, value, 0.0, 1.0). Signed, normalized shorts map from -1.0 to 1.0.
const int X_D3DVSDT_NORMSHORT3 = 0x31; // xbox ext. 3D signed, normalized short expanded to (value, value, value, 1.0). Signed, normalized shorts map from -1.0 to 1.0.
const int X_D3DVSDT_NORMSHORT4 = 0x41; // xbox ext. 4D signed, normalized short expanded to (value, value, value, value). Signed, normalized shorts map from -1.0 to 1.0.
const int X_D3DVSDT_NORMPACKED3 = 0x16; // xbox ext. Three signed, normalized components packed in 32-bits. (11,11,10). Each component ranges from -1.0 to 1.0. Expanded to (value, value, value, 1.0).
const int X_D3DVSDT_SHORT1 = 0x15; // xbox ext. 1D signed short expanded to (value, 0., 0., 1). Signed shorts map to the range [-32768, 32767].
const int X_D3DVSDT_SHORT3 = 0x35; // xbox ext. 3D signed short expanded to (value, value, value, 1). Signed shorts map to the range [-32768, 32767].
const int X_D3DVSDT_PBYTE1 = 0x14; // xbox ext. 1D packed byte expanded to (value, 0., 0., 1). Packed bytes map to the range [0, 1].
const int X_D3DVSDT_PBYTE2 = 0x24; // xbox ext. 2D packed byte expanded to (value, value, 0., 1). Packed bytes map to the range [0, 1].
const int X_D3DVSDT_PBYTE3 = 0x34; // xbox ext. 3D packed byte expanded to (value, value, value, 1). Packed bytes map to the range [0, 1].
const int X_D3DVSDT_PBYTE4 = 0x44; // xbox ext. 4D packed byte expanded to (value, value, value, value). Packed bytes map to the range [0, 1].
const int X_D3DVSDT_FLOAT2H = 0x72; // xbox ext. 3D float that expands to (value, value, 0.0, value). Useful for projective texture coordinates.
const int X_D3DVSDT_NONE = 0x02; // xbox ext. nsp

HostVertexDeclaration* HostGetVertexDeclaration(size_t handle, const bool isFixedFunction);