#include "StillworldWorld.h"

#include "Async/TaskGraphInterfaces.h"
#include "Camera/PlayerCameraManager.h"
#include "Components/DynamicMeshComponent.h"
#include "Components/InstancedStaticMeshComponent.h"
#include "DynamicMesh/DynamicMeshAttributeSet.h"
#include "Engine/CollisionProfile.h"
#include "Engine/StaticMesh.h"
#include "EngineUtils.h"
#include "GameFramework/Character.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "Kismet/GameplayStatics.h"
#include "Materials/MaterialInterface.h"
#include "Math/RandomStream.h"
#include "StillworldGameMode.h"
#include "StillworldSettings.h"
#include "StillworldWeather.h"

using UE::Geometry::FDynamicMesh3;
using UE::Geometry::FIndex3i;

namespace
{
	constexpr float M = 100.f; // metres -> centimetres

	int32 Cheb(const FIntPoint& A, const FIntPoint& B)
	{
		return FMath::Max(FMath::Abs(A.X - B.X), FMath::Abs(A.Y - B.Y));
	}

	float Smooth(float E0, float E1, float X)
	{
		const float T = FMath::Clamp((X - E0) / (E1 - E0), 0.f, 1.f);
		return T * T * (3.f - 2.f * T);
	}

	/** Whether FDynamicMesh3 considers (0,0,0),(1,0,0),(0,1,0) as facing +Z.
	 *  Decides the winding of terrain triangles so that they face upward
	 *  whatever the library convention is. */
	bool UpwardWindingIsXY()
	{
		static const bool bValue = []()
		{
			FDynamicMesh3 Test;
			const int32 A = Test.AppendVertex(FVector3d(0, 0, 0));
			const int32 B = Test.AppendVertex(FVector3d(1, 0, 0));
			const int32 C = Test.AppendVertex(FVector3d(0, 1, 0));
			const int32 T = Test.AppendTriangle(A, B, C);
			return Test.GetTriNormal(T).Z > 0.0;
		}();
		return bValue;
	}
}

AStillworldWorld::AStillworldWorld()
{
	PrimaryActorTick.bCanEverTick = true;
	PrimaryActorTick.TickGroup = TG_PrePhysics;
	USceneComponent* Root = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));
	Root->SetMobility(EComponentMobility::Static);
	RootComponent = Root;
}

AStillworldWorld* AStillworldWorld::Find(const UObject* WorldContext)
{
	UWorld* W = WorldContext ? WorldContext->GetWorld() : nullptr;
	if (!W)
	{
		return nullptr;
	}
	for (TActorIterator<AStillworldWorld> It(W); It; ++It)
	{
		return *It;
	}
	return nullptr;
}

void AStillworldWorld::BeginPlay()
{
	Super::BeginPlay();

	// World kind and seed come from the level URL (?World=Reclaimed?Seed=42)
	// via the game mode; a new random seed is drawn for every new map.
	EStillworldWorld Kind = EStillworldWorld::Meadow;
	int32 Seed = FMath::Rand();
	if (const AStillworldGameMode* GM = GetWorld()->GetAuthGameMode<AStillworldGameMode>())
	{
		Kind = GM->WorldKind;
		Seed = GM->WorldSeed;
	}
	Generator = FStillworldGenerator(Seed, Kind);
	MaxTasks = FMath::Clamp(FTaskGraphInterface::Get().GetNumWorkerThreads() - 1, 2, 10);

	LoadAssets();
	RebuildParams();
	SpawnPoint = Generator.FindSpawn(SpawnYaw);
	UE_LOG(LogTemp, Display, TEXT("[Stillworld] World %s, seed %d, spawn (%.0f, %.0f)"),
		Kind == EStillworldWorld::Meadow ? TEXT("Meadow") : TEXT("Reclaimed"), Seed, SpawnPoint.X, SpawnPoint.Y);

	// Per-world weather mood: the meadow is the rain-and-fog reference look;
	// the reclaimed town is damp and hazy, with lighter drizzle.
	for (TActorIterator<AStillworldWeather> It(GetWorld()); It; ++It)
	{
		It->Rain = Kind == EStillworldWorld::Meadow ? 0.55f : 0.3f;
		It->FogScale = Kind == EStillworldWorld::Meadow ? 1.f : 0.65f;
	}

	OnSettingsChanged();
	SettingsHandle = FStillworldSettings::OnChanged.AddUObject(this, &AStillworldWorld::OnSettingsChanged);

	if (APlayerController* PC = UGameplayStatics::GetPlayerController(this, 0))
	{
		if (PC->PlayerCameraManager)
		{
			PC->PlayerCameraManager->SetManualCameraFade(1.f, FLinearColor::Black, false);
		}
	}
}

