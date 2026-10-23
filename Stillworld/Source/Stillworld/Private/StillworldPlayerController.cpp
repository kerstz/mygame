#include "StillworldPlayerController.h"

#include "EnhancedInputComponent.h"
#include "EnhancedInputSubsystems.h"
#include "Engine/Engine.h"
#include "Engine/GameViewportClient.h"
#include "Engine/LocalPlayer.h"
#include "InputAction.h"
#include "InputMappingContext.h"
#include "InputModifiers.h"
#include "Misc/CommandLine.h"
#include "Misc/FileHelper.h"
#include "Misc/Parse.h"
#include "Misc/Paths.h"
#include "RHI.h"
#include "SStillworldMenu.h"
#include "StillworldGameMode.h"
#include "StillworldCharacter.h"
#include "StillworldSettings.h"
#include "Widgets/SWeakWidget.h"

void AStillworldPlayerController::EnsureInputObjects()
{
	if (Mapping)
	{
		return;
	}
	Mapping = NewObject<UInputMappingContext>(this, TEXT("IMC_Stillworld"));

	MoveAction = NewObject<UInputAction>(this, TEXT("IA_Move"));
	MoveAction->ValueType = EInputActionValueType::Axis2D;
	LookAction = NewObject<UInputAction>(this, TEXT("IA_Look"));
	LookAction->ValueType = EInputActionValueType::Axis2D;
	MenuAction = NewObject<UInputAction>(this, TEXT("IA_Menu"));
	MenuAction->ValueType = EInputActionValueType::Boolean;
	MenuAction->bTriggerWhenPaused = true;
	StatsAction = NewObject<UInputAction>(this, TEXT("IA_Stats"));
	StatsAction->ValueType = EInputActionValueType::Boolean;
	StatsAction->bTriggerWhenPaused = true;

	// Keyboard keys produce 1D values on X; forward/back are swizzled onto Y.
	auto MapMove = [this](const FKey& Key, bool bForwardAxis, bool bNegate)
	{
		FEnhancedActionKeyMapping& M = Mapping->MapKey(MoveAction, Key);
		if (bForwardAxis)
		{
			UInputModifierSwizzleAxis* Swizzle = NewObject<UInputModifierSwizzleAxis>(this);
			Swizzle->Order = EInputAxisSwizzle::YXZ;
			M.Modifiers.Add(Swizzle);
		}
		if (bNegate)
		{
			M.Modifiers.Add(NewObject<UInputModifierNegate>(this));
		}
	};
	// QWERTY (WASD), AZERTY (ZQSD) and arrows all work out of the box.
	MapMove(EKeys::W, true, false);
	MapMove(EKeys::Z, true, false);
	MapMove(EKeys::Up, true, false);
	MapMove(EKeys::S, true, true);
	MapMove(EKeys::Down, true, true);
	MapMove(EKeys::A, false, true);
	MapMove(EKeys::Q, false, true);
	MapMove(EKeys::Left, false, true);
	MapMove(EKeys::D, false, false);
	MapMove(EKeys::Right, false, false);

	Mapping->MapKey(LookAction, EKeys::Mouse2D);
	Mapping->MapKey(MenuAction, EKeys::Escape);
	// Escape stops Play-In-Editor sessions, so Tab also opens the menu.
	Mapping->MapKey(MenuAction, EKeys::Tab);
	Mapping->MapKey(StatsAction, EKeys::F3);
}

void AStillworldPlayerController::SetupInputComponent()
{
	Super::SetupInputComponent();
	EnsureInputObjects();
	if (UEnhancedInputComponent* Input = Cast<UEnhancedInputComponent>(InputComponent))
	{
		Input->BindAction(MenuAction, ETriggerEvent::Started, this, &AStillworldPlayerController::ToggleMenu);
		Input->BindAction(StatsAction, ETriggerEvent::Started, this, &AStillworldPlayerController::CycleStats);
	}
}

