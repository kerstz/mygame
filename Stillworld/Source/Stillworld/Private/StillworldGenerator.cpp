#include "StillworldGenerator.h"

#include "Math/RandomStream.h"
#include "StillworldMath.h"

namespace
{
	using StillworldMath::SmoothStep;

	float Perlin(const FVector2f& P)
	{
		return FMath::PerlinNoise2D(FVector2D(P.X, P.Y));
	}

	// Rotation between octaves breaks the grid alignment of Perlin noise.
	const FVector2f OctRotA(0.8f, 0.6f);
}

uint32 FStillworldGenerator::Hash3(int32 A, int32 B, int32 C)
{
	uint32 H = 2166136261u;
	for (uint32 V : { static_cast<uint32>(A), static_cast<uint32>(B), static_cast<uint32>(C) })
	{
		H ^= V;
		H *= 16777619u;
		H ^= H >> 13;
		H *= 0x5bd1e995u;
		H ^= H >> 15;
	}
	return H;
}

FStillworldGenerator::FStillworldGenerator(int32 InSeed, EStillworldWorld InWorld)
	: Seed(InSeed), World(InWorld)
{
	// The engine's Perlin noise is unseeded; a seed becomes a set of large
	// per-layer offsets into the noise field (well within float precision for
	// the frequencies used here).
	FRandomStream R(InSeed);
	for (FVector2f& O : Offsets)
	{
		O = FVector2f(R.FRandRange(-4000.f, 4000.f), R.FRandRange(-4000.f, 4000.f));
	}
	RoadAngle = R.FRandRange(0.f, UE_PI);
	RoadAxisU = FVector2f(FMath::Cos(RoadAngle), FMath::Sin(RoadAngle));
	RoadAxisV = FVector2f(-RoadAxisU.Y, RoadAxisU.X);
}

float FStillworldGenerator::Fbm(FVector2f P, int32 Octaves, int32 Layer) const
{
	P += Offsets[Layer & 15];
	float Sum = 0.f, Amp = 0.5f, Norm = 0.f;
	for (int32 I = 0; I < Octaves; ++I)
	{
		Sum += Perlin(P) * Amp;
		Norm += Amp;
		P = FVector2f(P.X * OctRotA.X - P.Y * OctRotA.Y, P.X * OctRotA.Y + P.Y * OctRotA.X) * 2.03f + FVector2f(17.1f, -9.3f);
		Amp *= 0.5f;
	}
	return Sum / Norm;
}

float FStillworldGenerator::Ridged(FVector2f P, int32 Octaves, int32 Layer) const
{
	P += Offsets[Layer & 15];
	float Sum = 0.f, Amp = 0.5f, Norm = 0.f;
	for (int32 I = 0; I < Octaves; ++I)
	{
		const float N = 1.f - FMath::Abs(Perlin(P));
		Sum += N * N * Amp;
		Norm += Amp;
		P = FVector2f(P.X * OctRotA.X - P.Y * OctRotA.Y, P.X * OctRotA.Y + P.Y * OctRotA.X) * 2.03f;
		Amp *= 0.5f;
	}
	return Sum / Norm;
}

float FStillworldGenerator::Patch(float X, float Y, float Scale, int32 Layer) const
{
	return FMath::Clamp(Fbm(FVector2f(X, Y) / FMath::Max(Scale, 1.f), 2, 8 + (Layer & 7)) * 1.4f + 0.5f, 0.f, 1.f);
}

// ---------------------------------------------------------------------------
// Heights

// Wandering footpaths: thin bands where a low-frequency noise crosses zero.
// Two independent fields give occasional crossings and forks.
float FStillworldGenerator::Track(float X, float Y) const
{
	const FVector2f P(X, Y);
	const float A = FMath::Abs(Fbm(P / 420.f, 2, 12));
	const float B = FMath::Abs(Fbm(P / 610.f, 2, 13));
	const float Edge = 0.012f + Fbm(P / 6.f, 2, 14) * 0.006f;   // ragged edges
	float T = FMath::Max(SmoothStep(Edge + 0.01f, Edge - 0.004f, A), SmoothStep(Edge + 0.008f, Edge - 0.004f, B));
	if (World == EStillworldWorld::Reclaimed)
	{
		T *= 1.f - Town(X, Y);
	}
	return T;
}

