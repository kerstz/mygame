#pragma once

#include "CoreMinimal.h"
#include "GameFramework/PlayerController.h"
#include "StillworldPlayerController.generated.h"

class UInputAction;
class UInputMappingContext;
class SStillworldMenu;

/**
 * Owns the input objects (built in code, no assets), the pause menu (Slate,
 * no assets) and the developer tools (F3 stats, -benchmark run).
 */
UCLASS()
class STILLWORLD_API AStillworldPlayerController : public APlayerController
{
	GENERATED_BODY()

public:
	virtual void BeginPlay() override;
	virtual void SetupInputComponent() override;
	virtual void EndPlay(const EEndPlayReason::Type Reason) override;
	virtual void PlayerTick(float DeltaTime) override;

	void EnsureInputObjects();
	/** Opens the title screen (world not paused) or the pause menu. */
	void SetMenuOpen(bool bOpen, bool bTitle = false);
	bool IsMenuOpen() const { return bMenuOpen; }

	UPROPERTY() TObjectPtr<UInputMappingContext> Mapping;
	UPROPERTY() TObjectPtr<UInputAction> MoveAction;
	UPROPERTY() TObjectPtr<UInputAction> LookAction;
	UPROPERTY() TObjectPtr<UInputAction> MenuAction;
	UPROPERTY() TObjectPtr<UInputAction> StatsAction;

private:
	TSharedPtr<SStillworldMenu> Menu;
	TSharedPtr<class SWidget> MenuContainer;
	bool bMenuOpen = false;
	int32 StatsMode = 0;

	void ToggleMenu();
	void CycleStats();

	// Benchmark state: Idle -> Warmup (streaming, shader compilation) ->
	// Measure (walking forward) -> written to Saved/Benchmark and quit.
	enum class EBench : uint8 { Off, Warmup, Measure };
	EBench Bench = EBench::Off;
	double BenchPhaseStart = 0.0;
	TArray<float> BenchFrames;
	TArray<float> BenchGpu;
	void BenchmarkTick(float DeltaTime);
	void BenchmarkFinish();
};
