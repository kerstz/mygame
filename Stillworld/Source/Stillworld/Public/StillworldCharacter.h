#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "StillworldCharacter.generated.h"

class UCameraComponent;
struct FInputActionValue;

/**
 * Invisible first-person walker. No jump, no sprint, no body: a person
 * strolling. Camera height is smoothed over bumps and a very small optional
 * head motion can be enabled in the settings.
 */
UCLASS()
class STILLWORLD_API AStillworldCharacter : public ACharacter
{
	GENERATED_BODY()

public:
	AStillworldCharacter();

	virtual void SetupPlayerInputComponent(UInputComponent* PlayerInputComponent) override;
	virtual void BeginPlay() override;
	virtual void EndPlay(const EEndPlayReason::Type Reason) override;
	virtual void Tick(float DeltaSeconds) override;

	UCameraComponent* GetCamera() const { return Camera; }

	/** Scripted input (X = right, Y = forward) used by the benchmark. */
	FVector2D AutoWalk = FVector2D::ZeroVector;

	/** Soft world boundary (cm from origin) until World Partition streaming
	 *  replaces the single landscape. 0 disables it. */
	UPROPERTY(EditAnywhere, Category = "Stillworld")
	float BoundaryRadius = 180000.f;

	/** Human eye height above the ground, in cm. */
	UPROPERTY(EditAnywhere, Category = "Stillworld")
	float EyeHeight = 165.f;

private:
	UPROPERTY(VisibleAnywhere, Category = "Stillworld")
	TObjectPtr<UCameraComponent> Camera;

	FVector2D MoveInput = FVector2D::ZeroVector;
	float StepPhase = 0.f;
	float WalkBlend = 0.f;
	float SmoothedZ = 0.f;
	FDelegateHandle SettingsHandle;

	void Move(const FInputActionValue& Value);
	void Look(const FInputActionValue& Value);
	void ApplySettings();
	void UpdateCamera(float DeltaSeconds);
};