void AStillworldPlayerController::BeginPlay()
{
	Super::BeginPlay();
	if (!IsLocalController())
	{
		return;
	}
	EnsureInputObjects();
	if (UEnhancedInputLocalPlayerSubsystem* Sub = ULocalPlayer::GetSubsystem<UEnhancedInputLocalPlayerSubsystem>(GetLocalPlayer()))
	{
		Sub->AddMappingContext(Mapping, 0);
	}

	FStillworldSettings& S = FStillworldSettings::Get();
	FString PresetArg;
	if (FParse::Value(FCommandLine::Get(), TEXT("preset="), PresetArg))
	{
		for (EStillworldPreset P : { EStillworldPreset::Performance, EStillworldPreset::High,
			EStillworldPreset::Ultra, EStillworldPreset::Cinematic })
		{
			if (PresetArg.Equals(FStillworldSettings::PresetName(P), ESearchCase::IgnoreCase))
			{
				S.ApplyPreset(P);
			}
		}
	}
	S.Apply(GetWorld());

	SetInputMode(FInputModeGameOnly());
	SetShowMouseCursor(false);

	// Title screen over the live, already generating landscape.
	const AStillworldGameMode* GM = GetWorld()->GetAuthGameMode<AStillworldGameMode>();
	if (GM && GM->bShowTitle)
	{
		SetMenuOpen(true, true);
	}

	if (FParse::Param(FCommandLine::Get(), TEXT("benchmark")))
	{
		Bench = EBench::Warmup;
		BenchPhaseStart = FPlatformTime::Seconds();
		UE_LOG(LogTemp, Display, TEXT("[Stillworld] Benchmark: warming up (preset %s)"), FStillworldSettings::PresetName(S.Preset));
	}
}

void AStillworldPlayerController::EndPlay(const EEndPlayReason::Type Reason)
{
	SetMenuOpen(false);
	Super::EndPlay(Reason);
}

void AStillworldPlayerController::ToggleMenu()
{
	SetMenuOpen(!bMenuOpen);
}

void AStillworldPlayerController::SetMenuOpen(bool bOpen, bool bTitle)
{
	if (bOpen == bMenuOpen)
	{
		return;
	}
	bMenuOpen = bOpen;
	UGameViewportClient* Viewport = GEngine ? GEngine->GameViewport : nullptr;
	if (bOpen)
	{
		Menu = SNew(SStillworldMenu).Owner(this)
			.Mode(bTitle ? SStillworldMenu::EMode::Title : SStillworldMenu::EMode::Pause);
		MenuContainer = SNew(SWeakWidget).PossiblyNullContent(Menu);
		if (Viewport)
		{
			Viewport->AddViewportWidgetContent(MenuContainer.ToSharedRef(), 100);
		}
		// The title screen keeps the world alive (rain, wind) behind the menu.
		if (!bTitle)
		{
			SetPause(true);
		}
		FInputModeGameAndUI Mode;
		Mode.SetWidgetToFocus(Menu);
		Mode.SetLockMouseToViewportBehavior(EMouseLockMode::LockAlways);
		Mode.SetHideCursorDuringCapture(false);
		SetInputMode(Mode);
		SetShowMouseCursor(true);
	}
	else
	{
		if (Viewport && MenuContainer.IsValid())
		{
			Viewport->RemoveViewportWidgetContent(MenuContainer.ToSharedRef());
		}
		Menu.Reset();
		MenuContainer.Reset();
		SetPause(false);
		SetInputMode(FInputModeGameOnly());
		SetShowMouseCursor(false);
	}
}

void AStillworldPlayerController::CycleStats()
{
	// Developer overlay (hidden by default — gameplay has no HUD).
	// 1: fps + frame/game/draw/GPU ms, 2: + GPU pass breakdown, 0: off.
	StatsMode = (StatsMode + 1) % 3;
	switch (StatsMode)
	{
	case 1:
		ConsoleCommand(TEXT("stat fps"));
		ConsoleCommand(TEXT("stat unit"));
		break;
	case 2:
		ConsoleCommand(TEXT("stat gpu"));
		break;
	default:
		ConsoleCommand(TEXT("stat none"));
		break;
	}
}

