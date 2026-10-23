#pragma once

#include "CoreMinimal.h"
#include "Engine/DeveloperSettings.h"
#include "StillworldAssetSettings.generated.h"

class UStaticMesh;
class UMaterialInterface;

/** Where a scatter layer may place instances. */
UENUM()
enum class EStillworldPlacement : uint8
{
	/** Natural ground: never on roads or inside building footprints. */
	Natural,
	/** On asphalt: abandoned cars, debris, grass breaking through cracks. */
	Road,
	/** One instance per town lot, set back from and aligned with the road. */
	Lot,
	/** Around buildings and along sidewalks (rubble, bushes, ivy clumps). */
	NearBuildings,
};

/** Which terrain surface weight multiplies the density (vertex colours). */
UENUM()
enum class EStillworldSurfaceMask : uint8
{
	None, Grass, Dirt, Asphalt, Moss
};

/** One family of scattered meshes (e.g. "tall grass", "spruce", "sedan"). */
USTRUCT()
struct FStillworldScatterLayer
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, Category = "Scatter")
	FName Name;

	/** Variants; one is picked per instance. Fab / Megascans Nanite meshes recommended. */
	UPROPERTY(EditAnywhere, Category = "Scatter")
	TArray<TSoftObjectPtr<UStaticMesh>> Meshes;

	UPROPERTY(EditAnywhere, Category = "Scatter")
	EStillworldPlacement Placement = EStillworldPlacement::Natural;

	UPROPERTY(EditAnywhere, Category = "Scatter")
	EStillworldSurfaceMask SurfaceMask = EStillworldSurfaceMask::None;

	/** Instances per 100 m² at density 1 (ignored for Lot placement). */
	UPROPERTY(EditAnywhere, Category = "Scatter", meta = (ClampMin = 0))
	float Density = 10.f;

	/** For Lot placement: probability that a lot holds a building. */
	UPROPERTY(EditAnywhere, Category = "Scatter", meta = (ClampMin = 0, ClampMax = 1))
	float LotProbability = 0.7f;

	/** 0 = uniform, 1 = strongly clustered in patches. */
	UPROPERTY(EditAnywhere, Category = "Scatter", meta = (ClampMin = 0, ClampMax = 1))
	float Clumping = 0.3f;

	/** Size of the clusters in metres. */
	UPROPERTY(EditAnywhere, Category = "Scatter")
	float ClumpSize = 25.f;

	UPROPERTY(EditAnywhere, Category = "Scatter")
	FVector2D ScaleRange = FVector2D(0.8, 1.2);

	/** Maximum ground slope in degrees. */
	UPROPERTY(EditAnywhere, Category = "Scatter")
	float MaxSlope = 35.f;

	/** Tilt instances with the ground (grass, rocks) instead of staying upright (trees). */
	UPROPERTY(EditAnywhere, Category = "Scatter")
	bool bAlignToGround = true;

	/** Random roll/pitch in degrees (fallen debris, crashed cars). */
	UPROPERTY(EditAnywhere, Category = "Scatter")
	float RandomTilt = 0.f;

	/** Push into the ground (cm) so roots/bases never float. */
	UPROPERTY(EditAnywhere, Category = "Scatter")
	float Sink = 5.f;

	/** Visible distance in metres (also limits which chunks get the layer). */
	UPROPERTY(EditAnywhere, Category = "Scatter")
	float CullDistance = 120.f;

	UPROPERTY(EditAnywhere, Category = "Scatter|Rendering")
	bool bCastShadow = true;

	/** Disable for dense grass: distance fields and ray tracing BVH are costly. */
	UPROPERTY(EditAnywhere, Category = "Scatter|Rendering")
	bool bAffectLumen = true;

	UPROPERTY(EditAnywhere, Category = "Scatter|Rendering")
	bool bRayTraced = true;

	UPROPERTY(EditAnywhere, Category = "Scatter")
	bool bCollision = false;
};

/**
 * Project Settings > Game > Stillworld. Assign Fab / Megascans assets here:
 * the procedural generator only decides WHERE things go; realism comes from
 * these meshes and the terrain material textures.
 */
UCLASS(Config = Game, DefaultConfig, meta = (DisplayName = "Stillworld"))
class STILLWORLD_API UStillworldAssetSettings : public UDeveloperSettings
{
	GENERATED_BODY()

public:
	virtual FName GetCategoryName() const override { return TEXT("Game"); }

	UPROPERTY(Config, EditAnywhere, Category = "Meadow")
	TSoftObjectPtr<UMaterialInterface> MeadowTerrainMaterial;

	UPROPERTY(Config, EditAnywhere, Category = "Meadow")
	TArray<FStillworldScatterLayer> MeadowLayers;

	UPROPERTY(Config, EditAnywhere, Category = "Reclaimed City")
	TSoftObjectPtr<UMaterialInterface> ReclaimedTerrainMaterial;

	UPROPERTY(Config, EditAnywhere, Category = "Reclaimed City")
	TArray<FStillworldScatterLayer> ReclaimedLayers;
};
