#include "StillworldSettings.h"

#include "AudioDevice.h"
#include "Engine/Engine.h"
#include "Engine/World.h"
#include "GameFramework/GameUserSettings.h"
#include "HAL/IConsoleManager.h"
#include "Misc/ConfigCacheIni.h"
#include "RHI.h"

FSimpleMulticastDelegate FStillworldSettings::OnChanged;

static const TCHAR* GSection = TEXT("Stillworld");

// ---------------------------------------------------------------------------
// Vendor features

static FString FirstExistingCVar(const TCHAR* Key)
{
	// DefaultGame.ini: [Stillworld.Vendor] +FsrEnable=r.Some.CVar (several allowed)
	TArray<FString> Names;
	if (GConfig)
	{
		GConfig->GetArray(TEXT("Stillworld.Vendor"), Key, Names, GGameIni);
	}
	for (const FString& Name : Names)
	{
		if (IConsoleManager::Get().FindConsoleVariable(*Name))
		{
			return Name;
		}
	}
	return FString();
}

const FStillworldVendorFeatures& FStillworldVendorFeatures::Get()
{
	static FStillworldVendorFeatures F;
	static bool bInit = false;
	if (!bInit)
	{
		bInit = true;
		F.FsrEnable = FirstExistingCVar(TEXT("FsrEnable"));
		F.FsrFrameGen = FirstExistingCVar(TEXT("FsrFrameGen"));
		F.DlssEnable = FirstExistingCVar(TEXT("DlssEnable"));
		F.DlssFrameGen = FirstExistingCVar(TEXT("DlssFrameGen"));
		F.Reflex = FirstExistingCVar(TEXT("Reflex"));
		UE_LOG(LogTemp, Display, TEXT("[Stillworld] Vendor features: FSR=%s FSR-FG=%s DLSS=%s DLSS-FG=%s HWRT=%d"),
			*F.FsrEnable, *F.FsrFrameGen, *F.DlssEnable, *F.DlssFrameGen, F.HasHardwareRayTracing() ? 1 : 0);
	}
	return F;
}

bool FStillworldVendorFeatures::HasFrameGen(EStillworldUpscaler U) const
{
	switch (U)
	{
	case EStillworldUpscaler::FSR: return !FsrFrameGen.IsEmpty();
	case EStillworldUpscaler::DLSS: return !DlssFrameGen.IsEmpty();
	default: return false;
	}
}

bool FStillworldVendorFeatures::HasHardwareRayTracing() const
{
	static const IConsoleVariable* RT = IConsoleManager::Get().FindConsoleVariable(TEXT("r.RayTracing"));
	return GRHISupportsRayTracing && RT && RT->GetInt() != 0;
}

// ---------------------------------------------------------------------------
// Settings

FStillworldSettings& FStillworldSettings::Get()
{
	static FStillworldSettings Instance;
	static bool bLoaded = false;
	if (!bLoaded)
	{
		bLoaded = true;
		Instance.ApplyPreset(EStillworldPreset::High);
		Instance.Load();
	}
	return Instance;
}

const TCHAR* FStillworldSettings::PresetName(EStillworldPreset P)
{
	switch (P)
	{
	case EStillworldPreset::Performance: return TEXT("Performance");
	case EStillworldPreset::High: return TEXT("High");
	case EStillworldPreset::Ultra: return TEXT("Ultra");
	default: return TEXT("Custom");
	}
}

