#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "StillworldAssetSettings.h"
#include "StillworldGenerator.h"
#include "DynamicMesh/DynamicMesh3.h"
#include "Tasks/Task.h"
#include "StillworldWorld.generated.h"

class UDynamicMeshComponent;
class UInstancedStaticMeshComponent;
class UMaterialInterface;
class UStaticMesh;

/**
 * Streams an endless procedural world around the player.
 *
 * Chunks (64 m) are generated on worker threads from FStillworldGenerator:
 * a terrain mesh (UDynamicMeshComponent, LOD by distance, skirts against
 * cracks) plus instance transforms for every scatter layer. The game thread
 * only uploads finished chunks within a small per-frame time budget, so
 * streaming never stalls rendering. Collision exists only around the player.
 */
UCLASS()
class STILLWORLD_API AStillworldWorld : public AActor
{
	GENERATED_BODY()

public:
	AStillworldWorld();

	virtual void BeginPlay() override;
	virtual void EndPlay(const EEndPlayReason::Type Reason) override;
	virtual void Tick(float DeltaSeconds) override;

	static AStillworldWorld* Find(const UObject* WorldContext);

	const FStillworldGenerator& GetGenerator() const { return Generator; }
	bool HasSpawnedPlayer() const { return bPlayerPlaced; }
	int32 GetChunkCount() const { return Chunks.Num(); }
	int32 GetPendingCount() const { return Pending.Num(); }

	static constexpr float ChunkMeters = 64.f;

	/** Main-thread time budget for uploading finished chunks (ms). */
	UPROPERTY(EditAnywhere, Category = "Streaming")
	float UploadBudgetMs = 3.f;

private:
	struct FLayerRuntime
	{
		FStillworldScatterLayer Def;
		TArray<TObjectPtr<UStaticMesh>> Meshes;
		/** Box half extents in metres (x along road, y depth, z height). */
		TArray<FVector3f> Extents;
		bool bFallbackCubes = false;
	};

	/** Immutable inputs copied into each worker task. */
	struct FBuildParams
	{
		FStillworldGenerator Gen;
		TArray<FStillworldScatterLayer> Layers;
		TArray<TArray<FVector3f>> LayerExtents;
		TArray<bool> LayerFallback;
		float Density = 1.f;
		float DistanceScale = 1.f;
	};

	struct FChunkBuild
	{
		FIntPoint Coord;
		int32 Lod = 0;
		int32 Generation = 0;
		UE::Geometry::FDynamicMesh3 Mesh;
		/** Key = layer index * 256 + variant. */
		TMap<int32, TArray<FTransform>> Instances;
	};

	struct FChunk
	{
		int32 Lod = 0;
		int32 Generation = 0;
		TObjectPtr<UDynamicMeshComponent> Terrain;
		TArray<TObjectPtr<UInstancedStaticMeshComponent>> Instanced;
		bool bCollision = false;
	};

	struct FPending
	{
		FIntPoint Coord;
		int32 Lod = 0;
		int32 Generation = 0;
		UE::Tasks::TTask<TSharedPtr<FChunkBuild>> Task;
	};

	FStillworldGenerator Generator;
	TSharedPtr<const FBuildParams> Params;
	TArray<FLayerRuntime> Layers;

	UPROPERTY(Transient)
	TObjectPtr<UMaterialInterface> TerrainMaterial;

	/** Keeps runtime-created components and loaded meshes alive for GC. */
	UPROPERTY(Transient)
	TSet<TObjectPtr<UObject>> KeepAlive;

	TMap<FIntPoint, FChunk> Chunks;
	TArray<FPending> Pending;
	FIntPoint Center = FIntPoint(MAX_int32, 0);
	int32 ViewChunks = 6;
	int32 Generation = 0;
	int32 MaxTasks = 4;
	bool bPlayerPlaced = false;
	FVector2f SpawnPoint = FVector2f::ZeroVector;
	float SpawnYaw = 0.f;
	FDelegateHandle SettingsHandle;
	float LastDensity = -1.f;
	float LastDistance = -1.f;

	void LoadAssets();
	void RebuildParams();
	void OnSettingsChanged();
	int32 LodFor(int32 D) const;
	void Schedule();
	void Upload();
	void UpdateCollision();
	void PlacePlayer();
	void DestroyChunk(FChunk& Chunk);
	void ApplyChunk(FChunkBuild& Build);

	static TSharedPtr<FChunkBuild> BuildChunk(TSharedPtr<const FBuildParams> P, FIntPoint Coord, int32 Lod, int32 Gen);
	static void BuildTerrain(const FBuildParams& P, FChunkBuild& Out);
	static void BuildScatter(const FBuildParams& P, FChunkBuild& Out);
};
