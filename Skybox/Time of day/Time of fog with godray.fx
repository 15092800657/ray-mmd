#include "../../shader/math.fxsub"
#include "../../shader/phasefunctions.fxsub"

#include "shader/common.fxsub"
#include "shader/fog.fxsub"

#include "../../shader/gbuffer.fxsub"
#include "../../shader/gbuffer_sampler.fxsub"

#define FOG_DISCARD_SKY 1
#define FOG_WITH_GODRAY_SAMPLES 48

static float FogSampleLength = 0.9;

texture FogMap : RENDERCOLORTARGET<float2 ViewportRatio={0.5, 0.5}; string Format="A16B16G16R16F";>;
sampler FogMapSamp = sampler_state {
	texture = <FogMap>;
	MinFilter = Linear; MagFilter = Linear; MipFilter = NONE;
	AddressU = BORDER; AddressV = BORDER; BorderColor = 0.0;
};
texture FogBlurMap : RENDERCOLORTARGET<float2 ViewportRatio={0.5, 0.5}; string Format="A16B16G16R16F";>;
sampler FogBlurMapSamp = sampler_state {
	texture = <FogBlurMap>;
	MinFilter = Linear; MagFilter = Linear; MipFilter = NONE;
	AddressU = BORDER; AddressV = BORDER; BorderColor = 0.0;
};

void AtmosphericFogVS(
	in float4 Position : POSITION,
	in float2 Texcoord : TEXCOORD0,
	out float4 oTexcoord0 : TEXCOORD0,
	out float3 oTexcoord1  : TEXCOORD1,
	out float3 oTexcoord2 : TEXCOORD2,
	out float3 oTexcoord3 : TEXCOORD3,
	out float4 oPosition : POSITION)
{
	oTexcoord0 = oPosition = mul(Position, matWorldViewProject);
	oTexcoord0.xy = PosToCoord(oTexcoord0.xy / oTexcoord0.w) + ViewportOffset;
	oTexcoord0.xy = oTexcoord0.xy * oTexcoord0.w;
	oTexcoord1 = normalize(Position.xyz - CameraPosition);
	oTexcoord2 = ComputeWaveLengthMie(mWaveLength, mMieColor, mMieTurbidity, 4);
	oTexcoord3 = ComputeWaveLengthRayleigh(mWaveLength) * mFogColor;
}

float4 AtmosphericFogPS(
	in float4 texcoord : TEXCOORD0,
	in float3 viewdir  : TEXCOORD1,
	in float3 mieLambda : TEXCOORD2,
	in float3 rayleight : TEXCOORD3) : COLOR
{
	float2 coord = texcoord.xy / texcoord.w;

	float4 MRT5 = tex2Dlod(Gbuffer5Map, float4(coord, 0, 0));
	float4 MRT6 = tex2Dlod(Gbuffer6Map, float4(coord, 0, 0));
	float4 MRT7 = tex2Dlod(Gbuffer7Map, float4(coord, 0, 0));
	float4 MRT8 = tex2Dlod(Gbuffer8Map, float4(coord, 0, 0));

	MaterialParam materialAlpha;
	DecodeGbuffer(MRT5, MRT6, MRT7, MRT8, materialAlpha);

#if FOG_DISCARD_SKY
	float3 sum1 = materialAlpha.albedo + materialAlpha.specular;
	clip(dot(sum1, 1.0) - 1e-5);
#endif

	float3 V = normalize(viewdir);

	float scaling = 1000;

	ScatteringParams setting;
	setting.sunSize = mSunRadius;
	setting.sunRadiance = mSunRadiance;
	setting.mieG = mMiePhase;
	setting.mieHeight = mMieHeight * scaling;
	setting.rayleighHeight = mRayleighHeight * scaling;
	setting.earthRadius = 6360 * scaling;
	setting.earthAtmTopRadius = 6380 * scaling;
	setting.earthCenter = float3(0, -setting.earthRadius, 0);
	setting.waveLambdaMie = mieLambda;
	setting.waveLambdaRayleigh = rayleight;
	setting.fogRange = mFogRange;
	
	float3 fog = ComputeFogChapman(setting, CameraPosition + float3(0, scaling, 0), V, LightDirection, materialAlpha.linearDepth);
	return float4(fog, 0);
}

