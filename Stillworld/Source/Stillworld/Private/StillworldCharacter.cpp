#include "StillworldCharacter.h"

#include "Camera/CameraComponent.h"
#include "Components/CapsuleComponent.h"
#include "EnhancedInputComponent.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "InputActionValue.h"
#include "StillworldPlayerController.h"
#include "StillworldSettings.h"

AStillworldCharacter::AStillworldCharacter()
{
	PrimaryActorTick.bCanEverTick = true;

	GetCapsuleComponent()->InitCapsuleSize(30.f, 88.f);

	Camera = CreateDefaultSubobject<UCameraComponent>(TEXT("Camera"));
	Camera->SetupAttachment(GetCapsuleComponent());
	Camera->SetRelativeLocation(FVector(0.f, 0.f, EyeHeight - 88.f));
	Camera->bUsePawnControlRotation = true;
	Camera->PostProcessBlendWeight = 0.f; // level post-process volume rules the look

	bUseControllerRotationYaw = true;
	bUseControllerRotationPitch = false;
	bUseControllerRotationRoll = false;

	UCharacterMovementComponent* MoveComp = GetCharacterMovement();
	MoveComp->MaxWalkSpeed = 145.f;
	// ~0.5 s to reach walking pace, a slightly quicker but soft stop.
	MoveComp->MaxAcceleration = 300.f;
	MoveComp->BrakingDecelerationWalking = 420.f;
	MoveComp->GroundFriction = 6.f;
	MoveComp->bUseSeparateBrakingFriction = false;
	MoveComp->MaxStepHeight = 40.f;
	MoveComp->SetWalkableFloorAngle(46.f);
	MoveComp->bOrientRotationToMovement = false;
	MoveComp->GetNavAgentPropertiesRef().bCanCrouch = false;
	MoveComp->GetNavAgentPropertiesRef().bCanJump = false;

	// Nothing of the body is ever rendered.
	GetMesh()->SetVisibility(false);
	GetMesh()->SetCastShadow(false);
}

void AStillworldCharacter::BeginPlay()
{
	Super::BeginPlay();
	SmoothedZ = GetActorLocation().Z;
	ApplySettings();
	SettingsHandle = FStillworldSettings::OnChanged.AddUObject(this, &AStillworldCharacter::ApplySettings);
}

void AStillworldCharacter::EndPlay(const EEndPlayReason::Type Reason)
{
	FStillworldSettings::OnChanged.Remove(SettingsHandle);
	Super::EndPlay(Reason);
}

void AStillworldCharacter::ApplySettings()
{
	const FStillworldSettings& S = FStillworldSettings::Get();
	Camera->SetFieldOfView(S.FieldOfView);
	GetCharacterMovement()->MaxWalkSpeed = S.WalkSpeed;
}

void AStillworldCharacter::SetupPlayerInputComponent(UInputComponent* PlayerInputComponent)
{
	Super::SetupPlayerInputComponent(PlayerInputComponent);
	AStillworldPlayerController* PC = Cast<AStillworldPlayerController>(GetController());
	UEnhancedInputComponent* Input = Cast<UEnhancedInputComponent>(PlayerInputComponent);
	if (!PC || !Input)
	{
		return;
	}
	PC->EnsureInputObjects();
	Input->BindAction(PC->MoveAction, ETriggerEvent::Triggered, this, &AStillworldCharacter::Move);
	Input->BindAction(PC->MoveAction, ETriggerEvent::Completed, this, &AStillworldCharacter::Move);
	Input->BindAction(PC->LookAction, ETriggerEvent::Triggered, this, &AStillworldCharacter::Look);
}

void AStillworldCharacter::Move(const FInputActionValue& Value)
{
	MoveInput = Value.Get<FVector2D>();
}

static bool MenuOpen(const APawn* Pawn)
{
	const AStillworldPlayerController* PC = Cast<AStillworldPlayerController>(Pawn->GetController());
	return PC && PC->IsMenuOpen();
}

void AStillworldCharacter::Look(const FInputActionValue& Value)
{
	if (MenuOpen(this))
	{
		return;
	}
	const FStillworldSettings& S = FStillworldSettings::Get();
	const FVector2D V = Value.Get<FVector2D>() * S.MouseSensitivity;
	AddControllerYawInput(V.X);
	// Mouse up is +Y; with the engine's legacy pitch scale a negative pitch
	// input looks up, hence the sign flip (as in the UE templates).
	AddControllerPitchInput(S.bInvertY ? V.Y : -V.Y);
}

void AStillworldCharacter::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);

	const FVector2D In = !AutoWalk.IsNearlyZero() ? AutoWalk : (MenuOpen(this) ? FVector2D::ZeroVector : MoveInput);
	if (!In.IsNearlyZero())
	{
		const FRotator Yaw(0.f, GetControlRotation().Yaw, 0.f);
		FVector Dir = FRotationMatrix(Yaw).GetUnitAxis(EAxis::X) * In.Y
			+ FRotationMatrix(Yaw).GetUnitAxis(EAxis::Y) * In.X;
		Dir = Dir.GetClampedToMaxSize(1.f);

		// Soft boundary: remove the outward component near the edge.
		if (BoundaryRadius > 0.f)
		{
			const FVector Flat(GetActorLocation().X, GetActorLocation().Y, 0.f);
			if (Flat.Size() > BoundaryRadius)
			{
				const FVector Out = Flat.GetSafeNormal();
				const float Outward = FVector::DotProduct(Dir, Out);
				if (Outward > 0.f)
				{
					Dir -= Out * Outward;
				}
			}
		}
		AddMovementInput(Dir, 1.f);
	}
	UpdateCamera(DeltaSeconds);
}

void AStillworldCharacter::UpdateCamera(float DeltaSeconds)
{
	const FStillworldSettings& S = FStillworldSettings::Get();
	const float ActorZ = GetActorLocation().Z;
	// Smooth the eye over step-ups (rocks, roots) instead of snapping.
	SmoothedZ = FMath::FInterpTo(SmoothedZ, ActorZ, DeltaSeconds, 12.f);
	SmoothedZ = FMath::Clamp(SmoothedZ, ActorZ - 30.f, ActorZ + 30.f);

	const float Speed = GetVelocity().Size2D();
	const float Walking = FMath::Clamp(Speed / 140.f, 0.f, 1.f);
	WalkBlend = FMath::FInterpTo(WalkBlend, Walking, DeltaSeconds, 4.f);
	// About 1.8 steps per second at walking pace.
	StepPhase += DeltaSeconds * UE_TWO_PI * 0.9f * FMath::Clamp(Speed / 140.f, 0.3f, 1.3f);
	const float Amount = S.HeadMotion * WalkBlend;
	const float BobZ = FMath::Sin(StepPhase * 2.f) * 1.8f * Amount;   // cm
	const float SwayY = FMath::Sin(StepPhase) * 1.0f * Amount;        // cm

	Camera->SetRelativeLocation(FVector(0.f, SwayY, EyeHeight - 88.f + BobZ + (SmoothedZ - ActorZ)));
}
