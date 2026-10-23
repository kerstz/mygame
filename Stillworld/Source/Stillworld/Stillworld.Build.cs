using UnrealBuildTool;

public class Stillworld : ModuleRules
{
	public Stillworld(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

		PublicDependencyModuleNames.AddRange(new string[]
		{
			"Core", "CoreUObject", "Engine", "InputCore", "EnhancedInput",
		});

		PrivateDependencyModuleNames.AddRange(new string[]
		{
			"Slate", "SlateCore", "RHI", "DeveloperSettings", "GeometryCore", "GeometryFramework",
		});
	}
}