float4 AtmosphericFogMiePS(
	in float4 texcoord : TEXCOORD0,
	in float3 viewdir  : TEXCOORD1,
	in float3 mieLambda : TEXCOORD2,
	in float3 rayleight : TEXCOORD3) : COLOR
{
	float2 coord = texcoord.xy / texcoord.w;

	float4 MRT5 = tex2Dlod(Gbuffer5Map, float4(coord, 0, 0));
	float4 MRT6 = tex2Dlod(Gbuffer6Map, float4(coord, 0, 0));
	float4 MRT7 = tex2Dlod(Gbuffer7Map, float4(coord, 0, 0));
	float4 MRT8 = tex2Dlod(Gbuffer8Map, float4(coord, 0, 0));

	MaterialParam materialAlpha;
	DecodeGbuffer(MRT5, MRT6, MRT7, MRT8, materialAlpha);

	float3 V = normalize(viewdir);

	float scaling = 1000;

	ScatteringParams setting;
	setting.sunSize = mSunRadius;
	setting.sunRadiance = mSunRadiance;
	setting.mieG = mMiePhase;
	setting.mieHeight = mMieHeight * scaling;
	setting.rayleighHeight = mRayleighHeight * scaling;
	setting.earthRadius = 6360 * scaling;
	setting.earthAtmTopRadius = 6380 * scaling;
	setting.earthCenter = float3(0, -setting.earthRadius, 0);
	setting.waveLambdaMie = mieLambda;
	setting.waveLambdaRayleigh = rayleight;
	setting.fogRange = mFogRange;
	
	float3 fog = ComputeFogChapmanMie(setting, CameraPosition + float3(0, scaling, 0), V, LightDirection, materialAlpha.linearDepth);
	return float4(fog, 0);
}

void AtmosphericFogMieBlurVS(
	in float4 Position : POSITION,
	in float2 Texcoord : TEXCOORD0,
	out float4 oTexcoord0 : TEXCOORD0,
	out float4 oTexcoord1 : TEXCOORD1,
	out float4 oPosition : POSITION)
{
	float4 illuminationPosition = mul(float4(-LightDirection * 80000, 1), matViewProject);

	oTexcoord0 = oPosition = mul(Position, matWorldViewProject);
	oTexcoord0.xy = PosToCoord(oTexcoord0.xy / oTexcoord0.w) + ViewportOffset;
	oTexcoord0.xy = oTexcoord0.xy * oTexcoord0.w;
	oTexcoord1 = illuminationPosition;
	oTexcoord1 /= oTexcoord1.w;
	oTexcoord1.xy = PosToCoord(oTexcoord1.xy) + ViewportOffset2 * 2;
}

float4 AtmosphericFogMieBlurPS(in float4 coord : TEXCOORD0, float4 illuminationPosition : TEXCOORD1) : COLOR0
{
	float2 sampleCoord = coord.xy / coord.w;
	float3 sampleColor = 0.0;
	float2 sampleDecay = float2(1.0, 0.96);
	float2 sampleDelta = (sampleCoord - illuminationPosition.xy) / FOG_WITH_GODRAY_SAMPLES * FogSampleLength;

	float jitter = PseudoRandom(sampleCoord * ViewportSize);
	sampleCoord += sampleDelta * jitter;

	for (int i = 0; i < FOG_WITH_GODRAY_SAMPLES; i++)
	{
		sampleColor += tex2Dlod(FogMapSamp, float4(sampleCoord, 0, 0)).rgb * sampleDecay.x;
		sampleCoord -= sampleDelta;
		sampleDecay.x *= sampleDecay.y;
	}

	sampleColor /= FOG_WITH_GODRAY_SAMPLES;

	return float4(sampleColor + sampleColor * jitter / 255.0f, 0);
}

