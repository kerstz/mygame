#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "StillworldSoundscape.generated.h"

class USoundBase;
class USoundAttenuation;

/**
 * Environmental sound design (there is no music, by design):
 *  - footsteps chosen from the actual surface under the player (grass, dirt,
 *    asphalt) with a wet layer when the ground is soaked; random variant,
 *    pitch and volume per step, never the same sample twice in a row;
 *  - sparse, spatialised one-shots placed at random positions around the
 *    listener: drips, distant birds and crows, far thunder in rain, metal
 *    creaks in ruined towns, gusts through foliage.
 * Continuous rain/wind beds are handled by AStillworldWeather.
 *
 * Sounds are loaded by name from /Game/Stillworld/Audio/SFX/<Name>_01..NN, so
 * replacing placeholders with real CC0 recordings needs no code change.
 */
UCLASS()
class STILLWORLD_API AStillworldSoundscape : public AActor
{
	GENERATED_BODY()

public:
	AStillworldSoundscape();
	virtual void BeginPlay() override;
	virtual void Tick(float DeltaSeconds) override;

	/** Distance walked between two footsteps (cm). */
	UPROPERTY(EditAnywhere, Category = "Sound")
	float StrideLength = 72.f;

	UPROPERTY(EditAnywhere, Category = "Sound")
	float FootstepVolume = 0.45f;

private:
	struct FBank
	{
		TArray<TObjectPtr<USoundBase>> Sounds;
		int32 Last = -1;
	};

	struct FAmbient
	{
		FString Bank;
		FVector2f Interval;   // seconds between events
		FVector2f Distance;   // metres from the listener
		FVector2f HeightOffset; // metres above the listener
		float Volume = 0.5f;
		float NextTime = 0.f;
		bool bNeedsRain = false;
		bool bNoHeavyRain = false;
		bool bTownOnly = false;
		bool bNeedsWind = false;
		bool bFar = false;    // uses the long-range attenuation
	};

	TMap<FString, FBank> Banks;
	TArray<FAmbient> Ambients;

	UPROPERTY(Transient)
	TArray<TObjectPtr<UObject>> KeepAlive;

	UPROPERTY(Transient)
	TObjectPtr<USoundAttenuation> NearAttenuation;

	UPROPERTY(Transient)
	TObjectPtr<USoundAttenuation> FarAttenuation;

	FVector LastFootPos = FVector::ZeroVector;
	float Walked = 0.f;
	float Time = 0.f;
	bool bHasLast = false;

	void LoadBank(const FString& Name);
	USoundBase* Pick(const FString& Name);
	void Play(USoundBase* Sound, const FVector& Where, float Volume, float Pitch, USoundAttenuation* Att);
	void Footstep(const FVector& FootPos);
};
