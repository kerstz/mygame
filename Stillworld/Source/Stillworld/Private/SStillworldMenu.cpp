#include "SStillworldMenu.h"

#include "StillworldGameMode.h"
#include "StillworldPlayerController.h"
#include "StillworldSettings.h"
#include "StillworldWorld.h"
#include "Styling/CoreStyle.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Input/SSlider.h"
#include "Widgets/Layout/SBorder.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/Layout/SScrollBox.h"
#include "Widgets/Layout/SSpacer.h"
#include "Widgets/Layout/SWidgetSwitcher.h"
#include "Widgets/SBoxPanel.h"
#include "Widgets/Text/STextBlock.h"

#define LOCTEXT_NAMESPACE "StillworldMenu"

namespace
{
	FSlateFontInfo Font(int32 Size, const TCHAR* Weight = TEXT("Light"))
	{
		return FCoreStyle::GetDefaultFontStyle(Weight, Size);
	}
	const FLinearColor Ink(0.92f, 0.93f, 0.91f, 1.f);
	const FLinearColor Dim(0.92f, 0.93f, 0.91f, 0.55f);
	const FLinearColor Accent(0.72f, 0.80f, 0.70f, 1.f);

	/** Flat, invisible button style: only the text reacts to hover. */
	const FButtonStyle& FlatButton()
	{
		static FButtonStyle Style = []()
		{
			FButtonStyle S;
			const FSlateBrush* None = FCoreStyle::Get().GetBrush("NoBrush");
			S.SetNormal(*None).SetHovered(*None).SetPressed(*None).SetDisabled(*None);
			S.SetNormalPadding(FMargin(0)).SetPressedPadding(FMargin(0));
			// Hovered entries brighten to the accent colour: the only animation needed.
			S.SetNormalForeground(Ink).SetHoveredForeground(Accent).SetPressedForeground(Accent)
				.SetDisabledForeground(FLinearColor(1, 1, 1, 0.25f));
			return S;
		}();
		return Style;
	}

	FText Quality(int32 Q)
	{
		static const FText Names[5] = {
			LOCTEXT("Q0", "Bas"), LOCTEXT("Q1", "Moyen"), LOCTEXT("Q2", "Élevé"),
			LOCTEXT("Q3", "Épique"), LOCTEXT("Q4", "Cinématique") };
		return Names[FMath::Clamp(Q, 0, 4)];
	}
}

void SStillworldMenu::Construct(const FArguments& InArgs)
{
	Owner = InArgs._Owner;
	Mode = InArgs._Mode;

	ChildSlot
	[
		SNew(SHorizontalBox)
		// Left: a soft dark column; right: the living landscape, untouched.
		+ SHorizontalBox::Slot().AutoWidth()
		[
			SNew(SBorder)
			.BorderImage(FCoreStyle::Get().GetBrush("GenericWhiteBox"))
			.BorderBackgroundColor(FLinearColor(0.012f, 0.015f, 0.014f, Mode == EMode::Title ? 0.62f : 0.72f))
			.Padding(FMargin(72.f, 64.f, 56.f, 48.f))
			[
				SNew(SBox).WidthOverride(560.f)
				[
					SNew(SVerticalBox)
					+ SVerticalBox::Slot().AutoHeight()
					[
						SNew(STextBlock).Text(LOCTEXT("Title", "STILLWORLD"))
						.Font(Font(46, TEXT("Light"))).ColorAndOpacity(Ink)
					]
					+ SVerticalBox::Slot().AutoHeight().Padding(0, 4, 0, 48)
					[
						SNew(STextBlock).Text(LOCTEXT("Tagline", "marcher, simplement."))
						.Font(Font(16, TEXT("Italic"))).ColorAndOpacity(Dim)
					]
					+ SVerticalBox::Slot().FillHeight(1.f)
					[
						SAssignNew(Pages, SWidgetSwitcher)
						+ SWidgetSwitcher::Slot()[BuildMain()]
						+ SWidgetSwitcher::Slot()[BuildWorlds()]
						+ SWidgetSwitcher::Slot()[BuildSettings()]
					]
				]
			]
		]
		+ SHorizontalBox::Slot().FillWidth(1.f)[SNew(SSpacer)]
	];
}

