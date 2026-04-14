#include "pch.h"
#include <dxc_compiler.h>
#include "shader_recompiler.h"
#include <string>      
#include <iostream>    
#include <sstream>     
#include <cassert>


static std::unique_ptr<uint8_t[]> readAllBytes(const char* filePath, size_t& fileSize)
{
	FILE* file = fopen(filePath, "rb");
	fseek(file, 0, SEEK_END);
	fileSize = ftell(file);
	fseek(file, 0, SEEK_SET);
	auto data = std::make_unique<uint8_t[]>(fileSize);
	fread(data.get(), 1, fileSize, file);
	fclose(file);
	return data;
}

static void writeAllBytes(const char* filePath, const void* data, size_t dataSize)
{
	FILE* file = fopen(filePath, "wb");
	fwrite(data, 1, dataSize, file);
	fclose(file);
}

struct RecompiledShader
{
	uint8_t* data = nullptr;
	IDxcBlob* dxil = nullptr;
	std::vector<uint8_t> spirv;
	uint32_t specConstantsMask = 0;
	std::string hlsl;
	bool isPixelShader = false;
};

int main(int argc, char** argv)
{

	const char* inputDir = argv[1];
	const char* output = argv[2];

	std::map<XXH64_hash_t, RecompiledShader> shaders;

	// First we collect all HLSL files from input directory
	for (auto& file : std::filesystem::recursive_directory_iterator(inputDir))
	{
		if (file.path().extension() != ".hlsl")
			continue;


		size_t fileSize = 0;
		auto fileData = readAllBytes(file.path().string().c_str(), fileSize);
		std::string content(reinterpret_cast<const char*>(fileData.get()), fileSize);

		XXH64_hash_t hash = 0;
		bool isPixelShader = file.path().string().find("PixelShader_") != std::string::npos;
		bool validHeader = false;

		std::istringstream ss(content);
		std::string line;
		while (std::getline(ss, line))
		{
			if (line.find("// Shader hash: ") != std::string::npos)
			{
				hash = std::stoull(line.substr(16), nullptr, 16);
				validHeader = true;
				break;
			}
		}

		if (!validHeader)
		{
			fmt::println("Skipping {} - no valid header found", file.path().filename().string());
			continue;
		}

		auto& shader = shaders[hash];
		shader.hlsl = content;
		shader.isPixelShader = isPixelShader;
	}

	std::atomic<uint32_t> progress = 0;

	std::for_each(std::execution::par_unseq, shaders.begin(), shaders.end(), [&](auto& hashShaderPair)
		{
			auto& shader = hashShaderPair.second;

			thread_local DxcCompiler dxcCompiler;

#ifdef XSHADER_RECOMP_DXIL
			shader.dxil = dxcCompiler.compile(shader.hlsl, shader.isPixelShader, false, false);
			assert(shader.dxil != nullptr);
			assert(*(reinterpret_cast<uint32_t*>(shader.dxil->GetBufferPointer()) + 1) != 0 && "DXIL was not signed properly!");
#endif

			IDxcBlob* spirv = dxcCompiler.compile(shader.hlsl, shader.isPixelShader, false, true);
			assert(spirv != nullptr);

			bool result = smolv::Encode(spirv->GetBufferPointer(), spirv->GetBufferSize(), shader.spirv, smolv::kEncodeFlagStripDebugInfo);
			assert(result);

			spirv->Release();

			size_t currentProgress = ++progress;
			if ((currentProgress % 10) == 0 || currentProgress == shaders.size())
				fmt::println("Compiling shaders... {:.1f}%", currentProgress / float(shaders.size()) * 100.0f);
		});


	fmt::println("Creating shader cache...");

	StringBuffer f;
	f.println("#include \"shader_cache.h\"");
	f.println("ShaderCacheEntry g_shaderCacheEntries[] = {{");

	std::vector<uint8_t> dxil;
	std::vector<uint8_t> spirv;

	for (auto& [hash, shader] : shaders)
	{
		f.println("\t{{ 0x{:X}, {}, {}, {}, {}, {} }},",
			hash,
			dxil.size(), (shader.dxil != nullptr) ? shader.dxil->GetBufferSize() : 0,
			spirv.size(), shader.spirv.size(),
			shader.specConstantsMask);

		if (shader.dxil != nullptr)
		{
			dxil.insert(dxil.end(),
				reinterpret_cast<uint8_t*>(shader.dxil->GetBufferPointer()),
				reinterpret_cast<uint8_t*>(shader.dxil->GetBufferPointer()) + shader.dxil->GetBufferSize());
		}

		spirv.insert(spirv.end(), shader.spirv.begin(), shader.spirv.end());
	}

	f.println("}};");

	fmt::println("Compressing DXIL cache...");

	int level = ZSTD_maxCLevel();

#ifdef XSHADER_RECOMP_DXIL
	std::vector<uint8_t> dxilCompressed(ZSTD_compressBound(dxil.size()));
	dxilCompressed.resize(ZSTD_compress(dxilCompressed.data(), dxilCompressed.size(), dxil.data(), dxil.size(), level));

	f.print("const uint8_t g_compressedDxilCache[] = {{");

	for (auto data : dxilCompressed)
		f.print("{},", data);

	f.println("}};");
	f.println("const size_t g_dxilCacheCompressedSize = {};", dxilCompressed.size());
	f.println("const size_t g_dxilCacheDecompressedSize = {};", dxil.size());
#endif

	fmt::println("Compressing SPIRV cache...");

	std::vector<uint8_t> spirvCompressed(ZSTD_compressBound(spirv.size()));
	spirvCompressed.resize(ZSTD_compress(spirvCompressed.data(), spirvCompressed.size(), spirv.data(), spirv.size(), level));

	f.print("const uint8_t g_compressedSpirvCache[] = {{");

	for (auto data : spirvCompressed)
		f.print("{},", data);

	f.println("}};");

	f.println("const size_t g_spirvCacheCompressedSize = {};", spirvCompressed.size());
	f.println("const size_t g_spirvCacheDecompressedSize = {};", spirv.size());
	f.println("const size_t g_shaderCacheEntryCount = {};", shaders.size());

	writeAllBytes(output, f.out.data(), f.out.size());


	return 0;
}