void FStillworldSettings::ApplyPreset(EStillworldPreset InPreset)
{
	const FStillworldVendorFeatures& V = FStillworldVendorFeatures::Get();
	auto SetGroups = [this](int32 Q)
	{
		ViewDistance = Shadows = GlobalIllumination = Reflections = PostProcess = Textures = Effects = Foliage = Shading = Q;
	};
	Preset = InPreset;
	switch (InPreset)
	{
	case EStillworldPreset::Performance:
		// High scalability keeps Lumen; lower internal resolution, upscaled.
		SetGroups(2);
		Textures = 3;
		ScreenPercentage = 58.f;
		RayTracing = EStillworldRayTracing::Off;
		FoliageDensity = 0.6f;
		FoliageDistance = 0.75f;
		bFrameGeneration = V.HasFrameGen(Upscaler);
		break;
	case EStillworldPreset::High:
		SetGroups(3);
		ScreenPercentage = 72.f;
		RayTracing = EStillworldRayTracing::Off;
		FoliageDensity = 0.85f;
		FoliageDistance = 1.f;
		bFrameGeneration = false;
		break;
	case EStillworldPreset::Ultra:
		// Uncompromising: Cinematic everything, native resolution, hardware
		// ray tracing with hit-lit reflections when the GPU supports it.
		SetGroups(4);
		ScreenPercentage = 100.f;
		RayTracing = V.HasHardwareRayTracing() ? EStillworldRayTracing::LumenHitLit : EStillworldRayTracing::Off;
		FoliageDensity = 1.f;
		FoliageDistance = 1.4f;
		bFrameGeneration = V.HasFrameGen(Upscaler);
		break;
	default:
		break;
	}
}

#define SW_GET_INT(Name, Field) GConfig->GetInt(GSection, TEXT(Name), Field, Ini)
#define SW_SET_INT(Name, Field) GConfig->SetInt(GSection, TEXT(Name), Field, Ini)

void FStillworldSettings::Load()
{
	if (!GConfig)
	{
		return;
	}
	const FString& Ini = GGameUserSettingsIni;
	int32 Tmp = static_cast<int32>(Preset);
	if (!GConfig->GetInt(GSection, TEXT("Preset"), Tmp, Ini))
	{
		return; // first launch: keep defaults
	}
	Preset = static_cast<EStillworldPreset>(FMath::Clamp(Tmp, 0, 3));
	SW_GET_INT("WindowMode", WindowMode);
	GConfig->GetBool(GSection, TEXT("VSync"), bVSync, Ini);
	GConfig->GetFloat(GSection, TEXT("FrameLimit"), FrameLimit, Ini);
	Tmp = static_cast<int32>(Upscaler);
	SW_GET_INT("Upscaler", Tmp);
	Upscaler = static_cast<EStillworldUpscaler>(FMath::Clamp(Tmp, 0, 2));
	GConfig->GetFloat(GSection, TEXT("ScreenPercentage"), ScreenPercentage, Ini);
	GConfig->GetBool(GSection, TEXT("FrameGeneration"), bFrameGeneration, Ini);
	Tmp = static_cast<int32>(RayTracing);
	SW_GET_INT("RayTracing", Tmp);
	RayTracing = static_cast<EStillworldRayTracing>(FMath::Clamp(Tmp, 0, 2));
	SW_GET_INT("ViewDistance", ViewDistance);
	SW_GET_INT("Shadows", Shadows);
	SW_GET_INT("GlobalIllumination", GlobalIllumination);
	SW_GET_INT("Reflections", Reflections);
	SW_GET_INT("PostProcess", PostProcess);
	SW_GET_INT("Textures", Textures);
	SW_GET_INT("Effects", Effects);
	SW_GET_INT("Foliage", Foliage);
	SW_GET_INT("Shading", Shading);
	GConfig->GetFloat(GSection, TEXT("FoliageDensity"), FoliageDensity, Ini);
	GConfig->GetFloat(GSection, TEXT("FoliageDistance"), FoliageDistance, Ini);
	GConfig->GetFloat(GSection, TEXT("FieldOfView"), FieldOfView, Ini);
	GConfig->GetFloat(GSection, TEXT("MouseSensitivity"), MouseSensitivity, Ini);
	GConfig->GetBool(GSection, TEXT("InvertY"), bInvertY, Ini);
	GConfig->GetFloat(GSection, TEXT("HeadMotion"), HeadMotion, Ini);
	GConfig->GetFloat(GSection, TEXT("WalkSpeed"), WalkSpeed, Ini);
	GConfig->GetFloat(GSection, TEXT("MasterVolume"), MasterVolume, Ini);
	GConfig->GetFloat(GSection, TEXT("AmbienceVolume"), AmbienceVolume, Ini);
	GConfig->GetFloat(GSection, TEXT("WeatherIntensity"), WeatherIntensity, Ini);
}