void AStillworldWorld::EndPlay(const EEndPlayReason::Type Reason)
{
	FStillworldSettings::OnChanged.Remove(SettingsHandle);
	// Worker tasks only hold copies of immutable data; just wait so they do
	// not outlive the module on shutdown.
	for (FPending& P : Pending)
	{
		P.Task.Wait();
	}
	Pending.Reset();
	Super::EndPlay(Reason);
}

void AStillworldWorld::LoadAssets()
{
	const UStillworldAssetSettings* S = GetDefault<UStillworldAssetSettings>();
	const bool bMeadow = Generator.GetWorld() == EStillworldWorld::Meadow;
	const TArray<FStillworldScatterLayer>& Defs = bMeadow ? S->MeadowLayers : S->ReclaimedLayers;
	TerrainMaterial = (bMeadow ? S->MeadowTerrainMaterial : S->ReclaimedTerrainMaterial).LoadSynchronous();
	if (!TerrainMaterial)
	{
		TerrainMaterial = LoadObject<UMaterialInterface>(nullptr, TEXT("/Game/Stillworld/Materials/MI_Terrain_Meadow.MI_Terrain_Meadow"), nullptr, LOAD_NoWarn | LOAD_Quiet);
	}

	Layers.Reset();
	bool bHasLots = false;
	for (const FStillworldScatterLayer& Def : Defs)
	{
		FLayerRuntime L;
		L.Def = Def;
		for (const TSoftObjectPtr<UStaticMesh>& Soft : Def.Meshes)
		{
			if (UStaticMesh* Mesh = Soft.LoadSynchronous())
			{
				L.Meshes.Add(Mesh);
				KeepAlive.Add(Mesh);
				const FVector Ext = Mesh->GetBounds().BoxExtent / M;
				L.Extents.Add(FVector3f(Ext));
			}
		}
		if (L.Meshes.Num() > 0)
		{
			bHasLots |= Def.Placement == EStillworldPlacement::Lot;
			Layers.Add(MoveTemp(L));
		}
	}

	// Without any configured building, the town still gets its structure:
	// plain concrete blocks, so streets and lots are readable while assets
	// are being chosen (see docs/ASSETS.md).
	if (!bMeadow && !bHasLots)
	{
		if (UStaticMesh* Cube = LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Cube.Cube")))
		{
			FLayerRuntime L;
			L.Def.Name = TEXT("FallbackBuildings");
			L.Def.Placement = EStillworldPlacement::Lot;
			L.Def.LotProbability = 0.75f;
			L.Def.CullDistance = 2000.f;
			L.Def.bAlignToGround = false;
			L.Def.bCollision = true;
			L.Def.Sink = 50.f;
			L.Meshes.Add(Cube);
			L.Extents.Add(FVector3f(6.f, 4.5f, 5.f));
			L.bFallbackCubes = true;
			KeepAlive.Add(Cube);
			Layers.Add(MoveTemp(L));
		}
	}
	if (Layers.Num() == 0 && GEngine)
	{
		GEngine->AddOnScreenDebugMessage(-1, 12.f, FColor(200, 200, 200),
			TEXT("Stillworld: no scatter assets configured (Project Settings > Game > Stillworld). See docs/ASSETS.md."));
	}

	// The generator needs building footprints to lay out lots (first Lot layer).
	Generator.BuildingExtents.Reset();
	for (const FLayerRuntime& L : Layers)
	{
		if (L.Def.Placement == EStillworldPlacement::Lot)
		{
			for (const FVector3f& E : L.Extents)
			{
				Generator.BuildingExtents.Add(FVector2f(E.X, E.Y));
			}
			Generator.BuildingLotProbability = L.Def.LotProbability;
			break;
		}
	}
}

void AStillworldWorld::RebuildParams()
{
	const FStillworldSettings& S = FStillworldSettings::Get();
	TSharedPtr<FBuildParams> P = MakeShared<FBuildParams>();
	P->Gen = Generator;
	P->Density = S.FoliageDensity;
	P->DistanceScale = S.FoliageDistance;
	for (const FLayerRuntime& L : Layers)
	{
		P->Layers.Add(L.Def);
		P->LayerExtents.Add(L.Extents);
		P->LayerFallback.Add(L.bFallbackCubes);
	}
	Params = P;
	LastDensity = S.FoliageDensity;
	LastDistance = S.FoliageDistance;
}

void AStillworldWorld::OnSettingsChanged()
{
	const FStillworldSettings& S = FStillworldSettings::Get();
	static const int32 ViewByQuality[5] = { 4, 5, 7, 9, 12 };
	const int32 NewView = ViewByQuality[FMath::Clamp(S.ViewDistance, 0, 4)];
	if (S.FoliageDensity != LastDensity || S.FoliageDistance != LastDistance)
	{
		// Rebuild every chunk progressively; old ones stay until replaced.
		RebuildParams();
		++Generation;
	}
	ViewChunks = NewView;
	Center = FIntPoint(MAX_int32, 0);
}

int32 AStillworldWorld::LodFor(int32 D) const
{
	if (D <= 1) { return 0; }  // 1 m grid
	if (D == 2) { return 1; }  // 2 m
	if (D <= 4) { return 2; }  // 4 m
	return 3;                  // 8 m
}

void AStillworldWorld::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);
	FVector Focus(SpawnPoint.X * M, SpawnPoint.Y * M, 0.0);
	if (bPlayerPlaced)
	{
		if (APlayerCameraManager* Cam = UGameplayStatics::GetPlayerCameraManager(this, 0))
		{
			Focus = Cam->GetCameraLocation();
		}
	}
	const FIntPoint C(FMath::FloorToInt(Focus.X / (ChunkMeters * M)), FMath::FloorToInt(Focus.Y / (ChunkMeters * M)));
	if (C != Center)
	{
		Center = C;
		// Unload outside the hysteresis band.
		TArray<FIntPoint> Remove;
		for (TPair<FIntPoint, FChunk>& Pair : Chunks)
		{
			if (Cheb(Pair.Key, Center) > ViewChunks + 1)
			{
				DestroyChunk(Pair.Value);
				Remove.Add(Pair.Key);
			}
		}
		for (const FIntPoint& K : Remove)
		{
			Chunks.Remove(K);
		}
	}
	Upload();
	Schedule();
	UpdateCollision();
	if (!bPlayerPlaced)
	{
		PlacePlayer();
	}
}