TSharedRef<SVerticalBox> SStillworldMenu::Page()
{
	return SNew(SVerticalBox);
}

TSharedRef<SWidget> SStillworldMenu::Entry(const FText& Label, TFunction<void()> OnClick, int32 Size)
{
	return SNew(SBox).Padding(FMargin(0, 6))
	[
		SNew(SButton)
		.ButtonStyle(&FlatButton())
		.OnClicked_Lambda([OnClick]() { OnClick(); return FReply::Handled(); })
		[
			SNew(STextBlock).Text(Label).Font(Font(Size))
		]
	];
}

TSharedRef<SWidget> SStillworldMenu::BuildMain()
{
	TSharedRef<SVerticalBox> Box = Page();
	TWeakObjectPtr<AStillworldPlayerController> O = Owner;
	if (Mode == EMode::Title)
	{
		Box->AddSlot().AutoHeight()[Entry(LOCTEXT("Walk", "Marcher"), [O]()
		{
			// The map behind the menu is already generated: just start walking.
			if (O.IsValid()) { O->SetMenuOpen(false); }
		})];
	}
	else
	{
		Box->AddSlot().AutoHeight()[Entry(LOCTEXT("Resume", "Reprendre"), [O]()
		{
			if (O.IsValid()) { O->SetMenuOpen(false); }
		})];
	}
	Box->AddSlot().AutoHeight()[Entry(LOCTEXT("Worlds", "Nouvelle carte"), [this]() { Pages->SetActiveWidgetIndex(1); })];
	Box->AddSlot().AutoHeight()[Entry(LOCTEXT("Settings", "Réglages"), [this]() { Pages->SetActiveWidgetIndex(2); })];
	Box->AddSlot().AutoHeight()[Entry(LOCTEXT("Quit", "Quitter"), [O]()
	{
		if (O.IsValid()) { O->ConsoleCommand(TEXT("quit")); }
	})];
	Box->AddSlot().FillHeight(1.f)[SNew(SSpacer)];
	Box->AddSlot().AutoHeight()
	[
		SNew(STextBlock).Font(Font(12, TEXT("Regular"))).ColorAndOpacity(Dim)
		.Text_Lambda([O]()
		{
			const AStillworldWorld* W = O.IsValid() ? AStillworldWorld::Find(O.Get()) : nullptr;
			if (!W) { return FText::GetEmpty(); }
			const bool bMeadow = W->GetGenerator().GetWorld() == EStillworldWorld::Meadow;
			return FText::Format(LOCTEXT("Seed", "{0} · carte n° {1}"),
				bMeadow ? LOCTEXT("MeadowName", "Prairie sous la pluie") : LOCTEXT("CityName", "Ville reprise par la nature"),
				FText::AsNumber(W->GetGenerator().GetSeed(), &FNumberFormattingOptions::DefaultNoGrouping()));
		})
	];
	return Box;
}

TSharedRef<SWidget> SStillworldMenu::BuildWorlds()
{
	TSharedRef<SVerticalBox> Box = Page();
	TWeakObjectPtr<AStillworldPlayerController> O = Owner;
	auto Go = [O](EStillworldWorld Kind)
	{
		if (O.IsValid()) { AStillworldGameMode::TravelToNewWorld(O.Get(), Kind); }
	};
	Box->AddSlot().AutoHeight()[Entry(LOCTEXT("Meadow", "Prairie sous la pluie"), [Go]() { Go(EStillworldWorld::Meadow); })];
	Box->AddSlot().AutoHeight().Padding(0, 0, 0, 14)
	[
		SNew(STextBlock).Font(Font(13, TEXT("Regular"))).ColorAndOpacity(Dim).AutoWrapText(true)
		.Text(LOCTEXT("MeadowDesc", "Herbes hautes, bruine et brume sans fin. Chaque carte est unique."))
	];
	Box->AddSlot().AutoHeight()[Entry(LOCTEXT("City", "Ville reprise par la nature"), [Go]() { Go(EStillworldWorld::Reclaimed); })];
	Box->AddSlot().AutoHeight().Padding(0, 0, 0, 14)
	[
		SNew(STextBlock).Font(Font(13, TEXT("Regular"))).ColorAndOpacity(Dim).AutoWrapText(true)
		.Text(LOCTEXT("CityDesc", "Rues désertes, carcasses de voitures, végétation qui a tout repris. Chaque carte est unique."))
	];
	Box->AddSlot().FillHeight(1.f)[SNew(SSpacer)];
	Box->AddSlot().AutoHeight()[Entry(LOCTEXT("Back", "‹  Retour"), [this]() { Pages->SetActiveWidgetIndex(0); }, 20)];
	return Box;
}

