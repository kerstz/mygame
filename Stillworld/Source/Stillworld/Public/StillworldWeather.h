#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "StillworldWeather.generated.h"

class UAudioComponent;
class UMaterialInstanceDynamic;
class UMaterialInterface;
class UMaterialParameterCollection;
class USoundBase;
class UStaticMeshComponent;
class UExponentialHeightFogComponent;

/**
 * Weather state for the whole level.
 *
 * Drives the material parameter collection MPC_Weather (Wetness,
 * RainIntensity, WindStrength, WindDirX, WindDirY) that every Stillworld
 * material reads, the rain curtains around the camera, the ambience loops
 * and a slow "breathing" of the height fog density.
 *
 * Rain is rendered as two nested, camera-centred translucent cylinders with
 * scrolling streak textures (parallax between layers gives depth). This is
 * far cheaper than tens of thousands of particles and reads well in fine
 * drizzle, which is what the reference shows.
 */
UCLASS()
class STILLWORLD_API AStillworldWeather : public AActor
{
	GENERATED_BODY()

public:
	AStillworldWeather();
	virtual void BeginPlay() override;
	virtual void Tick(float DeltaSeconds) override;

	/** 0..1 base rain for this level (scaled by the player's setting). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Weather", meta = (ClampMin = 0, ClampMax = 1))
	float Rain = 0.55f;

	/** 0..1 base wind strength. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Weather", meta = (ClampMin = 0, ClampMax = 1))
	float Wind = 0.6f;

	/** Per-world multiplier on the level's height fog density. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Weather")
	float FogScale = 1.f;

	/** Relative amplitude of slow fog density variation (0 = static fog). */
	UPROPERTY(EditAnywhere, Category = "Weather")
	float FogBreathing = 0.12f;

	UPROPERTY(EditAnywhere, Category = "Weather|Assets")
	TSoftObjectPtr<UMaterialParameterCollection> WeatherCollection;

	UPROPERTY(EditAnywhere, Category = "Weather|Assets")
	TSoftObjectPtr<UMaterialInterface> RainMaterial;

	UPROPERTY(EditAnywhere, Category = "Weather|Assets")
	TSoftObjectPtr<USoundBase> RainSound;

	UPROPERTY(EditAnywhere, Category = "Weather|Assets")
	TSoftObjectPtr<USoundBase> WindSound;

	float GetWetness() const { return Wetness; }

private:
	UPROPERTY(VisibleAnywhere, Category = "Weather")
	TObjectPtr<UStaticMeshComponent> RainNear;

	UPROPERTY(VisibleAnywhere, Category = "Weather")
	TObjectPtr<UStaticMeshComponent> RainFar;

	UPROPERTY(VisibleAnywhere, Category = "Weather")
	TObjectPtr<UAudioComponent> RainAudio;

	UPROPERTY(VisibleAnywhere, Category = "Weather")
	TObjectPtr<UAudioComponent> WindAudio;

	UPROPERTY(Transient)
	TObjectPtr<UMaterialParameterCollection> LoadedCollection;

	UPROPERTY(Transient)
	TObjectPtr<UExponentialHeightFogComponent> Fog;

	float Wetness = 0.f;
	float WindAngle = 0.6f;
	float Time = 0.f;
	float BaseFogDensity = 0.f;

	void SetupRainLayer(UStaticMeshComponent* Mesh, UMaterialInterface* Mat, float Tiling, float Speed, float Opacity);
};