void AStillworldWorld::Schedule()
{
	if (Pending.Num() >= MaxTasks || !Params.IsValid())
	{
		return;
	}
	struct FWant { int32 Dist2; FIntPoint Coord; int32 Lod; };
	TArray<FWant> Want;
	for (int32 DY = -ViewChunks; DY <= ViewChunks; ++DY)
	{
		for (int32 DX = -ViewChunks; DX <= ViewChunks; ++DX)
		{
			const FIntPoint K = Center + FIntPoint(DX, DY);
			const int32 Lod = LodFor(FMath::Max(FMath::Abs(DX), FMath::Abs(DY)));
			const FChunk* Existing = Chunks.Find(K);
			if (Existing && Existing->Lod == Lod && Existing->Generation == Generation)
			{
				continue;
			}
			if (Pending.ContainsByPredicate([&K](const FPending& P) { return P.Coord == K; }))
			{
				continue; // a stale result is discarded on arrival, then rescheduled
			}
			Want.Add({ DX * DX + DY * DY, K, Lod });
		}
	}
	Want.Sort([](const FWant& A, const FWant& B) { return A.Dist2 < B.Dist2; });
	for (const FWant& W : Want)
	{
		if (Pending.Num() >= MaxTasks)
		{
			break;
		}
		FPending P;
		P.Coord = W.Coord;
		P.Lod = W.Lod;
		P.Generation = Generation;
		TSharedPtr<const FBuildParams> Captured = Params;
		const FIntPoint Coord = W.Coord;
		const int32 Lod = W.Lod;
		const int32 Gen = Generation;
		P.Task = UE::Tasks::Launch(UE_SOURCE_LOCATION, [Captured, Coord, Lod, Gen]()
		{
			return BuildChunk(Captured, Coord, Lod, Gen);
		});
		Pending.Add(MoveTemp(P));
	}
}