float4 AtmosphericScatteringPS(
	in float4 texcoord : TEXCOORD0, 
	in float3 viewdir : TEXCOORD1,
	in float3 mieLambda : TEXCOORD2,
	in float3 rayleight : TEXCOORD3) : COLOR
{
	float2 coord = texcoord.xy / texcoord.w;

	float4 MRT5 = tex2Dlod(Gbuffer5Map, float4(coord, 0, 0));
	float4 MRT6 = tex2Dlod(Gbuffer6Map, float4(coord, 0, 0));
	float4 MRT7 = tex2Dlod(Gbuffer7Map, float4(coord, 0, 0));
	float4 MRT8 = tex2Dlod(Gbuffer8Map, float4(coord, 0, 0));

	MaterialParam material;
	DecodeGbuffer(MRT5, MRT6, MRT7, MRT8, material);

	float3 V = normalize(viewdir);

	float scaling = 1000;

	ScatteringParams setting;
	setting.sunSize = mSunRadius;
	setting.sunRadiance = mSunRadiance;
	setting.mieG = mMiePhase;
	setting.mieHeight = mMieHeight * scaling;
	setting.rayleighHeight = mRayleighHeight * scaling;
	setting.earthRadius = 6360 * scaling;
	setting.earthAtmTopRadius = 6380 * scaling;
	setting.earthCenter = float3(0, -setting.earthRadius, 0);
	setting.waveLambdaMie = mieLambda;
	setting.waveLambdaRayleigh = rayleight;
	setting.fogRange = mFogRange;
	
	float3 fogAmount = ComputeFogChapmanRayleigh(setting, CameraPosition + float3(0, scaling, 0), V, LightDirection, material.linearDepth);

#if FOG_DISCARD_SKY
	clip(dot(material.albedo + material.specular, 1) - 1e-5);
#endif

	float3 fogBlur = tex2Dlod(FogBlurMapSamp, float4(coord + ViewportOffset, 0, 0)).rgb;
	return float4(fogAmount + fogBlur, luminance(mWaveLength) * material.linearDepth * mFogDensity);
}

const float4 BackColor = 0.0;

technique FogTech<string MMDPass = "object";>{
	pass DrawObject {
		ZEnable = false; ZWriteEnable = false;
		AlphaBlendEnable = true; AlphaTestEnable = false;
		SrcBlend = ONE; DestBlend = ONE;
		CullMode = NONE;
		VertexShader = compile vs_3_0 AtmosphericFogVS();
		PixelShader  = compile ps_3_0 AtmosphericFogPS();
	}
}

technique FogTecBS0<string MMDPass = "object_ss";
	string Script =
		"ClearSetColor=BackColor;"
		"RenderColorTarget=FogMap;"
		"Clear=Color;"
		"Pass=DrawFog;"
		"RenderColorTarget=FogBlurMap;"
		"Clear=Color;"
		"Pass=DrawLightShaft;"
		"RenderColorTarget=;"
		"Pass=DrawGodRay;"
	;>{
		pass DrawFog {
			ZEnable = false; ZWriteEnable = false;
			AlphaBlendEnable = false; AlphaTestEnable = FALSE;
			VertexShader = compile vs_3_0 AtmosphericFogVS();
			PixelShader = compile ps_3_0 AtmosphericFogMiePS();
		}
		pass DrawLightShaft {
			ZEnable = false; ZWriteEnable = false;
			AlphaBlendEnable = false; AlphaTestEnable = FALSE;
			VertexShader = compile vs_3_0 AtmosphericFogMieBlurVS();
			PixelShader = compile ps_3_0 AtmosphericFogMieBlurPS();
		}
		pass DrawGodRay {
			ZEnable = false; ZWriteEnable = false;
			AlphaBlendEnable = true; AlphaTestEnable = FALSE;
			SrcBlend = ONE; DestBlend = ONE;
			VertexShader = compile vs_3_0 AtmosphericFogVS();
			PixelShader = compile ps_3_0 AtmosphericScatteringPS();
		}
	}

technique EdgeTec<string MMDPass = "edge";>{}
technique ShadowTech<string MMDPass = "shadow";>{}
technique ZplotTec<string MMDPass = "zplot";>{}