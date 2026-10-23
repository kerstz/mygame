#pragma once

#include "CoreMinimal.h"
#include "Widgets/SCompoundWidget.h"

class AStillworldPlayerController;
class SVerticalBox;
class SWidgetSwitcher;

/**
 * The only UI in the game. A quiet column of large text entries over the
 * live landscape (title screen and pause), plus a complete settings page.
 * Built in Slate, so it needs no UMG assets.
 */
class SStillworldMenu : public SCompoundWidget
{
public:
	enum class EMode : uint8 { Title, Pause };

	SLATE_BEGIN_ARGS(SStillworldMenu) {}
		SLATE_ARGUMENT(TWeakObjectPtr<AStillworldPlayerController>, Owner)
		SLATE_ARGUMENT(EMode, Mode)
	SLATE_END_ARGS()

	void Construct(const FArguments& InArgs);
	virtual bool SupportsKeyboardFocus() const override { return true; }

private:
	TWeakObjectPtr<AStillworldPlayerController> Owner;
	EMode Mode = EMode::Pause;
	TSharedPtr<SWidgetSwitcher> Pages;     // 0 main, 1 worlds, 2 settings
	TSharedPtr<SWidgetSwitcher> Tabs;      // settings categories
	int32 TabIndex = 0;

	TSharedRef<SWidget> BuildMain();
	TSharedRef<SWidget> BuildWorlds();
	TSharedRef<SWidget> BuildSettings();

	void Commit();

	TSharedRef<SWidget> Entry(const FText& Label, TFunction<void()> OnClick, int32 Size = 30);
	TSharedRef<SVerticalBox> Page();
	void AddChoice(TSharedRef<SVerticalBox> Box, const FText& Label, TArray<FText> Options,
		TFunction<int32()> Get, TFunction<void(int32)> Set, TFunction<bool()> Enabled = nullptr);
	void AddSlider(TSharedRef<SVerticalBox> Box, const FText& Label, float Min, float Max,
		TFunction<float()> Get, TFunction<void(float)> Set, bool bInteger, bool bCommitOnRelease);
	void AddNote(TSharedRef<SVerticalBox> Box, TAttribute<FText> Text);
};
