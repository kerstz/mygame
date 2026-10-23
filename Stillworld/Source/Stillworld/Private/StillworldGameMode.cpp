#include "StillworldGameMode.h"

#include "EngineUtils.h"
#include "GameFramework/HUD.h"
#include "Kismet/GameplayStatics.h"
#include "Misc/CommandLine.h"
#include "Misc/DateTime.h"
#include "Misc/Parse.h"
#include "StillworldCharacter.h"
#include "StillworldPlayerController.h"
#include "StillworldSoundscape.h"
#include "StillworldWeather.h"
#include "StillworldWorld.h"

AStillworldGameMode::AStillworldGameMode()
{
	DefaultPawnClass = AStillworldCharacter::StaticClass();
	PlayerControllerClass = AStillworldPlayerController::StaticClass();
	HUDClass = AHUD::StaticClass(); // draws nothing
}

static EStillworldWorld ParseWorld(const FString& S, EStillworldWorld Default)
{
	if (S.Equals(TEXT("Reclaimed"), ESearchCase::IgnoreCase) || S.Equals(TEXT("City"), ESearchCase::IgnoreCase))
	{
		return EStillworldWorld::Reclaimed;
	}
	if (S.Equals(TEXT("Meadow"), ESearchCase::IgnoreCase))
	{
		return EStillworldWorld::Meadow;
	}
	return Default;
}

void AStillworldGameMode::InitGame(const FString& MapName, const FString& Options, FString& ErrorMessage)
{
	Super::InitGame(MapName, Options, ErrorMessage);
	FString Cmd;
	WorldKind = ParseWorld(UGameplayStatics::ParseOption(Options, TEXT("World")), EStillworldWorld::Meadow);
	if (FParse::Value(FCommandLine::Get(), TEXT("world="), Cmd))
	{
		WorldKind = ParseWorld(Cmd, WorldKind);
	}
	WorldSeed = UGameplayStatics::GetIntOption(Options, TEXT("Seed"), 0);
	FParse::Value(FCommandLine::Get(), TEXT("seed="), WorldSeed);
	if (WorldSeed == 0)
	{
		// Every new map is different.
		WorldSeed = static_cast<int32>(FPlatformTime::Cycles() ^ static_cast<uint32>(FDateTime::Now().GetTicks())) & 0x7fffffff;
		WorldSeed = FMath::Max(WorldSeed, 1);
	}
	bShowTitle = !UGameplayStatics::HasOption(Options, TEXT("Play"))
		&& !FParse::Param(FCommandLine::Get(), TEXT("benchmark"))
		&& !FParse::Param(FCommandLine::Get(), TEXT("notitle"));
}

void AStillworldGameMode::StartPlay()
{
	Super::StartPlay();
	UWorld* W = GetWorld();
	// Maps built by Content/Python/setup_stillworld.py already contain these;
	// spawning them here keeps any empty test map working too. Weather first:
	// the world actor configures it.
	if (!TActorIterator<AStillworldWeather>(W))
	{
		W->SpawnActor<AStillworldWeather>();
	}
	if (!TActorIterator<AStillworldWorld>(W))
	{
		W->SpawnActor<AStillworldWorld>();
	}
	if (!TActorIterator<AStillworldSoundscape>(W))
	{
		W->SpawnActor<AStillworldSoundscape>();
	}
}

void AStillworldGameMode::TravelToNewWorld(UObject* WorldContext, EStillworldWorld Kind, int32 Seed)
{
	UWorld* W = WorldContext ? WorldContext->GetWorld() : nullptr;
	if (!W)
	{
		return;
	}
	const FString Options = FString::Printf(TEXT("World=%s?Play=1%s"),
		Kind == EStillworldWorld::Meadow ? TEXT("Meadow") : TEXT("Reclaimed"),
		Seed != 0 ? *FString::Printf(TEXT("?Seed=%d"), Seed) : TEXT(""));
	UGameplayStatics::OpenLevel(W, FName(*UGameplayStatics::GetCurrentLevelName(W, true)), true, Options);
}
