#include "StillworldWeather.h"

#include "Camera/PlayerCameraManager.h"
#include "Components/AudioComponent.h"
#include "Components/ExponentialHeightFogComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Engine/ExponentialHeightFog.h"
#include "Engine/StaticMesh.h"
#include "EngineUtils.h"
#include "Kismet/GameplayStatics.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Materials/MaterialParameterCollection.h"
#include "Materials/MaterialParameterCollectionInstance.h"
#include "Sound/SoundBase.h"
#include "StillworldSettings.h"
#include "UObject/ConstructorHelpers.h"

AStillworldWeather::AStillworldWeather()
{
	PrimaryActorTick.bCanEverTick = true;
	PrimaryActorTick.TickGroup = TG_PostUpdateWork; // after the camera moved

	RootComponent = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));

	static ConstructorHelpers::FObjectFinder<UStaticMesh> Cylinder(TEXT("/Engine/BasicShapes/Cylinder.Cylinder"));
	auto MakeLayer = [this, &Cylinder](const TCHAR* Name, const FVector& Scale)
	{
		UStaticMeshComponent* M = CreateDefaultSubobject<UStaticMeshComponent>(Name);
		M->SetupAttachment(RootComponent);
		if (Cylinder.Succeeded())
		{
			M->SetStaticMesh(Cylinder.Object);
		}
		M->SetRelativeScale3D(Scale);
		M->SetCollisionEnabled(ECollisionEnabled::NoCollision);
		M->SetCastShadow(false);
		M->bAffectDistanceFieldLighting = false;
		M->bAffectDynamicIndirectLighting = false;
		M->SetVisibleInRayTracing(false);
		M->SetUsingAbsoluteRotation(true);
		M->bNeverDistanceCull = true;
		return M;
	};
	// Engine cylinder: 1 m diameter, 1 m tall, pivot at the centre.
	RainNear = MakeLayer(TEXT("RainNear"), FVector(9.f, 9.f, 14.f));
	RainFar = MakeLayer(TEXT("RainFar"), FVector(30.f, 30.f, 26.f));

	RainAudio = CreateDefaultSubobject<UAudioComponent>(TEXT("RainAudio"));
	RainAudio->SetupAttachment(RootComponent);
	RainAudio->bAutoActivate = false;
	RainAudio->bIsUISound = false;
	RainAudio->bAllowSpatialization = false;
	WindAudio = CreateDefaultSubobject<UAudioComponent>(TEXT("WindAudio"));
	WindAudio->SetupAttachment(RootComponent);
	WindAudio->bAutoActivate = false;
	WindAudio->bAllowSpatialization = false;

	WeatherCollection = TSoftObjectPtr<UMaterialParameterCollection>(FSoftObjectPath(TEXT("/Game/Stillworld/Core/MPC_Weather.MPC_Weather")));
	RainMaterial = TSoftObjectPtr<UMaterialInterface>(FSoftObjectPath(TEXT("/Game/Stillworld/Materials/M_RainCurtain.M_RainCurtain")));
	RainSound = TSoftObjectPtr<USoundBase>(FSoftObjectPath(TEXT("/Game/Stillworld/Audio/SW_Rain.SW_Rain")));
	WindSound = TSoftObjectPtr<USoundBase>(FSoftObjectPath(TEXT("/Game/Stillworld/Audio/SW_Wind.SW_Wind")));
}

void AStillworldWeather::SetupRainLayer(UStaticMeshComponent* Mesh, UMaterialInterface* Mat, float Tiling, float Speed, float Opacity)
{
	if (!Mat)
	{
		Mesh->SetVisibility(false);
		return;
	}
	UMaterialInstanceDynamic* MID = UMaterialInstanceDynamic::Create(Mat, this);
	MID->SetScalarParameterValue(TEXT("Tiling"), Tiling);
	MID->SetScalarParameterValue(TEXT("Speed"), Speed);
	MID->SetScalarParameterValue(TEXT("LayerOpacity"), Opacity);
	Mesh->SetMaterial(0, MID);
}