void AStillworldWorld::Upload()
{
	const double Start = FPlatformTime::Seconds();
	for (int32 I = 0; I < Pending.Num();)
	{
		if (!Pending[I].Task.IsCompleted())
		{
			++I;
			continue;
		}
		TSharedPtr<FChunkBuild> Build = Pending[I].Task.GetResult();
		Pending.RemoveAtSwap(I);
		const int32 Wanted = LodFor(Cheb(Build->Coord, Center));
		if (Cheb(Build->Coord, Center) > ViewChunks + 1 || Build->Lod != Wanted || Build->Generation != Generation)
		{
			continue; // stale: the player moved or settings changed
		}
		ApplyChunk(*Build);
		if ((FPlatformTime::Seconds() - Start) * 1000.0 > UploadBudgetMs)
		{
			break;
		}
	}
}

void AStillworldWorld::DestroyChunk(FChunk& Chunk)
{
	if (Chunk.Terrain)
	{
		KeepAlive.Remove(Chunk.Terrain);
		Chunk.Terrain->DestroyComponent();
	}
	for (UInstancedStaticMeshComponent* ISM : Chunk.Instanced)
	{
		if (ISM)
		{
			KeepAlive.Remove(ISM);
			ISM->DestroyComponent();
		}
	}
	Chunk.Instanced.Reset();
	Chunk.Terrain = nullptr;
}