void AStillworldPlayerController::PlayerTick(float DeltaTime)
{
	Super::PlayerTick(DeltaTime);
	if (Bench != EBench::Off)
	{
		BenchmarkTick(DeltaTime);
	}
}

void AStillworldPlayerController::BenchmarkTick(float DeltaTime)
{
	const double Now = FPlatformTime::Seconds();
	AStillworldCharacter* Walker = Cast<AStillworldCharacter>(GetPawn());
	if (Bench == EBench::Warmup)
	{
		// Generous warm-up: PSO/shader compilation and Lumen surface cache.
		if (Now - BenchPhaseStart > 12.0)
		{
			Bench = EBench::Measure;
			BenchPhaseStart = Now;
			BenchFrames.Reset();
			BenchGpu.Reset();
			if (Walker)
			{
				Walker->AutoWalk = FVector2D(0.f, 1.f);
			}
		}
		return;
	}
	BenchFrames.Add(DeltaTime * 1000.f);
	BenchGpu.Add(FPlatformTime::ToMilliseconds(RHIGetGPUFrameCycles()));
	if (Now - BenchPhaseStart > 30.0)
	{
		if (Walker)
		{
			Walker->AutoWalk = FVector2D::ZeroVector;
		}
		BenchmarkFinish();
	}
}

static float Average(const TArray<float>& A)
{
	double Sum = 0.0;
	for (float V : A)
	{
		Sum += V;
	}
	return A.Num() ? static_cast<float>(Sum / A.Num()) : 0.f;
}

void AStillworldPlayerController::BenchmarkFinish()
{
	Bench = EBench::Off;
	TArray<float> Sorted = BenchFrames;
	Sorted.Sort();
	const int32 N = Sorted.Num();
	const float AvgMs = Average(BenchFrames);
	const float P99 = N ? Sorted[FMath::Min(N - 1, FMath::FloorToInt(N * 0.99f))] : 0.f;
	const float P1Fps = P99 > 0.f ? 1000.f / P99 : 0.f;
	FIntPoint Size(0, 0);
	if (GEngine && GEngine->GameViewport)
	{
		FVector2D VS;
		GEngine->GameViewport->GetViewportSize(VS);
		Size = FIntPoint(VS.X, VS.Y);
	}
	const FStillworldSettings& S = FStillworldSettings::Get();
	const FString Json = FString::Printf(TEXT(
		"{\n  \"preset\": \"%s\",\n  \"resolution\": \"%dx%d\",\n  \"screen_percentage\": %.0f,\n"
		"  \"rhi\": \"%s\",\n  \"adapter\": \"%s\",\n  \"frames\": %d,\n  \"avg_ms\": %.3f,\n  \"avg_fps\": %.1f,\n"
		"  \"p99_ms\": %.3f,\n  \"one_percent_low_fps\": %.1f,\n  \"gpu_avg_ms\": %.3f\n}\n"),
		FStillworldSettings::PresetName(S.Preset), Size.X, Size.Y, S.ScreenPercentage,
		GDynamicRHI ? GDynamicRHI->GetName() : TEXT("?"), *GRHIAdapterName, N, AvgMs,
		AvgMs > 0.f ? 1000.f / AvgMs : 0.f, P99, P1Fps, Average(BenchGpu));
	const FString Path = FPaths::ProjectSavedDir() / TEXT("Benchmark") /
		FString::Printf(TEXT("benchmark_%s.json"), FStillworldSettings::PresetName(S.Preset));
	FFileHelper::SaveStringToFile(Json, *Path);
	UE_LOG(LogTemp, Display, TEXT("[Stillworld] Benchmark written to %s\n%s"), *Path, *Json);
	ConsoleCommand(TEXT("quit"));
}
