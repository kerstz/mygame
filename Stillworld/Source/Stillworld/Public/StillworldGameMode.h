#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "StillworldGenerator.h"
#include "StillworldGameMode.generated.h"

/**
 * No HUD, no rules. Reads the world kind and seed from the level URL
 * (?World=Meadow|Reclaimed?Seed=N?Play=1) or the command line
 * (-world= -seed=), and makes sure the weather, world and sound actors exist.
 * Without ?Play=1 the game opens on the title menu over a live landscape.
 */
UCLASS()
class STILLWORLD_API AStillworldGameMode : public AGameModeBase
{
	GENERATED_BODY()

public:
	AStillworldGameMode();
	virtual void InitGame(const FString& MapName, const FString& Options, FString& ErrorMessage) override;
	virtual void StartPlay() override;

	EStillworldWorld WorldKind = EStillworldWorld::Meadow;
	int32 WorldSeed = 0;
	bool bShowTitle = true;

	/** Reloads the level with a new random (or given) map of `Kind`. */
	static void TravelToNewWorld(UObject* WorldContext, EStillworldWorld Kind, int32 Seed = 0);
};
