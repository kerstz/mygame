#include "StillworldSoundscape.h"

#include "Camera/PlayerCameraManager.h"
#include "EngineUtils.h"
#include "GameFramework/Character.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "Kismet/GameplayStatics.h"
#include "Sound/SoundAttenuation.h"
#include "Sound/SoundBase.h"
#include "StillworldSettings.h"
#include "StillworldWeather.h"
#include "StillworldWorld.h"

AStillworldSoundscape::AStillworldSoundscape()
{
	PrimaryActorTick.bCanEverTick = true;
	RootComponent = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));
}

void AStillworldSoundscape::LoadBank(const FString& Name)
{
	FBank& Bank = Banks.FindOrAdd(Name);
	for (int32 I = 1; I <= 12; ++I)
	{
		const FString Asset = FString::Printf(TEXT("%s_%02d"), *Name, I);
		const FString Path = FString::Printf(TEXT("/Game/Stillworld/Audio/SFX/%s.%s"), *Asset, *Asset);
		if (USoundBase* S = LoadObject<USoundBase>(nullptr, *Path, nullptr, LOAD_NoWarn | LOAD_Quiet))
		{
			Bank.Sounds.Add(S);
			KeepAlive.Add(S);
		}
	}
}

USoundBase* AStillworldSoundscape::Pick(const FString& Name)
{
	FBank* Bank = Banks.Find(Name);
	if (!Bank || Bank->Sounds.Num() == 0)
	{
		return nullptr;
	}
	int32 I = FMath::RandHelper(Bank->Sounds.Num());
	if (Bank->Sounds.Num() > 1 && I == Bank->Last)
	{
		I = (I + 1 + FMath::RandHelper(Bank->Sounds.Num() - 1)) % Bank->Sounds.Num();
	}
	Bank->Last = I;
	return Bank->Sounds[I];
}

void AStillworldSoundscape::BeginPlay()
{
	Super::BeginPlay();
	for (const TCHAR* Name : { TEXT("Foot_Grass"), TEXT("Foot_Dirt"), TEXT("Foot_Asphalt"), TEXT("Foot_Wet"),
		TEXT("Drip"), TEXT("Bird"), TEXT("Crow"), TEXT("Thunder_Far"), TEXT("Metal_Creak"), TEXT("Leaves_Gust") })
	{
		LoadBank(Name);
	}

	// Natural inverse-distance falloff, spatialised (binaural-ready).
	auto MakeAtt = [this](float Inner, float Falloff)
	{
		USoundAttenuation* A = NewObject<USoundAttenuation>(this);
		A->Attenuation.bAttenuate = true;
		A->Attenuation.bSpatialize = true;
		A->Attenuation.AttenuationShape = EAttenuationShape::Sphere;
		A->Attenuation.AttenuationShapeExtents = FVector(Inner, 0.f, 0.f);
		A->Attenuation.FalloffDistance = Falloff;
		A->Attenuation.DistanceAlgorithm = EAttenuationDistanceModel::NaturalSound;
		// Air absorption: distant sounds lose their highs.
		A->Attenuation.bAttenuateWithLPF = true;
		A->Attenuation.LPFRadiusMin = Inner * 4.f;
		A->Attenuation.LPFRadiusMax = Falloff;
		KeepAlive.Add(A);
		return A;
	};
	NearAttenuation = MakeAtt(150.f, 6000.f);
	FarAttenuation = MakeAtt(2000.f, 250000.f);

	const bool bTown = AStillworldWorld::Find(this)
		&& AStillworldWorld::Find(this)->GetGenerator().GetWorld() == EStillworldWorld::Reclaimed;
	auto Add = [this](const TCHAR* Bank, FVector2f Interval, FVector2f Dist, FVector2f Height, float Vol) -> FAmbient&
	{
		FAmbient A;
		A.Bank = Bank;
		A.Interval = Interval;
		A.Distance = Dist;
		A.HeightOffset = Height;
		A.Volume = Vol;
		A.NextTime = FMath::FRandRange(Interval.X * 0.3f, Interval.Y);
		return Ambients.Add_GetRef(A);
	};
	Add(TEXT("Drip"), { 1.5f, 5.f }, { 2.f, 9.f }, { -1.f, 2.f }, 0.35f).bNeedsRain = true;
	Add(TEXT("Bird"), { 14.f, 40.f }, { 35.f, 120.f }, { 3.f, 15.f }, 0.3f).bNoHeavyRain = true;
	Add(TEXT("Crow"), { bTown ? 25.f : 60.f, bTown ? 70.f : 160.f }, { 60.f, 200.f }, { 10.f, 30.f }, 0.35f).bFar = true;
	FAmbient& Thunder = Add(TEXT("Thunder_Far"), { 70.f, 220.f }, { 1500.f, 3500.f }, { 200.f, 600.f }, 0.55f);
	Thunder.bNeedsRain = true;
	Thunder.bFar = true;
	if (bTown)
	{
		Add(TEXT("Metal_Creak"), { 18.f, 55.f }, { 12.f, 45.f }, { 0.f, 8.f }, 0.4f).bTownOnly = true;
	}
	Add(TEXT("Leaves_Gust"), { 9.f, 24.f }, { 8.f, 30.f }, { 1.f, 6.f }, 0.4f).bNeedsWind = true;
}