void AStillworldWorld::ApplyChunk(FChunkBuild& Build)
{
	FChunk New;
	New.Lod = Build.Lod;
	New.Generation = Build.Generation;

	UDynamicMeshComponent* Terrain = NewObject<UDynamicMeshComponent>(this);
	Terrain->SetMobility(EComponentMobility::Static);
	Terrain->SetupAttachment(RootComponent);
	Terrain->SetWorldLocation(FVector(Build.Coord.X * ChunkMeters * M, Build.Coord.Y * ChunkMeters * M, 0.0));
	Terrain->SetMesh(MoveTemp(Build.Mesh));
	Terrain->SetTangentsType(EDynamicMeshComponentTangentsMode::AutoCalculated);
	if (TerrainMaterial)
	{
		Terrain->SetMaterial(0, TerrainMaterial);
	}
	Terrain->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	Terrain->SetCastShadow(Build.Lod <= 2);
	Terrain->RegisterComponent();
	KeepAlive.Add(Terrain);
	New.Terrain = Terrain;

	for (TPair<int32, TArray<FTransform>>& Pair : Build.Instances)
	{
		const int32 LayerIdx = Pair.Key / 256;
		const int32 Variant = Pair.Key % 256;
		if (!Layers.IsValidIndex(LayerIdx) || !Layers[LayerIdx].Meshes.IsValidIndex(Variant) || Pair.Value.Num() == 0)
		{
			continue;
		}
		const FStillworldScatterLayer& Def = Layers[LayerIdx].Def;
		UInstancedStaticMeshComponent* ISM = NewObject<UInstancedStaticMeshComponent>(this);
		ISM->SetMobility(EComponentMobility::Static);
		ISM->SetupAttachment(RootComponent);
		ISM->SetStaticMesh(Layers[LayerIdx].Meshes[Variant]);
		const float Cull = Def.CullDistance * FStillworldSettings::Get().FoliageDistance * M;
		ISM->SetCullDistances(static_cast<int32>(Cull * 0.8f), static_cast<int32>(Cull));
		ISM->SetCastShadow(Def.bCastShadow);
		ISM->bAffectDistanceFieldLighting = Def.bAffectLumen;
		ISM->bAffectDynamicIndirectLighting = Def.bAffectLumen;
		ISM->SetVisibleInRayTracing(Def.bRayTraced);
		// Wind animation (WPO) is pointless where it cannot be seen.
		ISM->WorldPositionOffsetDisableDistance = static_cast<int32>(Cull * 0.6f);
		if (Def.bCollision)
		{
			ISM->SetCollisionProfileName(UCollisionProfile::BlockAll_ProfileName);
		}
		else
		{
			ISM->SetCollisionEnabled(ECollisionEnabled::NoCollision);
		}
		ISM->RegisterComponent();
		ISM->AddInstances(Pair.Value, false, true);
		KeepAlive.Add(ISM);
		New.Instanced.Add(ISM);
	}

	// Replace the previous version only once the new one exists: no holes.
	if (FChunk* Old = Chunks.Find(Build.Coord))
	{
		DestroyChunk(*Old);
	}
	Chunks.Add(Build.Coord, New);
}

void AStillworldWorld::UpdateCollision()
{
	for (TPair<FIntPoint, FChunk>& Pair : Chunks)
	{
		FChunk& Ch = Pair.Value;
		const bool bWant = Cheb(Pair.Key, Center) <= 1;
		if (bWant != Ch.bCollision && Ch.Terrain)
		{
			Ch.bCollision = bWant;
			if (bWant)
			{
				Ch.Terrain->SetCollisionProfileName(UCollisionProfile::BlockAll_ProfileName);
				Ch.Terrain->SetComplexAsSimpleCollisionEnabled(true, true);
			}
			else
			{
				Ch.Terrain->SetCollisionEnabled(ECollisionEnabled::NoCollision);
			}
		}
	}
}

void AStillworldWorld::PlacePlayer()
{
	APlayerController* PC = UGameplayStatics::GetPlayerController(this, 0);
	ACharacter* Pawn = PC ? Cast<ACharacter>(PC->GetPawn()) : nullptr;
	if (!Pawn)
	{
		return;
	}
	const float GroundZ = Generator.Height(SpawnPoint.X, SpawnPoint.Y) * M;
	const FVector Spawn(SpawnPoint.X * M, SpawnPoint.Y * M, GroundZ + 100.f);
	const FIntPoint C(FMath::FloorToInt(SpawnPoint.X / ChunkMeters), FMath::FloorToInt(SpawnPoint.Y / ChunkMeters));
	const FChunk* Ch = Chunks.Find(C);
	if (!Ch || !Ch->bCollision)
	{
		// Hold the walker in place (no gravity) until the ground is solid.
		Pawn->GetCharacterMovement()->SetMovementMode(MOVE_None);
		Pawn->SetActorLocation(Spawn);
		return;
	}
	Pawn->SetActorLocation(Spawn, false, nullptr, ETeleportType::TeleportPhysics);
	PC->SetControlRotation(FRotator(-2.f, SpawnYaw, 0.f));
	Pawn->GetCharacterMovement()->SetMovementMode(MOVE_Walking);
	bPlayerPlaced = true;
	if (PC->PlayerCameraManager)
	{
		PC->PlayerCameraManager->StartCameraFade(1.f, 0.f, 3.f, FLinearColor::Black, false, false);
	}
}