void FStillworldSettings::Save() const
{
	if (!GConfig)
	{
		return;
	}
	const FString& Ini = GGameUserSettingsIni;
	SW_SET_INT("Preset", static_cast<int32>(Preset));
	SW_SET_INT("WindowMode", WindowMode);
	GConfig->SetBool(GSection, TEXT("VSync"), bVSync, Ini);
	GConfig->SetFloat(GSection, TEXT("FrameLimit"), FrameLimit, Ini);
	SW_SET_INT("Upscaler", static_cast<int32>(Upscaler));
	GConfig->SetFloat(GSection, TEXT("ScreenPercentage"), ScreenPercentage, Ini);
	GConfig->SetBool(GSection, TEXT("FrameGeneration"), bFrameGeneration, Ini);
	SW_SET_INT("RayTracing", static_cast<int32>(RayTracing));
	SW_SET_INT("ViewDistance", ViewDistance);
	SW_SET_INT("Shadows", Shadows);
	SW_SET_INT("GlobalIllumination", GlobalIllumination);
	SW_SET_INT("Reflections", Reflections);
	SW_SET_INT("PostProcess", PostProcess);
	SW_SET_INT("Textures", Textures);
	SW_SET_INT("Effects", Effects);
	SW_SET_INT("Foliage", Foliage);
	SW_SET_INT("Shading", Shading);
	GConfig->SetFloat(GSection, TEXT("FoliageDensity"), FoliageDensity, Ini);
	GConfig->SetFloat(GSection, TEXT("FoliageDistance"), FoliageDistance, Ini);
	GConfig->SetFloat(GSection, TEXT("FieldOfView"), FieldOfView, Ini);
	GConfig->SetFloat(GSection, TEXT("MouseSensitivity"), MouseSensitivity, Ini);
	GConfig->SetBool(GSection, TEXT("InvertY"), bInvertY, Ini);
	GConfig->SetFloat(GSection, TEXT("HeadMotion"), HeadMotion, Ini);
	GConfig->SetFloat(GSection, TEXT("WalkSpeed"), WalkSpeed, Ini);
	GConfig->SetFloat(GSection, TEXT("MasterVolume"), MasterVolume, Ini);
	GConfig->SetFloat(GSection, TEXT("AmbienceVolume"), AmbienceVolume, Ini);
	GConfig->SetFloat(GSection, TEXT("WeatherIntensity"), WeatherIntensity, Ini);
	GConfig->Flush(false, Ini);
}

#undef SW_GET_INT
#undef SW_SET_INT

static void SetCVar(const FString& Name, float Value)
{
	if (Name.IsEmpty())
	{
		return;
	}
	if (IConsoleVariable* CVar = IConsoleManager::Get().FindConsoleVariable(*Name))
	{
		CVar->Set(Value, ECVF_SetByGameSetting);
	}
}

