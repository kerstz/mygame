#pragma once

#include "CoreMinimal.h"

class UWorld;

/** Graphics presets. Ultra is deliberately uncompromising (Cinematic engine
 *  scalability, native resolution, hardware ray tracing with hit lighting):
 *  expect 30-60 fps at 3440x1440. Performance and High target high frame
 *  rates. Values must be confirmed with `-benchmark` (docs/PERFORMANCE.md). */
enum class EStillworldPreset : uint8
{
	Performance,
	High,
	Ultra,
	Custom
};

/** Temporal upscaler. FSR and DLSS require their vendor plugins; options for
 *  missing plugins are hidden in the menu (see FStillworldVendorFeatures). */
enum class EStillworldUpscaler : uint8
{
	TSR,   // Unreal Temporal Super Resolution, works on every GPU
	FSR,   // AMD FidelityFX Super Resolution (AMD FSR plugin)
	DLSS,  // NVIDIA DLSS (NVIDIA DLSS plugin, RTX GPUs)
};

/** Ray tracing mode. Requires r.RayTracing=True (set in DefaultEngine.ini)
 *  and a GPU/driver exposing ray tracing (RDNA2+, RTX). */
enum class EStillworldRayTracing : uint8
{
	Off,          // software Lumen (distance fields)
	Lumen,        // hardware ray traced Lumen GI + reflections
	LumenHitLit,  // + hit lighting: true ray traced reflections (heaviest)
};

/** Runtime detection of optional vendor plugins via their console variables.
 *  The cvar names live in DefaultGame.ini [Stillworld.Vendor] so they can be
 *  updated for new plugin versions without recompiling. */
struct STILLWORLD_API FStillworldVendorFeatures
{
	FString FsrEnable;
	FString FsrFrameGen;
	FString DlssEnable;
	FString DlssFrameGen;
	FString Reflex;

	bool HasFSR() const { return !FsrEnable.IsEmpty(); }
	bool HasDLSS() const { return !DlssEnable.IsEmpty(); }
	bool HasFrameGen(EStillworldUpscaler U) const;
	bool HasHardwareRayTracing() const;

	static const FStillworldVendorFeatures& Get();
};

/**
 * Player settings, persisted in GameUserSettings.ini under [Stillworld].
 */
struct STILLWORLD_API FStillworldSettings
{
	EStillworldPreset Preset = EStillworldPreset::High;

	// Display
	int32 WindowMode = 1;           // 0 fullscreen, 1 borderless, 2 windowed
	bool bVSync = false;
	float FrameLimit = 0.f;         // 0 = unlimited

	// Image
	EStillworldUpscaler Upscaler = EStillworldUpscaler::TSR;
	float ScreenPercentage = 75.f;  // internal resolution
	bool bFrameGeneration = false;
	EStillworldRayTracing RayTracing = EStillworldRayTracing::Off;

	// Engine scalability groups, 0 (low) .. 4 (cinematic).
	int32 ViewDistance = 3;
	int32 Shadows = 3;
	int32 GlobalIllumination = 3;
	int32 Reflections = 3;
	int32 PostProcess = 3;
	int32 Textures = 3;
	int32 Effects = 3;              // volumetric fog, clouds, translucency
	int32 Foliage = 3;
	int32 Shading = 3;

	// Vegetation scatter
	float FoliageDensity = 0.85f;
	float FoliageDistance = 1.f;    // multiplier on per-layer cull distances

	// Controls
	float FieldOfView = 80.f;
	float MouseSensitivity = 0.45f;
	bool bInvertY = false;
	float HeadMotion = 0.35f;       // 0 = perfectly steady camera
	float WalkSpeed = 145.f;        // cm/s

	// Sound / weather
	float MasterVolume = 0.8f;
	float AmbienceVolume = 0.7f;
	float WeatherIntensity = 1.f;

	static FStillworldSettings& Get();

	void Load();
	void Save() const;
	void ApplyPreset(EStillworldPreset InPreset);
	/** Pushes every value to the engine. */
	void Apply(UWorld* World) const;

	static const TCHAR* PresetName(EStillworldPreset P);

	/** Broadcast after Apply(); gameplay objects re-read what they need. */
	static FSimpleMulticastDelegate OnChanged;
};