void SStillworldMenu::Commit()
{
	FStillworldSettings& S = FStillworldSettings::Get();
	S.Apply(Owner.IsValid() ? Owner->GetWorld() : nullptr);
	S.Save();
}

void SStillworldMenu::AddNote(TSharedRef<SVerticalBox> Box, TAttribute<FText> Text)
{
	Box->AddSlot().AutoHeight().Padding(0, 2, 0, 8)
	[
		SNew(STextBlock).Font(Font(12, TEXT("Regular"))).ColorAndOpacity(Dim).AutoWrapText(true).Text(Text)
	];
}

void SStillworldMenu::AddChoice(TSharedRef<SVerticalBox> Box, const FText& Label, TArray<FText> Options,
	TFunction<int32()> Get, TFunction<void(int32)> Set, TFunction<bool()> Enabled)
{
	const int32 Count = Options.Num();
	auto Step = [this, Get, Set, Count, Enabled](int32 Dir)
	{
		if (Enabled && !Enabled()) { return; }
		Set((Get() + Dir + Count) % Count);
		Commit();
	};
	Box->AddSlot().AutoHeight().Padding(0, 4)
	[
		SNew(SHorizontalBox)
		.IsEnabled_Lambda([Enabled]() { return !Enabled || Enabled(); })
		+ SHorizontalBox::Slot().FillWidth(1.f).VAlign(VAlign_Center)
		[
			SNew(STextBlock).Text(Label).Font(Font(15, TEXT("Regular"))).ColorAndOpacity(Ink)
		]
		+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center)
		[
			SNew(SButton).ButtonStyle(&FlatButton()).OnClicked_Lambda([Step]() { Step(-1); return FReply::Handled(); })
			[SNew(STextBlock).Text(FText::FromString(TEXT("‹"))).Font(Font(20)).ColorAndOpacity(Accent)]
		]
		+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center)
		[
			SNew(SBox).WidthOverride(170.f).HAlign(HAlign_Center)
			[
				SNew(STextBlock).Font(Font(15, TEXT("Regular"))).ColorAndOpacity(Ink)
				.Text_Lambda([Options, Get]() { return Options[FMath::Clamp(Get(), 0, Options.Num() - 1)]; })
			]
		]
		+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center)
		[
			SNew(SButton).ButtonStyle(&FlatButton()).OnClicked_Lambda([Step]() { Step(1); return FReply::Handled(); })
			[SNew(STextBlock).Text(FText::FromString(TEXT("›"))).Font(Font(20)).ColorAndOpacity(Accent)]
		]
	];
}

void SStillworldMenu::AddSlider(TSharedRef<SVerticalBox> Box, const FText& Label, float Min, float Max,
	TFunction<float()> Get, TFunction<void(float)> Set, bool bInteger, bool bCommitOnRelease)
{
	Box->AddSlot().AutoHeight().Padding(0, 4)
	[
		SNew(SHorizontalBox)
		+ SHorizontalBox::Slot().FillWidth(1.f).VAlign(VAlign_Center)
		[
			SNew(STextBlock).Text(Label).Font(Font(15, TEXT("Regular"))).ColorAndOpacity(Ink)
		]
		+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center)
		[
			SNew(SBox).WidthOverride(170.f)
			[
				SNew(SSlider)
				.MinValue(Min).MaxValue(Max)
				.SliderBarColor(FLinearColor(1, 1, 1, 0.25f))
				.SliderHandleColor(Accent)
				.Value_Lambda([Get]() { return Get(); })
				.OnValueChanged_Lambda([this, Set, bInteger, bCommitOnRelease](float V)
				{
					Set(bInteger ? FMath::RoundToFloat(V) : V);
					if (!bCommitOnRelease) { Commit(); }
				})
				.OnMouseCaptureEnd_Lambda([this, bCommitOnRelease]()
				{
					// Resolution / density changes are applied once, on release.
					if (bCommitOnRelease) { Commit(); }
				})
			]
		]
		+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(12, 0, 0, 0)
		[
			SNew(SBox).WidthOverride(48.f)
			[
				SNew(STextBlock).Font(Font(14, TEXT("Regular"))).ColorAndOpacity(Dim)
				.Text_Lambda([Get, bInteger]()
				{
					return FText::FromString(bInteger ? FString::Printf(TEXT("%.0f"), Get()) : FString::Printf(TEXT("%.2f"), Get()));
				})
			]
		]
	];
}

