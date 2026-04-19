#!/usr/bin/env ruby
# generate-xcodeproj.rb — Generates OpenClawQA.xcodeproj/project.pbxproj
# Run from the project root: ruby generate-xcodeproj.rb

require 'digest'
require 'fileutils'

# Deterministic UUID generation
$uuid_counter = 0
def make_uuid(seed)
  $uuid_counter += 1
  Digest::MD5.hexdigest("#{seed}-#{$uuid_counter}").upcase[0, 24]
end

# Collect all Swift source files
source_dir = File.join(File.dirname(__FILE__), 'OpenClawQA')
swift_files = Dir.glob(File.join(source_dir, '**', '*.swift')).sort
plist_file = File.join(source_dir, 'Resources', 'Info.plist')
assets_dir = File.join(source_dir, 'Resources', 'Assets.xcassets')

# Generate UUIDs for each file
file_refs = {}
build_files = {}

swift_files.each do |f|
  rel = f.sub("#{source_dir}/", '')
  file_refs[rel] = make_uuid("fileref-#{rel}")
  build_files[rel] = make_uuid("buildfile-#{rel}")
end

# Special file refs
plist_ref = make_uuid("fileref-info-plist")
assets_ref = make_uuid("fileref-assets")
assets_build = make_uuid("buildfile-assets")

# Group UUIDs
root_group = make_uuid("root-group")
app_group = make_uuid("app-group")
models_group = make_uuid("models-group")
database_group = make_uuid("database-group")
services_group = make_uuid("services-group")
viewmodels_group = make_uuid("viewmodels-group")
views_group = make_uuid("views-group")
theme_group = make_uuid("theme-group")
resources_group = make_uuid("resources-group")
sidebar_group = make_uuid("sidebar-group")
overview_group = make_uuid("overview-group")
runs_group = make_uuid("runs-group")
rundetail_group = make_uuid("rundetail-group")
findings_group = make_uuid("findings-group")
coverage_group = make_uuid("coverage-group")
insights_group = make_uuid("insights-group")
integrations_group = make_uuid("integrations-group")
settings_group = make_uuid("settings-group")
components_group = make_uuid("components-group")
projectsetup_group = make_uuid("projectsetup-group")
source_group = make_uuid("source-group")
products_group = make_uuid("products-group")

# Target and project UUIDs
project_uuid = make_uuid("project")
target_uuid = make_uuid("target")
product_ref = make_uuid("product-ref")
build_config_debug = make_uuid("build-config-debug")
build_config_release = make_uuid("build-config-release")
target_config_debug = make_uuid("target-config-debug")
target_config_release = make_uuid("target-config-release")
config_list = make_uuid("config-list")
target_config_list = make_uuid("target-config-list")
sources_phase = make_uuid("sources-phase")
resources_phase = make_uuid("resources-phase")
frameworks_phase = make_uuid("frameworks-phase")

# Helper: group files by directory
def files_in_dir(files, dir)
  files.select { |f, _| f.start_with?(dir) && !f.sub("#{dir}/", '').include?('/') }
end

def group_children(file_refs, dir)
  files_in_dir(file_refs, dir).map { |_, uuid| uuid }
end

# Build the pbxproj
pbx = <<~PBX
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 56;
	objects = {

/* Begin PBXBuildFile section */
PBX

swift_files.each do |f|
  rel = f.sub("#{source_dir}/", '')
  pbx << "\t\t#{build_files[rel]} /* #{File.basename(rel)} in Sources */ = {isa = PBXBuildFile; fileRef = #{file_refs[rel]} /* #{File.basename(rel)} */; };\n"
end
pbx << "\t\t#{assets_build} /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = #{assets_ref} /* Assets.xcassets */; };\n"

pbx << <<~PBX
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
PBX

swift_files.each do |f|
  rel = f.sub("#{source_dir}/", '')
  pbx << "\t\t#{file_refs[rel]} /* #{File.basename(rel)} */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \"#{File.basename(rel)}\"; sourceTree = \"<group>\"; };\n"
end
pbx << "\t\t#{plist_ref} /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; };\n"
pbx << "\t\t#{assets_ref} /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; };\n"
pbx << "\t\t#{product_ref} /* OpenClawQA.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = OpenClawQA.app; sourceTree = BUILT_PRODUCTS_DIR; };\n"

pbx << <<~PBX
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		#{frameworks_phase} /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
PBX

# Helper to emit group
def emit_group(uuid, name, children, path = nil)
  path_str = path ? "\t\t\tpath = \"#{path}\";" : ""
  child_str = children.map { |c| "\t\t\t\t#{c} /* */," }.join("\n")
  <<~GRP
  \t\t#{uuid} /* #{name} */ = {
  \t\t\tisa = PBXGroup;
  \t\t\tchildren = (
  #{child_str}
  \t\t\t);
  #{path_str}
  \t\t\tname = "#{name}";
  \t\t\tsourceTree = "<group>";
  \t\t};
  GRP
end

# Root group
root_children = [source_group, products_group]
pbx << emit_group(root_group, "OpenClawQA", root_children)

# Products group
pbx << emit_group(products_group, "Products", [product_ref])

# Source group (OpenClawQA/)
src_children = [app_group, models_group, database_group, services_group, viewmodels_group, views_group, theme_group, resources_group]
pbx << emit_group(source_group, "OpenClawQA", src_children, "OpenClawQA")

# App group
app_files = group_children(file_refs, 'App')
pbx << emit_group(app_group, "App", app_files, "App")