// ---------------------------------------------------------------------------
// Worker-thread generation

TSharedPtr<AStillworldWorld::FChunkBuild> AStillworldWorld::BuildChunk(TSharedPtr<const FBuildParams> P, FIntPoint Coord, int32 Lod, int32 Gen)
{
	TSharedPtr<FChunkBuild> Out = MakeShared<FChunkBuild>();
	Out->Coord = Coord;
	Out->Lod = Lod;
	Out->Generation = Gen;
	BuildTerrain(*P, *Out);
	BuildScatter(*P, *Out);
	return Out;
}

void AStillworldWorld::BuildTerrain(const FBuildParams& P, FChunkBuild& Out)
{
	static const int32 CellsByLod[4] = { 64, 32, 16, 8 };
	const int32 Cells = CellsByLod[FMath::Clamp(Out.Lod, 0, 3)];
	const float Spacing = ChunkMeters / Cells;
	const float OX = Out.Coord.X * ChunkMeters;
	const float OY = Out.Coord.Y * ChunkMeters;
	const int32 Side = Cells + 1;
	const int32 N = Cells + 3; // one-cell border for seamless normals

	// Heights on a bordered grid.
	TArray<float> H;
	H.SetNumUninitialized(N * N);
	for (int32 IY = 0; IY < N; ++IY)
	{
		for (int32 IX = 0; IX < N; ++IX)
		{
			H[IY * N + IX] = P.Gen.Height(OX + (IX - 1) * Spacing, OY + (IY - 1) * Spacing);
		}
	}

	FDynamicMesh3& Mesh = Out.Mesh;
	Mesh.EnableAttributes();
	Mesh.Attributes()->EnablePrimaryColors();
	UE::Geometry::FDynamicMeshNormalOverlay* Normals = Mesh.Attributes()->PrimaryNormals();
	UE::Geometry::FDynamicMeshUVOverlay* UVs = Mesh.Attributes()->PrimaryUV();
	UE::Geometry::FDynamicMeshColorOverlay* Colors = Mesh.Attributes()->PrimaryColors();

	auto AddVertex = [&](float LX, float LY, float Z, const FVector3f& Nrm, const FVector4f& Col)
	{
		const int32 V = Mesh.AppendVertex(FVector3d(LX * M, LY * M, Z * M));
		Normals->AppendElement(Nrm);
		// UV0 = world position in metres (the material does its own tiling).
		UVs->AppendElement(FVector2f(OX + LX, OY + LY));
		Colors->AppendElement(Col);
		return V; // element ids == vertex ids (one element per vertex)
	};
	auto AddTri = [&](int32 A, int32 B, int32 C)
	{
		const int32 T = UpwardWindingIsXY() ? Mesh.AppendTriangle(A, B, C) : Mesh.AppendTriangle(A, C, B);
		if (T >= 0)
		{
			const FIndex3i Tri = Mesh.GetTriangle(T);
			Normals->SetTriangle(T, Tri);
			UVs->SetTriangle(T, Tri);
			Colors->SetTriangle(T, Tri);
		}
	};

	TArray<int32> Grid;
	Grid.SetNumUninitialized(Side * Side);
	for (int32 IY = 0; IY < Side; ++IY)
	{
		for (int32 IX = 0; IX < Side; ++IX)
		{
			const int32 G = (IY + 1) * N + (IX + 1);
			const float DX = H[G + 1] - H[G - 1];
			const float DY = H[G + N] - H[G - N];
			const FVector3f Nrm = FVector3f(-DX, -DY, 2.f * Spacing).GetSafeNormal();
			const float LX = IX * Spacing;
			const float LY = IY * Spacing;
			Grid[IY * Side + IX] = AddVertex(LX, LY, H[G], Nrm, P.Gen.Surface(OX + LX, OY + LY));
		}
	}
	for (int32 IY = 0; IY < Cells; ++IY)
	{
		for (int32 IX = 0; IX < Cells; ++IX)
		{
			const int32 A = Grid[IY * Side + IX];
			const int32 B = Grid[IY * Side + IX + 1];
			const int32 C = Grid[(IY + 1) * Side + IX + 1];
			const int32 D = Grid[(IY + 1) * Side + IX];
			AddTri(A, B, C);
			AddTri(A, C, D);
		}
	}
	// Skirts hide T-junction cracks between neighbours of different LOD.
	// Edges are walked counter-clockwise seen from above; with right-handed
	// winding (normalised by AddTri) this order makes each strip face outward.
	const float Skirt = Spacing * 1.5f + 1.f;
	auto EdgeStrip = [&](int32 X0, int32 Y0, int32 DX, int32 DY)
	{
		int32 PrevTop = -1, PrevBot = -1;
		for (int32 I = 0; I < Side; ++I)
		{
			const int32 IX = X0 + DX * I;
			const int32 IY = Y0 + DY * I;
			const int32 Top = Grid[IY * Side + IX];
			const FVector3d TP = Mesh.GetVertex(Top);
			const int32 Bot = AddVertex(IX * Spacing, IY * Spacing, static_cast<float>(TP.Z / M) - Skirt,
				Normals->GetElement(Top), Colors->GetElement(Top));
			if (PrevTop >= 0)
			{
				AddTri(PrevTop, Bot, Top);
				AddTri(PrevTop, PrevBot, Bot);
			}
			PrevTop = Top;
			PrevBot = Bot;
		}
	};
	EdgeStrip(0, 0, 1, 0);
	EdgeStrip(Cells, 0, 0, 1);
	EdgeStrip(Cells, Cells, -1, 0);
	EdgeStrip(0, Cells, 0, -1);
}