float FStillworldGenerator::MeadowHeight(FVector2f P) const
{
	// Domain warp: hills lose the "blobby" fBm look and get organic folds.
	const FVector2f W(Fbm(P / 900.f, 2, 1), Fbm(P / 900.f, 2, 2));
	const float Large = Fbm(P / 2600.f, 4, 0) * 26.f;
	const float Hills = Fbm((P + W * 140.f) / 650.f, 5, 3) * 17.f;
	// Distant ridges give the fog something to swallow on the horizon.
	const float Ridge = Ridged(P / 2200.f, 4, 4) * SmoothStep(0.15f, 0.55f, Fbm(P / 7000.f, 2, 5)) * 90.f;
	const float Detail = Fbm(P / 55.f, 3, 6) * 0.9f + Fbm(P / 8.f, 2, 7) * 0.1f;
	// Worn paths sit a few centimetres below the turf.
	return Large + Hills + Ridge + Detail - Track(P.X, P.Y) * 0.12f;
}

float FStillworldGenerator::ReclaimedHeight(FVector2f P) const
{
	const float Low = Fbm(P / 1800.f, 4, 0) * 22.f;
	const float Mid = Fbm(P / 240.f, 3, 3) * 3.f;
	const float Fine = Fbm(P / 35.f, 2, 6) * 0.35f + Fbm(P / 7.f, 2, 7) * 0.06f;
	const float T = Town(P.X, P.Y);
	// Towns were built on levelled ground; roads follow the smooth terrain.
	float H = Low + (Mid + Fine) * (1.f - T * 0.8f);
	const float R = Road(P.X, P.Y);
	H = FMath::Lerp(H, Low + Fine * 0.15f, R);
	return H;
}

float FStillworldGenerator::Height(float X, float Y) const
{
	const FVector2f P(X, Y);
	return World == EStillworldWorld::Meadow ? MeadowHeight(P) : ReclaimedHeight(P);
}

FVector3f FStillworldGenerator::Normal(float X, float Y, float Eps) const
{
	const float Dx = Height(X + Eps, Y) - Height(X - Eps, Y);
	const float Dy = Height(X, Y + Eps) - Height(X, Y - Eps);
	return FVector3f(-Dx, -Dy, 2.f * Eps).GetSafeNormal();
}

// ---------------------------------------------------------------------------
// Town layout: a rotated, gently warped street grid. Infinite and continuous.

float FStillworldGenerator::Town(float X, float Y) const
{
	if (World != EStillworldWorld::Reclaimed)
	{
		return 0.f;
	}
	// Large town regions separated by reclaimed forest.
	return SmoothStep(-0.05f, 0.2f, Fbm(FVector2f(X, Y) / 2400.f, 3, 9));
}

FVector2f FStillworldGenerator::ToGrid(FVector2f P) const
{
	const FVector2f W(Fbm(P / 520.f, 2, 10), Fbm(P / 520.f, 2, 11));
	const FVector2f Q = P + W * 22.f;
	return FVector2f(FVector2f::DotProduct(Q, RoadAxisU), FVector2f::DotProduct(Q, RoadAxisV));
}

FVector2f FStillworldGenerator::FromGrid(FVector2f G) const
{
	const FVector2f Q = RoadAxisU * G.X + RoadAxisV * G.Y;
	FVector2f P = Q;
	for (int32 I = 0; I < 4; ++I)
	{
		const FVector2f W(Fbm(P / 520.f, 2, 10), Fbm(P / 520.f, 2, 11));
		P = Q - W * 22.f;
	}
	return P;
}

float FStillworldGenerator::Road(float X, float Y) const
{
	const float T = Town(X, Y);
	if (T < 0.25f)
	{
		return 0.f;
	}
	const FVector2f G = ToGrid(FVector2f(X, Y));
	const float DU = FMath::Abs(G.X - FMath::RoundToFloat(G.X / BlockU) * BlockU);
	const float DV = FMath::Abs(G.Y - FMath::RoundToFloat(G.Y / BlockV) * BlockV);
	const float D = FMath::Min(DU, DV);
	// Roads fade out (are swallowed) toward the edge of town.
	return SmoothStep(WalkHalf + 0.6f, WalkHalf - 0.4f, D) * SmoothStep(0.25f, 0.5f, T);
}

FVector2f FStillworldGenerator::RoadDirection(float X, float Y) const
{
	const FVector2f G = ToGrid(FVector2f(X, Y));
	const float DU = FMath::Abs(G.X - FMath::RoundToFloat(G.X / BlockU) * BlockU);
	const float DV = FMath::Abs(G.Y - FMath::RoundToFloat(G.Y / BlockV) * BlockV);
	// Near a U = const line the road runs along V, and vice versa.
	return DU < DV ? RoadAxisV : RoadAxisU;
}