TSharedRef<SWidget> SStillworldMenu::BuildSettings()
{
	FStillworldSettings* S = &FStillworldSettings::Get();
	// Pointer (not reference) so lambdas can capture it by value safely.
	const FStillworldVendorFeatures* V = &FStillworldVendorFeatures::Get();
	auto Custom = [S]() { S->Preset = EStillworldPreset::Custom; };
	const TArray<FText> Q5 = { Quality(0), Quality(1), Quality(2), Quality(3), Quality(4) };
	const TArray<FText> OffOn = { LOCTEXT("Off", "Désactivé"), LOCTEXT("On", "Activé") };

	// --- Image
	TSharedRef<SVerticalBox> Image = Page();
	AddChoice(Image, LOCTEXT("Preset", "Préréglage"),
		{ LOCTEXT("PPerf", "Performance"), LOCTEXT("PHigh", "Élevé"), LOCTEXT("PUltra", "Ultra"), LOCTEXT("PCustom", "Personnalisé") },
		[S]() { return static_cast<int32>(S->Preset); },
		[S](int32 I) { if (I < 3) { S->ApplyPreset(static_cast<EStillworldPreset>(I)); } else { S->Preset = EStillworldPreset::Custom; } });
	AddNote(Image, TAttribute<FText>::CreateLambda([S]()
	{
		switch (S->Preset)
		{
		case EStillworldPreset::Performance: return LOCTEXT("NPerf", "Fluidité d'abord : Lumen logiciel, résolution interne réduite, upscaling.");
		case EStillworldPreset::High: return LOCTEXT("NHigh", "Équilibré : qualité Épique, environ 72 % de résolution interne.");
		case EStillworldPreset::Ultra: return LOCTEXT("NUltra", "Sans compromis : Cinématique, résolution native, ray tracing avec reflets tracés. Prévoir 30-60 i/s.");
		default: return LOCTEXT("NCustom", "Réglages personnalisés.");
		}
	}));
	AddChoice(Image, LOCTEXT("Upscaler", "Upscaling"),
		{ LOCTEXT("TSR", "TSR (Unreal)"), LOCTEXT("FSR", "AMD FSR"), LOCTEXT("DLSS", "NVIDIA DLSS") },
		[S]() { return static_cast<int32>(S->Upscaler); },
		[S, V, Custom](int32 I)
		{
			// Skip upscalers whose plugin is not installed.
			for (int32 K = 0; K < 3; ++K)
			{
				const EStillworldUpscaler U = static_cast<EStillworldUpscaler>((I + K) % 3);
				if (U == EStillworldUpscaler::TSR || (U == EStillworldUpscaler::FSR && V->HasFSR()) || (U == EStillworldUpscaler::DLSS && V->HasDLSS()))
				{
					S->Upscaler = U;
					break;
				}
			}
			Custom();
		});
	AddSlider(Image, LOCTEXT("ScreenPct", "Résolution de rendu (%)"), 33.f, 100.f,
		[S]() { return S->ScreenPercentage; }, [S, Custom](float X) { S->ScreenPercentage = X; Custom(); }, true, true);
	AddChoice(Image, LOCTEXT("FrameGen", "Génération d'images"), OffOn,
		[S]() { return S->bFrameGeneration ? 1 : 0; }, [S](int32 I) { S->bFrameGeneration = I == 1; },
		[S, V]() { return V->HasFrameGen(S->Upscaler); });
	AddChoice(Image, LOCTEXT("RT", "Ray tracing"),
		{ LOCTEXT("RT0", "Désactivé"), LOCTEXT("RT1", "Lumen matériel"), LOCTEXT("RT2", "Lumen + reflets tracés") },
		[S]() { return static_cast<int32>(S->RayTracing); },
		[S, Custom](int32 I) { S->RayTracing = static_cast<EStillworldRayTracing>(I); Custom(); },
		[V]() { return V->HasHardwareRayTracing(); });
	AddNote(Image, TAttribute<FText>::CreateLambda([S, V]()
	{
		if (!V->HasFrameGen(S->Upscaler))
		{
			return LOCTEXT("NoFG", "Génération d'images : nécessite le plugin AMD FSR ou NVIDIA DLSS (Streamline) avec DirectX 12 — sous Linux, lancer la version Windows via Proton.");
		}
		return LOCTEXT("FG", "La génération d'images double la fluidité perçue ; elle est plus agréable au-dessus de 50 i/s de base.");
	}));

	// --- Quality
	TSharedRef<SVerticalBox> Qual = Page();
	auto Group = [&](const FText& Label, int32 FStillworldSettings::* Field)
	{
		AddChoice(Qual, Label, Q5, [S, Field]() { return S->*Field; }, [S, Field, Custom](int32 I) { S->*Field = I; Custom(); });
	};
	Group(LOCTEXT("GView", "Distance d'affichage"), &FStillworldSettings::ViewDistance);
	Group(LOCTEXT("GShadow", "Ombres"), &FStillworldSettings::Shadows);
	Group(LOCTEXT("GGI", "Illumination globale"), &FStillworldSettings::GlobalIllumination);
	Group(LOCTEXT("GRefl", "Reflets"), &FStillworldSettings::Reflections);
	Group(LOCTEXT("GTex", "Textures"), &FStillworldSettings::Textures);
	Group(LOCTEXT("GFx", "Effets (brouillard, nuages)"), &FStillworldSettings::Effects);
	Group(LOCTEXT("GFol", "Végétation (moteur)"), &FStillworldSettings::Foliage);
	Group(LOCTEXT("GShade", "Matériaux"), &FStillworldSettings::Shading);
	Group(LOCTEXT("GPost", "Post-traitement"), &FStillworldSettings::PostProcess);
	AddSlider(Qual, LOCTEXT("FDens", "Densité de la végétation"), 0.2f, 1.f,
		[S]() { return S->FoliageDensity; }, [S, Custom](float X) { S->FoliageDensity = X; Custom(); }, false, true);
	AddSlider(Qual, LOCTEXT("FDist", "Portée de la végétation"), 0.5f, 2.f,
		[S]() { return S->FoliageDistance; }, [S, Custom](float X) { S->FoliageDistance = X; Custom(); }, false, true);

	// --- Display
	TSharedRef<SVerticalBox> Disp = Page();
	AddChoice(Disp, LOCTEXT("Window", "Affichage"),
		{ LOCTEXT("W0", "Plein écran"), LOCTEXT("W1", "Fenêtré sans bordure"), LOCTEXT("W2", "Fenêtré") },
		[S]() { return S->WindowMode; }, [S](int32 I) { S->WindowMode = I; });
	AddChoice(Disp, LOCTEXT("VSync", "Synchronisation verticale"), OffOn,
		[S]() { return S->bVSync ? 1 : 0; }, [S](int32 I) { S->bVSync = I == 1; });
	static const float Limits[] = { 0.f, 30.f, 60.f, 90.f, 120.f, 144.f, 165.f };
	AddChoice(Disp, LOCTEXT("Limit", "Limite d'images"),
		{ LOCTEXT("L0", "Aucune"), FText::FromString(TEXT("30")), FText::FromString(TEXT("60")), FText::FromString(TEXT("90")),
		  FText::FromString(TEXT("120")), FText::FromString(TEXT("144")), FText::FromString(TEXT("165")) },
		[S]()
		{
			for (int32 I = 0; I < 7; ++I) { if (FMath::IsNearlyEqual(S->FrameLimit, Limits[I])) { return I; } }
			return 0;
		},
		[S](int32 I) { S->FrameLimit = Limits[I]; });
	AddSlider(Disp, LOCTEXT("FOV", "Champ de vision"), 60.f, 110.f,
		[S]() { return S->FieldOfView; }, [S](float X) { S->FieldOfView = X; }, true, false);

	// --- Walking
	TSharedRef<SVerticalBox> Walk = Page();
	AddSlider(Walk, LOCTEXT("Sens", "Sensibilité de la souris"), 0.1f, 1.5f,
		[S]() { return S->MouseSensitivity; }, [S](float X) { S->MouseSensitivity = X; }, false, false);
	AddChoice(Walk, LOCTEXT("InvY", "Inverser l'axe vertical"), OffOn,
		[S]() { return S->bInvertY ? 1 : 0; }, [S](int32 I) { S->bInvertY = I == 1; });
	AddSlider(Walk, LOCTEXT("Head", "Mouvement de tête"), 0.f, 1.f,
		[S]() { return S->HeadMotion; }, [S](float X) { S->HeadMotion = X; }, false, false);
	AddSlider(Walk, LOCTEXT("Pace", "Allure (m/s)"), 1.f, 2.2f,
		[S]() { return S->WalkSpeed / 100.f; }, [S](float X) { S->WalkSpeed = X * 100.f; }, false, false);
	AddNote(Walk, LOCTEXT("Keys", "Avancer : ZQSD / WASD / flèches · Regarder : souris · Menu : Échap ou Tab · F3 : statistiques"));

	// --- Sound
	TSharedRef<SVerticalBox> Snd = Page();
	AddSlider(Snd, LOCTEXT("Master", "Volume général"), 0.f, 1.f,
		[S]() { return S->MasterVolume; }, [S](float X) { S->MasterVolume = X; }, false, false);
	AddSlider(Snd, LOCTEXT("Amb", "Pluie, vent et pas"), 0.f, 1.f,
		[S]() { return S->AmbienceVolume; }, [S](float X) { S->AmbienceVolume = X; }, false, false);
	AddSlider(Snd, LOCTEXT("RainInt", "Intensité de la pluie"), 0.f, 1.5f,
		[S]() { return S->WeatherIntensity; }, [S](float X) { S->WeatherIntensity = X; }, false, false);
	AddNote(Snd, LOCTEXT("NoMusic", "Pas de musique, volontairement."));

	// --- Tabs
	const TArray<FText> TabNames = { LOCTEXT("TImage", "Image"), LOCTEXT("TQual", "Qualité"),
		LOCTEXT("TDisp", "Écran"), LOCTEXT("TWalk", "Marche"), LOCTEXT("TSnd", "Son") };
	TSharedRef<SHorizontalBox> TabRow = SNew(SHorizontalBox);
	for (int32 I = 0; I < TabNames.Num(); ++I)
	{
		TabRow->AddSlot().AutoWidth().Padding(0, 0, 22, 0)
		[
			SNew(SButton).ButtonStyle(&FlatButton())
			.OnClicked_Lambda([this, I]() { TabIndex = I; Tabs->SetActiveWidgetIndex(I); return FReply::Handled(); })
			[
				SNew(STextBlock).Text(TabNames[I]).Font(Font(17, TEXT("Regular")))
				.ColorAndOpacity_Lambda([this, I]() { return FSlateColor(TabIndex == I ? Accent : Dim); })
			]
		];
	}

	return SNew(SVerticalBox)
		+ SVerticalBox::Slot().AutoHeight().Padding(0, 0, 0, 18)[TabRow]
		+ SVerticalBox::Slot().FillHeight(1.f)
		[
			SNew(SScrollBox)
			+ SScrollBox::Slot()
			[
				SAssignNew(Tabs, SWidgetSwitcher)
				+ SWidgetSwitcher::Slot()[Image]
				+ SWidgetSwitcher::Slot()[Qual]
				+ SWidgetSwitcher::Slot()[Disp]
				+ SWidgetSwitcher::Slot()[Walk]
				+ SWidgetSwitcher::Slot()[Snd]
			]
		]
		+ SVerticalBox::Slot().AutoHeight().Padding(0, 16, 0, 0)
		[
			Entry(LOCTEXT("Back2", "‹  Retour"), [this]() { Pages->SetActiveWidgetIndex(0); }, 20)
		];
}

#undef LOCTEXT_NAMESPACE