void AStillworldWorld::BuildScatter(const FBuildParams& P, FChunkBuild& Out)
{
	const FStillworldGenerator& Gen = P.Gen;
	const float OX = Out.Coord.X * ChunkMeters;
	const float OY = Out.Coord.Y * ChunkMeters;
	const float Area = ChunkMeters * ChunkMeters;
	// Distance (m) from the player's chunk to the nearest edge of this one is
	// at least (ring - 1) * size: only layers visible that far are generated.
	const int32 Ring = Out.Lod == 0 ? 1 : (Out.Lod == 1 ? 2 : (Out.Lod == 2 ? 4 : 99));
	const float MinDist = FMath::Max(0, Ring - 1) * ChunkMeters;

	for (int32 LI = 0; LI < P.Layers.Num(); ++LI)
	{
		const FStillworldScatterLayer& L = P.Layers[LI];
		const TArray<FVector3f>& Ext = P.LayerExtents[LI];
		if (Ext.Num() == 0 || L.CullDistance * P.DistanceScale < MinDist)
		{
			continue;
		}
		FRandomStream Rng(static_cast<int32>(FStillworldGenerator::Hash3(Gen.GetSeed() + LI * 7919, Out.Coord.X, Out.Coord.Y)));
		const float CosMax = FMath::Cos(FMath::DegreesToRadians(L.MaxSlope));

		auto Emit = [&](int32 Variant, const FVector2f& Pos, float YawDeg, float Scale, const FVector3f& Nrm)
		{
			const float Z = Gen.Height(Pos.X, Pos.Y);
			FQuat Q = FQuat(FVector::UpVector, FMath::DegreesToRadians(YawDeg));
			if (L.bAlignToGround)
			{
				Q = FQuat::FindBetweenNormals(FVector::UpVector, FVector(Nrm)) * Q;
			}
			if (L.RandomTilt > 0.f)
			{
				const FRotator Tilt(Rng.FRandRange(-L.RandomTilt, L.RandomTilt), 0.f, Rng.FRandRange(-L.RandomTilt, L.RandomTilt));
				Q = Q * Tilt.Quaternion();
			}
			FVector S(Scale);
			if (P.LayerFallback[LI])
			{
				// Fallback concrete blocks: 1 m cube scaled to a building.
				const FVector3f E = Ext[Variant];
				S = FVector(E.X * 2.f, E.Y * 2.f, Rng.FRandRange(6.f, 16.f));
			}
			const float Base = P.LayerFallback[LI] ? S.Z * 0.5f * M : 0.f;
			const FVector Loc(Pos.X * M, Pos.Y * M, Z * M - L.Sink + Base);
			Out.Instances.FindOrAdd(LI * 256 + Variant).Add(FTransform(Q, Loc, S));
		};

		if (L.Placement == EStillworldPlacement::Lot)
		{
			TArray<FStillworldGenerator::FLot> Lots;
			Gen.LotsInRect(FVector2f(OX, OY), FVector2f(OX + ChunkMeters, OY + ChunkMeters), Lots);
			for (const FStillworldGenerator::FLot& Lot : Lots)
			{
				Emit(FMath::Min(Lot.Variant, Ext.Num() - 1), Lot.Center, Lot.YawDeg, 1.f, FVector3f::UpVector);
			}
			continue;
		}

		const int32 Count = FMath::RoundToInt(L.Density * Area / 100.f * P.Density);
		for (int32 I = 0; I < Count; ++I)
		{
			const FVector2f Pos(OX + Rng.FRand() * ChunkMeters, OY + Rng.FRand() * ChunkMeters);
			const float Keep = Rng.FRand();
			float Prob = 1.f;
			if (L.Clumping > 0.f)
			{
				Prob *= FMath::Lerp(1.f, Smooth(0.35f, 0.7f, Gen.Patch(Pos.X, Pos.Y, L.ClumpSize, LI)), L.Clumping);
			}
			const float RoadW = Gen.Road(Pos.X, Pos.Y);
			switch (L.Placement)
			{
			case EStillworldPlacement::Natural:
				Prob *= 1.f - RoadW;
				break;
			case EStillworldPlacement::Road:
				Prob *= RoadW;
				break;
			case EStillworldPlacement::NearBuildings:
				Prob *= Gen.Town(Pos.X, Pos.Y) * (Gen.InsideBuilding(Pos.X, Pos.Y, 6.f) ? 1.f : 0.15f);
				break;
			default:
				break;
			}
			if (L.SurfaceMask != EStillworldSurfaceMask::None && Prob > 0.f)
			{
				const FVector4f Sf = Gen.Surface(Pos.X, Pos.Y);
				const float W = L.SurfaceMask == EStillworldSurfaceMask::Grass ? Sf.X
					: L.SurfaceMask == EStillworldSurfaceMask::Dirt ? Sf.Y
					: L.SurfaceMask == EStillworldSurfaceMask::Asphalt ? Sf.Z : Sf.W;
				Prob *= W;
			}
			if (Keep > Prob)
			{
				continue;
			}
			if (Gen.InsideBuilding(Pos.X, Pos.Y, 0.5f))
			{
				continue;
			}
			const FVector3f Nrm = Gen.Normal(Pos.X, Pos.Y, 0.75f);
			if (Nrm.Z < CosMax)
			{
				continue;
			}
			float Yaw = Rng.FRand() * 360.f;
			if (L.Placement == EStillworldPlacement::Road)
			{
				// Abandoned cars mostly follow the lane, some slewed across it.
				const FVector2f D = Gen.RoadDirection(Pos.X, Pos.Y);
				Yaw = FMath::RadiansToDegrees(FMath::Atan2(D.Y, D.X)) + (Rng.FRand() < 0.5f ? 0.f : 180.f)
					+ Rng.FRandRange(-12.f, 12.f) + (Rng.FRand() < 0.2f ? Rng.FRandRange(-60.f, 60.f) : 0.f);
			}
			const float Scale = Rng.FRandRange(L.ScaleRange.X, L.ScaleRange.Y);
			Emit(Rng.RandHelper(Ext.Num()), Pos, Yaw, Scale, Nrm);
		}
	}
}