bool FStillworldGenerator::LotByIndex(int32 I, int32 J, FLot& Out, FVector2f* OutGridCenter, FVector2f* OutHalf) const
{
	if (World != EStillworldWorld::Reclaimed || BuildingExtents.Num() == 0)
	{
		return false;
	}
	const uint32 H = Hash3(Seed, I, J);
	if ((H & 0xffff) / 65535.f > BuildingLotProbability)
	{
		return false;
	}
	// Corner lots touch the cross street; leave them empty (open corners).
	const int32 InBlock = ((I % 4) + 4) % 4;
	if (InBlock == 0 || InBlock == 3)
	{
		if (((H >> 16) & 3) == 0)
		{
			return false;
		}
	}
	const int32 Variant = static_cast<int32>((H >> 8) % static_cast<uint32>(BuildingExtents.Num()));
	const FVector2f Half = BuildingExtents[Variant];
	if (Half.X > LotWidth * 0.5f - 1.f || Half.Y > BlockV * 0.5f - WalkHalf - 2.f)
	{
		return false; // too big for a lot
	}
	// Even rows face the road at the bottom of the block, odd rows the top.
	const int32 BlockJ = FMath::FloorToInt32(J / 2.f);
	const bool bBottom = (J - BlockJ * 2) == 0;
	const float Setback = WalkHalf + 1.5f + Half.Y;
	FVector2f G;
	G.X = (I + 0.5f) * LotWidth;
	G.Y = bBottom ? BlockJ * BlockV + Setback : (BlockJ + 1) * BlockV - Setback;
	Out.Center = FromGrid(G);
	if (Town(Out.Center.X, Out.Center.Y) < 0.55f)
	{
		return false;
	}
	Out.Variant = Variant;
	Out.Hash = H;
	const float Base = FMath::RadiansToDegrees(RoadAngle) + (bBottom ? 0.f : 180.f);
	Out.YawDeg = Base + (((H >> 20) & 0xff) / 255.f - 0.5f) * 3.f; // slight decay misalignment
	if (OutGridCenter) { *OutGridCenter = G; }
	if (OutHalf) { *OutHalf = Half; }
	return true;
}

bool FStillworldGenerator::LotAt(float X, float Y, FLot& Out) const
{
	const FVector2f G = ToGrid(FVector2f(X, Y));
	const int32 I = FMath::FloorToInt32(G.X / LotWidth);
	const int32 J = FMath::FloorToInt32(G.Y / (BlockV * 0.5f));
	return LotByIndex(I, J, Out);
}

bool FStillworldGenerator::InsideBuilding(float X, float Y, float Margin) const
{
	const FVector2f G = ToGrid(FVector2f(X, Y));
	const int32 I = FMath::FloorToInt32(G.X / LotWidth);
	const int32 J = FMath::FloorToInt32(G.Y / (BlockV * 0.5f));
	FLot Lot;
	FVector2f C, Half;
	if (!LotByIndex(I, J, Lot, &C, &Half))
	{
		return false;
	}
	return FMath::Abs(G.X - C.X) < Half.X + Margin && FMath::Abs(G.Y - C.Y) < Half.Y + Margin;
}

void FStillworldGenerator::LotsInRect(const FVector2f& Min, const FVector2f& Max, TArray<FLot>& Out) const
{
	if (World != EStillworldWorld::Reclaimed)
	{
		return;
	}
	// Grid-space bounds of the rect's corners (+1 lot margin for the warp).
	FVector2f GMin(FLT_MAX, FLT_MAX), GMax(-FLT_MAX, -FLT_MAX);
	for (const FVector2f& C : { Min, Max, FVector2f(Min.X, Max.Y), FVector2f(Max.X, Min.Y) })
	{
		const FVector2f G = ToGrid(C);
		GMin = FVector2f(FMath::Min(GMin.X, G.X), FMath::Min(GMin.Y, G.Y));
		GMax = FVector2f(FMath::Max(GMax.X, G.X), FMath::Max(GMax.Y, G.Y));
	}
	const int32 I0 = FMath::FloorToInt32(GMin.X / LotWidth) - 1;
	const int32 I1 = FMath::FloorToInt32(GMax.X / LotWidth) + 1;
	const int32 J0 = FMath::FloorToInt32(GMin.Y / (BlockV * 0.5f)) - 1;
	const int32 J1 = FMath::FloorToInt32(GMax.Y / (BlockV * 0.5f)) + 1;
	for (int32 J = J0; J <= J1; ++J)
	{
		for (int32 I = I0; I <= I1; ++I)
		{
			FLot Lot;
			// Each lot belongs to exactly one chunk: the one containing its centre.
			if (LotByIndex(I, J, Lot) && Lot.Center.X >= Min.X && Lot.Center.X < Max.X
				&& Lot.Center.Y >= Min.Y && Lot.Center.Y < Max.Y)
			{
				Out.Add(Lot);
			}
		}
	}
}