void FStillworldSettings::Apply(UWorld* World) const
{
	const FStillworldVendorFeatures& V = FStillworldVendorFeatures::Get();

	if (GEngine)
	{
		if (UGameUserSettings* GS = GEngine->GetGameUserSettings())
		{
			GS->SetViewDistanceQuality(ViewDistance);
			GS->SetShadowQuality(Shadows);
			GS->SetGlobalIlluminationQuality(GlobalIllumination);
			GS->SetReflectionQuality(Reflections);
			GS->SetPostProcessingQuality(PostProcess);
			GS->SetTextureQuality(Textures);
			GS->SetVisualEffectQuality(Effects);
			GS->SetFoliageQuality(Foliage);
			GS->SetShadingQuality(Shading);
			GS->SetResolutionScaleValueEx(FMath::Clamp(ScreenPercentage, 33.f, 100.f));
			const EWindowMode::Type Mode = WindowMode == 0 ? EWindowMode::Fullscreen
				: WindowMode == 1 ? EWindowMode::WindowedFullscreen : EWindowMode::Windowed;
			GS->SetFullscreenMode(Mode);
			if (Mode != EWindowMode::Windowed)
			{
				GS->SetScreenResolution(GS->GetDesktopResolution());
			}
			GS->SetVSyncEnabled(bVSync);
			GS->SetFrameRateLimit(FrameLimit);
			GS->ApplySettings(false);
		}
	}

	// --- Ray tracing (only effective if r.RayTracing was on at startup).
	const bool bRT = RayTracing != EStillworldRayTracing::Off && V.HasHardwareRayTracing();
	SetCVar(TEXT("r.Lumen.HardwareRayTracing"), bRT ? 1.f : 0.f);
	// 0 = surface cache lighting, 2 = hit lighting (reflections shaded at the
	// ray hit: mirror-accurate wet surfaces and puddles).
	SetCVar(TEXT("r.Lumen.HardwareRayTracing.LightingMode"),
		bRT && RayTracing == EStillworldRayTracing::LumenHitLit ? 2.f : 0.f);

	// --- "Really ultra" extras on top of the Cinematic scalability tier.
	const bool bCine = GlobalIllumination >= 4;
	SetCVar(TEXT("r.Lumen.ScreenProbeGather.DownsampleFactor"), bCine ? 8.f : 16.f);
	SetCVar(TEXT("r.Lumen.Reflections.MaxRoughnessToTrace"), bCine ? 0.6f : 0.4f);
	SetCVar(TEXT("r.Shadow.Virtual.ResolutionLodBiasDirectional"), Shadows >= 4 ? -1.5f : (Shadows >= 3 ? -1.f : 0.f));
	SetCVar(TEXT("r.VolumetricFog.GridPixelSize"), Effects >= 4 ? 4.f : (Effects >= 3 ? 8.f : 16.f));
	SetCVar(TEXT("r.VolumetricFog.GridSizeZ"), Effects >= 4 ? 128.f : 64.f);
	// Comfort: never motion blur or depth of field in first person.
	SetCVar(TEXT("r.MotionBlurQuality"), 0.f);
	SetCVar(TEXT("r.DepthOfFieldQuality"), 0.f);

	// --- Upscaler and frame generation (vendor plugins, if installed).
	const bool bFSR = Upscaler == EStillworldUpscaler::FSR && V.HasFSR();
	const bool bDLSS = Upscaler == EStillworldUpscaler::DLSS && V.HasDLSS();
	SetCVar(V.FsrEnable, bFSR ? 1.f : 0.f);
	SetCVar(V.DlssEnable, bDLSS ? 1.f : 0.f);
	SetCVar(V.FsrFrameGen, bFSR && bFrameGeneration ? 1.f : 0.f);
	SetCVar(V.DlssFrameGen, bDLSS && bFrameGeneration ? 1.f : 0.f);
	// Low-latency mode whenever frame generation adds a frame of latency.
	SetCVar(V.Reflex, bDLSS && bFrameGeneration ? 1.f : 0.f);
	// TSR is the engine default anti-aliasing method (r.AntiAliasingMethod=4).

	if (World)
	{
		FAudioDeviceHandle Device = World->GetAudioDevice();
		if (Device.IsValid())
		{
			Device->SetTransientPrimaryVolume(FMath::Clamp(MasterVolume, 0.f, 1.f));
		}
	}
	OnChanged.Broadcast();
}