# Models group
models_files = group_children(file_refs, 'Models')
pbx << emit_group(models_group, "Models", models_files, "Models")

# Database group
db_files = group_children(file_refs, 'Database')
pbx << emit_group(database_group, "Database", db_files, "Database")

# Services group
svc_files = group_children(file_refs, 'Services')
pbx << emit_group(services_group, "Services", svc_files, "Services")

# ViewModels group
vm_files = group_children(file_refs, 'ViewModels')
pbx << emit_group(viewmodels_group, "ViewModels", vm_files, "ViewModels")

# Views group
views_children = [sidebar_group, overview_group, runs_group, rundetail_group, findings_group, coverage_group, insights_group, integrations_group, settings_group, components_group, projectsetup_group]
pbx << emit_group(views_group, "Views", views_children, "Views")

# View subgroups
[
  [sidebar_group, "Sidebar", "Views/Sidebar"],
  [overview_group, "Overview", "Views/Overview"],
  [runs_group, "Runs", "Views/Runs"],
  [rundetail_group, "RunDetail", "Views/RunDetail"],
  [findings_group, "Findings", "Views/Findings"],
  [coverage_group, "Coverage", "Views/Coverage"],
  [insights_group, "Insights", "Views/Insights"],
  [integrations_group, "Integrations", "Views/Integrations"],
  [settings_group, "Settings", "Views/Settings"],
  [components_group, "Components", "Views/Components"],
  [projectsetup_group, "ProjectSetup", "Views/ProjectSetup"],
].each do |uuid, name, dir|
  children = group_children(file_refs, dir)
  pbx << emit_group(uuid, name, children, name)
end

# Theme group
theme_files = group_children(file_refs, 'Theme')
pbx << emit_group(theme_group, "Theme", theme_files, "Theme")

# Resources group
pbx << emit_group(resources_group, "Resources", [plist_ref, assets_ref], "Resources")

pbx << <<~PBX
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		#{target_uuid} /* OpenClawQA */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = #{target_config_list} /* Build configuration list for PBXNativeTarget "OpenClawQA" */;
			buildPhases = (
				#{sources_phase} /* Sources */,
				#{frameworks_phase} /* Frameworks */,
				#{resources_phase} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = OpenClawQA;
			productName = OpenClawQA;
			productReference = #{product_ref} /* OpenClawQA.app */;
			productType = "com.apple.product-type.application";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		#{project_uuid} /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1620;
				LastUpgradeCheck = 1620;
			};
			buildConfigurationList = #{config_list} /* Build configuration list for PBXProject "OpenClawQA" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = #{root_group};
			productRefGroup = #{products_group} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				#{target_uuid} /* OpenClawQA */,
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		#{resources_phase} /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				#{assets_build} /* Assets.xcassets in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		#{sources_phase} /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
PBX

swift_files.each do |f|
  rel = f.sub("#{source_dir}/", '')
  pbx << "\t\t\t\t#{build_files[rel]} /* #{File.basename(rel)} in Sources */,\n"
end

pbx << <<~PBX
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		#{build_config_debug} /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				MTL_FAST_MATH = YES;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = macosx;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
			};
			name = Debug;
		};
		#{build_config_release} /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				MTL_FAST_MATH = YES;
				SDKROOT = macosx;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
			};
			name = Release;
		};
		#{target_config_debug} /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_ENTITLEMENTS = "";
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = "OpenClawQA/Resources/Info.plist";
				INFOPLIST_KEY_NSHumanReadableCopyright = "Copyright © 2026 OpenClaw. All rights reserved.";
				INFOPLIST_KEY_NSMainStoryboardFile = "";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.openclaw.qa;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
			};
			name = Debug;
		};
		#{target_config_release} /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_ENTITLEMENTS = "";
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = "OpenClawQA/Resources/Info.plist";
				INFOPLIST_KEY_NSHumanReadableCopyright = "Copyright © 2026 OpenClaw. All rights reserved.";
				INFOPLIST_KEY_NSMainStoryboardFile = "";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.openclaw.qa;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		#{config_list} /* Build configuration list for PBXProject "OpenClawQA" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				#{build_config_debug} /* Debug */,
				#{build_config_release} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		#{target_config_list} /* Build configuration list for PBXNativeTarget "OpenClawQA" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				#{target_config_debug} /* Debug */,
				#{target_config_release} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */
	};
	rootObject = #{project_uuid} /* Project object */;
}
PBX

# Write the file
output_dir = File.join(File.dirname(__FILE__), 'OpenClawQA.xcodeproj')
FileUtils.mkdir_p(output_dir)
File.write(File.join(output_dir, 'project.pbxproj'), pbx)

# Create shared scheme
scheme_dir = File.join(output_dir, 'xcshareddata', 'xcschemes')
FileUtils.mkdir_p(scheme_dir)

scheme = <<~SCHEME
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1620"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "#{target_uuid}"
               BuildableName = "OpenClawQA.app"
               BlueprintName = "OpenClawQA"
               ReferencedContainer = "container:OpenClawQA.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "#{target_uuid}"
            BuildableName = "OpenClawQA.app"
            BlueprintName = "OpenClawQA"
            ReferencedContainer = "container:OpenClawQA.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
SCHEME

File.write(File.join(scheme_dir, 'OpenClawQA.xcscheme'), scheme)

puts "✅ Generated OpenClawQA.xcodeproj with #{swift_files.length} Swift files"
puts "   Scheme: OpenClawQA"
puts "   Platform: macOS 14.0+"
puts "   Bundle ID: com.openclaw.qa"