void AStillworldWeather::BeginPlay()
{
	Super::BeginPlay();
	LoadedCollection = WeatherCollection.LoadSynchronous();
	UMaterialInterface* Mat = RainMaterial.LoadSynchronous();
	SetupRainLayer(RainNear, Mat, 4.f, 1.6f, 0.55f);
	SetupRainLayer(RainFar, Mat, 9.f, 1.1f, 0.35f);

	if (USoundBase* S = RainSound.LoadSynchronous())
	{
		RainAudio->SetSound(S);
		RainAudio->SetVolumeMultiplier(0.001f);
		RainAudio->Play();
	}
	if (USoundBase* S = WindSound.LoadSynchronous())
	{
		WindAudio->SetSound(S);
		WindAudio->SetVolumeMultiplier(0.001f);
		WindAudio->Play();
	}
	for (TActorIterator<AExponentialHeightFog> It(GetWorld()); It; ++It)
	{
		Fog = It->GetComponent();
		BaseFogDensity = Fog ? Fog->FogDensity : 0.f;
		break;
	}
	// Start wet if it is raining: the player arrives mid-shower.
	Wetness = FMath::Clamp(Rain * 1.4f, 0.f, 1.f);
}

void AStillworldWeather::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);
	Time += DeltaSeconds;
	const FStillworldSettings& S = FStillworldSettings::Get();
	const float RainNow = FMath::Clamp(Rain * S.WeatherIntensity, 0.f, 1.5f);

	// Wind: slowly wandering direction, overlapping slow gust cycles.
	WindAngle += FMath::Sin(Time * 0.013f) * DeltaSeconds * 0.02f;
	const float Gust = 0.75f + 0.25f * FMath::Sin(Time * 0.21f) * FMath::Sin(Time * 0.057f + 1.3f);
	const float WindNow = Wind * Gust;

	// Ground and foliage wet in ~30 s, dry in ~2 min.
	const float TargetWet = FMath::Clamp(RainNow * 1.4f, 0.f, 1.f);
	const float Rate = TargetWet > Wetness ? 1.f / 30.f : 1.f / 120.f;
	Wetness = FMath::FInterpConstantTo(Wetness, TargetWet, DeltaSeconds, Rate);

	if (LoadedCollection)
	{
		if (UMaterialParameterCollectionInstance* MPC = GetWorld()->GetParameterCollectionInstance(LoadedCollection))
		{
			MPC->SetScalarParameterValue(TEXT("Wetness"), Wetness);
			MPC->SetScalarParameterValue(TEXT("RainIntensity"), RainNow);
			MPC->SetScalarParameterValue(TEXT("WindStrength"), WindNow);
			MPC->SetScalarParameterValue(TEXT("WindDirX"), FMath::Cos(WindAngle));
			MPC->SetScalarParameterValue(TEXT("WindDirY"), FMath::Sin(WindAngle));
		}
	}

	// Keep the rain curtains centred on the camera.
	if (APlayerCameraManager* Cam = UGameplayStatics::GetPlayerCameraManager(this, 0))
	{
		SetActorLocation(Cam->GetCameraLocation());
	}
	const bool bRaining = RainNow > 0.02f;
	RainNear->SetVisibility(bRaining);
	RainFar->SetVisibility(bRaining);

	if (Fog && BaseFogDensity > 0.f)
	{
		const float Breath = 1.f + FogBreathing * FMath::Sin(Time * 0.035f) * FMath::Sin(Time * 0.011f + 0.7f);
		Fog->SetFogDensity(BaseFogDensity * FogScale * Breath * (1.f + RainNow * 0.15f));
	}

	const float Amb = S.AmbienceVolume;
	RainAudio->SetVolumeMultiplier(FMath::Max(0.001f, RainNow * Amb * 0.8f));
	WindAudio->SetVolumeMultiplier(FMath::Max(0.001f, (0.2f + WindNow * 0.6f) * Amb * 0.6f));
}