void AStillworldSoundscape::Play(USoundBase* Sound, const FVector& Where, float Volume, float Pitch, USoundAttenuation* Att)
{
	if (Sound)
	{
		UGameplayStatics::PlaySoundAtLocation(this, Sound, Where, FRotator::ZeroRotator, Volume, Pitch, 0.f, Att);
	}
}

void AStillworldSoundscape::Footstep(const FVector& FootPos)
{
	const FStillworldSettings& S = FStillworldSettings::Get();
	const AStillworldWorld* World = AStillworldWorld::Find(this);
	FString Bank = TEXT("Foot_Grass");
	if (World)
	{
		const FVector4f Sf = World->GetGenerator().Surface(FootPos.X / 100.f, FootPos.Y / 100.f);
		if (Sf.Z > 0.5f)
		{
			Bank = TEXT("Foot_Asphalt");
		}
		else if (Sf.Y > Sf.X)
		{
			Bank = TEXT("Foot_Dirt");
		}
	}
	const float Vol = FootstepVolume * S.AmbienceVolume * FMath::FRandRange(0.8f, 1.05f);
	Play(Pick(Bank), FootPos, Vol, FMath::FRandRange(0.92f, 1.08f), NearAttenuation);

	float Wet = 0.f;
	for (TActorIterator<AStillworldWeather> It(GetWorld()); It; ++It)
	{
		Wet = It->GetWetness();
		break;
	}
	if (Wet > 0.35f)
	{
		Play(Pick(TEXT("Foot_Wet")), FootPos, Vol * Wet * 0.7f, FMath::FRandRange(0.9f, 1.1f), NearAttenuation);
	}
}

void AStillworldSoundscape::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);
	Time += DeltaSeconds;
	ACharacter* Pawn = Cast<ACharacter>(UGameplayStatics::GetPlayerPawn(this, 0));
	APlayerCameraManager* Cam = UGameplayStatics::GetPlayerCameraManager(this, 0);
	if (!Pawn || !Cam)
	{
		return;
	}

	// --- Footsteps from distance actually walked on the ground.
	const FVector Feet = Pawn->GetActorLocation() - FVector(0, 0, Pawn->GetSimpleCollisionHalfHeight());
	const bool bGrounded = Pawn->GetCharacterMovement() && Pawn->GetCharacterMovement()->IsMovingOnGround();
	if (bHasLast && bGrounded)
	{
		Walked += FVector::Dist2D(Feet, LastFootPos);
		if (Walked >= StrideLength)
		{
			Walked = 0.f;
			Footstep(Feet);
		}
	}
	else
	{
		Walked = StrideLength * 0.5f;
	}
	LastFootPos = Feet;
	bHasLast = true;

	// --- Sparse ambient one-shots around the listener.
	float Rain = 0.f, Wind = 0.f;
	for (TActorIterator<AStillworldWeather> It(GetWorld()); It; ++It)
	{
		Rain = It->Rain * FStillworldSettings::Get().WeatherIntensity;
		Wind = It->Wind;
		break;
	}
	const FVector Listener = Cam->GetCameraLocation();
	const float Amb = FStillworldSettings::Get().AmbienceVolume;
	for (FAmbient& A : Ambients)
	{
		if (Time < A.NextTime)
		{
			continue;
		}
		A.NextTime = Time + FMath::FRandRange(A.Interval.X, A.Interval.Y);
		if ((A.bNeedsRain && Rain < 0.2f) || (A.bNoHeavyRain && Rain > 0.7f) || (A.bNeedsWind && Wind < 0.35f))
		{
			continue;
		}
		const float Angle = FMath::FRandRange(0.f, UE_TWO_PI);
		const float Dist = FMath::FRandRange(A.Distance.X, A.Distance.Y) * 100.f;
		const FVector Where = Listener + FVector(FMath::Cos(Angle) * Dist, FMath::Sin(Angle) * Dist,
			FMath::FRandRange(A.HeightOffset.X, A.HeightOffset.Y) * 100.f);
		Play(Pick(A.Bank), Where, A.Volume * Amb * FMath::FRandRange(0.7f, 1.f), FMath::FRandRange(0.94f, 1.06f),
			A.bFar ? FarAttenuation.Get() : NearAttenuation.Get());
	}
}
