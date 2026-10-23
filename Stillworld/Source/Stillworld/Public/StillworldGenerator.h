#pragma once

#include "CoreMinimal.h"

/** The two kinds of world. Each run generates a new random map of the kind. */
enum class EStillworldWorld : uint8
{
	Meadow,     // endless rolling grassland under rain and fog
	Reclaimed,  // abandoned town swallowed by vegetation (TLOU-inspired mood)
};

/**
 * Deterministic world functions: f(seed, x, y). Pure and immutable after
 * construction, so it is copied into worker threads freely. Every chunk
 * evaluates the same global functions, which is what makes chunk borders
 * seamless by construction.
 *
 * Units: METRES in world X/Y (UE forward/right), height in metres.
 */
class STILLWORLD_API FStillworldGenerator
{
public:
	/** Half extents (m) of each building variant in its local X (along road) and Y (depth). */
	TArray<FVector2f> BuildingExtents;
	float BuildingLotProbability = 0.7f;

	FStillworldGenerator() = default;
	FStillworldGenerator(int32 InSeed, EStillworldWorld InWorld);

	int32 GetSeed() const { return Seed; }
	EStillworldWorld GetWorld() const { return World; }

	float Height(float X, float Y) const;
	/** Unit normal from central differences of Height(). */
	FVector3f Normal(float X, float Y, float Eps = 1.f) const;
	/** Surface weights: R grass, G dirt/mud, B asphalt/concrete, A moss/overgrowth. */
	FVector4f Surface(float X, float Y) const;

	/** 0..1 worn dirt track (meadow paths, forest trails outside towns). */
	float Track(float X, float Y) const;

	/** 0..1 town presence (Reclaimed only). */
	float Town(float X, float Y) const;
	/** 0..1 asphalt amount (roads + sidewalks), Reclaimed only. */
	float Road(float X, float Y) const;
	/** Direction of the closest road (unit, world XY), for aligning cars. */
	FVector2f RoadDirection(float X, float Y) const;

	/** Building in the lot containing (X, Y), if any. */
	struct FLot
	{
		FVector2f Center;     // world metres
		float YawDeg = 0.f;   // mesh X axis along the road
		int32 Variant = 0;
		uint32 Hash = 0;
	};
	bool LotAt(float X, float Y, FLot& Out) const;
	/** True if (X, Y) lies inside a building footprint (+ margin). */
	bool InsideBuilding(float X, float Y, float Margin = 1.5f) const;

	/** Enumerates all lots whose centre lies in the axis-aligned rect. */
	void LotsInRect(const FVector2f& Min, const FVector2f& Max, TArray<FLot>& Out) const;

	/** Clustered noise in 0..1 (used for vegetation clumping). */
	float Patch(float X, float Y, float Scale, int32 Layer) const;

	/** A good spawn point (world metres) and view yaw (degrees). */
	FVector2f FindSpawn(float& OutYaw) const;

	static uint32 Hash3(int32 A, int32 B, int32 C);

private:
	int32 Seed = 1;
	EStillworldWorld World = EStillworldWorld::Meadow;
	FVector2f Offsets[16];
	float RoadAngle = 0.f;
	FVector2f RoadAxisU = FVector2f(1, 0);
	FVector2f RoadAxisV = FVector2f(0, 1);

	static constexpr float BlockU = 120.f;   // block length along U (m)
	static constexpr float BlockV = 92.f;    // block depth along V (m)
	static constexpr float LotWidth = 30.f;  // 4 lots per block row
	static constexpr float RoadHalf = 4.6f;  // carriageway half width
	static constexpr float WalkHalf = 7.0f;  // + sidewalk

	float Fbm(FVector2f P, int32 Octaves, int32 Layer) const;
	float Ridged(FVector2f P, int32 Octaves, int32 Layer) const;
	/** World XY (m) -> warped, rotated road-grid space. */
	FVector2f ToGrid(FVector2f P) const;
	/** Inverse of ToGrid by fixed-point iteration (warp is small and smooth). */
	FVector2f FromGrid(FVector2f Q) const;
	bool LotByIndex(int32 I, int32 J, FLot& Out, FVector2f* OutGridCenter = nullptr, FVector2f* OutHalf = nullptr) const;
	float MeadowHeight(FVector2f P) const;
	float ReclaimedHeight(FVector2f P) const;
};