// ---------------------------------------------------------------------------
// Surfaces

FVector4f FStillworldGenerator::Surface(float X, float Y) const
{
	const FVector2f P(X, Y);
	const FVector3f N = Normal(X, Y, 1.5f);
	const float Slope = 1.f - N.Z;
	const float DirtPatch = SmoothStep(0.25f, 0.5f, Fbm(P / 70.f, 3, 12) + Fbm(P / 9.f, 2, 13) * 0.25f);
	const float Path = Track(X, Y);
	if (World == EStillworldWorld::Meadow)
	{
		const float Dirt = FMath::Clamp(DirtPatch * 0.6f + SmoothStep(0.25f, 0.5f, Slope) + Path * 0.85f, 0.f, 1.f);
		const float Moss = SmoothStep(0.2f, 0.6f, Fbm(P / 30.f, 2, 14)) * 0.3f * (1.f - Path);
		return FVector4f(1.f - Dirt, Dirt, 0.f, Moss);
	}
	const float Asphalt = Road(X, Y);
	const float Town01 = Town(X, Y);
	// Rubble/dirt around town, forest floor outside.
	const float Dirt = FMath::Clamp(DirtPatch * (0.5f + Town01 * 0.4f) + SmoothStep(0.25f, 0.5f, Slope) + Path * 0.85f, 0.f, 1.f) * (1.f - Asphalt);
	const float Grass = FMath::Max(0.f, 1.f - Asphalt - Dirt);
	// Nature reclaims everything: moss in asphalt cracks and on the ground.
	const float Moss = FMath::Clamp(SmoothStep(0.1f, 0.55f, Fbm(P / 18.f, 3, 15)) * (0.35f + 0.4f * (1.f - Town01))
		+ Asphalt * SmoothStep(0.35f, 0.7f, Fbm(P / 4.f, 2, 1)) * 0.6f, 0.f, 1.f);
	return FVector4f(Grass, Dirt, Asphalt, Moss);
}

// ---------------------------------------------------------------------------
// Spawn

FVector2f FStillworldGenerator::FindSpawn(float& OutYaw) const
{
	OutYaw = 0.f;
	const float Step = 96.f;
	float Angle = 0.f, Radius = 0.f;
	// Always return the best candidate seen, never a point inside a building.
	float BestScore = -1.f;
	FVector2f Best = FVector2f::ZeroVector;
	float BestYaw = 0.f;
	for (int32 I = 0; I < 6000; ++I)
	{
		const FVector2f P(FMath::Cos(Angle) * Radius, FMath::Sin(Angle) * Radius);
		const FVector3f N = Normal(P.X, P.Y, 4.f);
		float Score = -1.f;
		float Yaw = 0.f;
		if (World == EStillworldWorld::Reclaimed)
		{
			// Ideal: the middle of a street, deep inside a town.
			if (!InsideBuilding(P.X, P.Y, 2.f))
			{
				Score = N.Z * Town(P.X, P.Y) * (0.2f + Road(P.X, P.Y));
				const FVector2f D = RoadDirection(P.X, P.Y);
				Yaw = FMath::RadiansToDegrees(FMath::Atan2(D.Y, D.X));
			}
		}
		else
		{
			// Flat ground, looking downhill: the most open view over the meadow.
			Score = N.Z;
			Yaw = FMath::RadiansToDegrees(FMath::Atan2(N.Y, N.X));
		}
		if (Score > BestScore)
		{
			BestScore = Score;
			Best = P;
			BestYaw = Yaw;
		}
		const bool bIdeal = World == EStillworldWorld::Reclaimed ? Score > 0.9f : Score > 0.985f;
		if (bIdeal)
		{
			break;
		}
		Angle += Step / FMath::Max(Radius, Step);
		Radius = Step * Angle / UE_TWO_PI * 1.5f;
	}
	OutYaw = BestYaw;
	return Best;
}
