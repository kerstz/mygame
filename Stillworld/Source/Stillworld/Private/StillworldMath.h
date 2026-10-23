#pragma once

#include "CoreMinimal.h"

/** Small helpers shared by the generator and the world streamer. Named with
 *  a prefix so unity builds never see two definitions. */
namespace StillworldMath
{
	inline float SmoothStep(float E0, float E1, float X)
	{
		const float T = FMath::Clamp((X - E0) / (E1 - E0), 0.f, 1.f);
		return T * T * (3.f - 2.f * T);
	}

	/** Metres -> centimetres. */
	constexpr float M = 100.f;
}
