#!/usr/bin/env python3
"""Generate a deterministic Xcode project using only Python's standard library.

Run from any directory. The shared scheme builds the app and runs core XCTest.
Default signing is local ad hoc. Override CODE_SIGN_IDENTITY and DEVELOPMENT_TEAM
in Xcode or xcodebuild for Developer ID distribution; notarization is separate.
"""
from pathlib import Path
import hashlib
import json
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "MediaInfoQuickLook.xcodeproj"
objects = {}


def ident(label):
    return hashlib.sha256(label.encode()).hexdigest()[:24].upper()


def add(label, isa, **properties):
    key = ident(label)
    objects[key] = {"isa": isa, **properties}
    return key


def encode(value, depth=0):
    pad = "\t" * depth
    if isinstance(value, dict):
        return "{\n" + "".join(f"{pad}\t{json.dumps(k)} = {encode(v, depth + 1)};\n" for k, v in value.items()) + pad + "}"
    if isinstance(value, list):
        return "(\n" + "".join(f"{pad}\t{encode(v, depth + 1)},\n" for v in value) + pad + ")"
    return json.dumps(str(value), ensure_ascii=False)


def source_group(name, directory):
    references = []
    builds = []
    for path in sorted((ROOT / directory).glob("*.swift")):
        rel = path.relative_to(ROOT).as_posix()
        reference = add("file:" + rel, "PBXFileReference", lastKnownFileType="sourcecode.swift", path=rel, sourceTree="SOURCE_ROOT")
        references.append(reference)
        builds.append(add("build:" + rel, "PBXBuildFile", fileRef=reference))
    return add("group:" + name, "PBXGroup", children=references, name=name, sourceTree="<group>"), builds


def configurations(name, settings):
    configs = []
    for mode in ("Debug", "Release"):
        merged = dict(settings)
        if name == "Project":
            merged.update(SWIFT_OPTIMIZATION_LEVEL="-Onone" if mode == "Debug" else "-O",
                          DEBUG_INFORMATION_FORMAT="dwarf" if mode == "Debug" else "dwarf-with-dsym",
                          ENABLE_TESTABILITY="YES" if mode == "Debug" else "NO",
                          SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG" if mode == "Debug" else "",
                          ONLY_ACTIVE_ARCH="YES" if mode == "Debug" else "NO")
        configs.append(add(f"config:{name}:{mode}", "XCBuildConfiguration", buildSettings=merged, name=mode))
    return add("configs:" + name, "XCConfigurationList", buildConfigurations=configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")


groups = []
builds_by_target = {}
for name, directory in (("MediaInfoCore", "Sources/MediaInfoCore"), ("MediaInfoQuickLook", "Sources/MediaInfoQuickLook"), ("MediaInfoCoreTests", "Tests/MediaInfoCoreTests")):
    group, builds = source_group(name, directory)
    groups.append(group)
    builds_by_target[name] = builds

resource_refs = []
for filename in ("Info.plist", "MediaInfoQuickLook.entitlements"):
    resource_refs.append(add("resource:" + filename, "PBXFileReference", lastKnownFileType="text.plist.xml", path="Resources/" + filename, sourceTree="SOURCE_ROOT"))
groups.append(add("group:Resources", "PBXGroup", children=resource_refs, name="Resources", sourceTree="<group>"))

products = {}
for name, extension, filetype in (("MediaInfoCore", "framework", "wrapper.framework"), ("MediaInfoQuickLook", "app", "wrapper.application"), ("MediaInfoCoreTests", "xctest", "wrapper.cfbundle")):
    products[name] = add("product:" + name, "PBXFileReference", explicitFileType=filetype, includeInIndex=0, path=f"{name}.{extension}", sourceTree="BUILT_PRODUCTS_DIR")
groups.append(add("group:Products", "PBXGroup", children=list(products.values()), name="Products", sourceTree="<group>"))
main_group = add("group:Main", "PBXGroup", children=groups, sourceTree="<group>")

project_id = ident("project")
core_id = ident("target:MediaInfoCore")
target_ids = []
for name in builds_by_target:
    source_phase = add("sources:" + name, "PBXSourcesBuildPhase", buildActionMask=2147483647, files=builds_by_target[name], runOnlyForDeploymentPostprocessing=0)
    framework_builds = []
    dependencies = []
    if name != "MediaInfoCore":
        framework_builds.append(add("link:core:" + name, "PBXBuildFile", fileRef=products["MediaInfoCore"]))
        proxy = add("proxy:core:" + name, "PBXContainerItemProxy", containerPortal=project_id, proxyType=1, remoteGlobalIDString=core_id, remoteInfo="MediaInfoCore")
        dependencies.append(add("dependency:core:" + name, "PBXTargetDependency", target=core_id, targetProxy=proxy))
    framework_phase = add("frameworks:" + name, "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=framework_builds, runOnlyForDeploymentPostprocessing=0)
    phases = [source_phase, framework_phase]
    settings = {"PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "com.hemafri." + name,
                "CODE_SIGN_STYLE": "Manual", "CODE_SIGN_IDENTITY": "-", "ENABLE_APP_SANDBOX": "NO"}
    if name == "MediaInfoQuickLook":
        product_type = "com.apple.product-type.application"
        settings.update(INFOPLIST_FILE="Resources/Info.plist", GENERATE_INFOPLIST_FILE="NO",
                        CODE_SIGN_ENTITLEMENTS="Resources/MediaInfoQuickLook.entitlements", ENABLE_HARDENED_RUNTIME="YES",
                        LD_RUNPATH_SEARCH_PATHS=["$(inherited)", "@executable_path/../Frameworks"])
        embed = add("embed:core", "PBXBuildFile", fileRef=products["MediaInfoCore"], settings={"ATTRIBUTES": ["CodeSignOnCopy", "RemoveHeadersOnCopy"]})
        phases.append(add("phase:embed", "PBXCopyFilesBuildPhase", buildActionMask=2147483647, dstPath="", dstSubfolderSpec=10, files=[embed], name="Embed Frameworks", runOnlyForDeploymentPostprocessing=0))
    elif name == "MediaInfoCore":
        product_type = "com.apple.product-type.framework"
        settings.update(GENERATE_INFOPLIST_FILE="YES", DEFINES_MODULE="YES", SKIP_INSTALL="YES",
                        DYLIB_INSTALL_NAME_BASE="@rpath", DYLIB_COMPATIBILITY_VERSION="1", DYLIB_CURRENT_VERSION="1",
                        ENABLE_HARDENED_RUNTIME="YES")
    else:
        product_type = "com.apple.product-type.bundle.unit-test"
        settings.update(GENERATE_INFOPLIST_FILE="YES", SKIP_INSTALL="YES",
                        LD_RUNPATH_SEARCH_PATHS=["$(inherited)", "@loader_path/../Frameworks", "@executable_path/../Frameworks", "$(BUILT_PRODUCTS_DIR)"],
                        ENABLE_HARDENED_RUNTIME="NO")
    config_list = configurations(name, settings)
    target_ids.append(add("target:" + name, "PBXNativeTarget", buildConfigurationList=config_list, buildPhases=phases, buildRules=[], dependencies=dependencies, name=name, productName=name, productReference=products[name], productType=product_type))

project_configs = configurations("Project", {"SDKROOT": "macosx", "MACOSX_DEPLOYMENT_TARGET": "13.0", "SWIFT_VERSION": "5.0", "CLANG_ENABLE_MODULES": "YES", "COMBINE_HIDPI_IMAGES": "YES", "SUPPORTED_PLATFORMS": "macosx"})
add("project", "PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "1500"}, buildConfigurationList=project_configs, compatibilityVersion="Xcode 14.0", developmentRegion="en", hasScannedForEncodings=0, knownRegions=["en", "Base"], mainGroup=main_group, productRefGroup=ident("group:Products"), projectDirPath="", projectRoot="", targets=target_ids)
PROJECT.mkdir(exist_ok=True)
(PROJECT / "project.pbxproj").write_text("// !$*UTF8*$!\n" + encode({"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": dict(sorted(objects.items())), "rootObject": project_id}) + "\n")

scheme = ET.Element("Scheme", LastUpgradeVersion="1500", version="1.3")
build_action = ET.SubElement(scheme, "BuildAction", parallelizeBuildables="YES", buildImplicitDependencies="YES")
entries = ET.SubElement(build_action, "BuildActionEntries")


def reference(parent, name, extension):
    return ET.SubElement(parent, "BuildableReference", BuildableIdentifier="primary", BlueprintIdentifier=ident("target:" + name), BuildableName=name + "." + extension, BlueprintName=name, ReferencedContainer="container:MediaInfoQuickLook.xcodeproj")


for name, extension in (("MediaInfoQuickLook", "app"), ("MediaInfoCoreTests", "xctest")):
    app = name == "MediaInfoQuickLook"
    entry = ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning="YES" if app else "NO", buildForProfiling="YES" if app else "NO", buildForArchiving="YES" if app else "NO", buildForAnalyzing="YES")
    reference(entry, name, extension)
test = ET.SubElement(scheme, "TestAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", shouldUseLaunchSchemeArgsEnv="YES")
testables = ET.SubElement(test, "Testables")
reference(ET.SubElement(testables, "TestableReference", skipped="NO"), "MediaInfoCoreTests", "xctest")
launch = ET.SubElement(scheme, "LaunchAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", launchStyle="0", useCustomWorkingDirectory="NO", ignoresPersistentStateOnLaunch="NO", debugDocumentVersioning="YES", allowLocationSimulation="YES")
reference(ET.SubElement(launch, "BuildableProductRunnable", runnableDebuggingMode="0"), "MediaInfoQuickLook", "app")
profile = ET.SubElement(scheme, "ProfileAction", buildConfiguration="Release", shouldUseLaunchSchemeArgsEnv="YES", savedToolIdentifier="", useCustomWorkingDirectory="NO", debugDocumentVersioning="YES")
reference(ET.SubElement(profile, "BuildableProductRunnable", runnableDebuggingMode="0"), "MediaInfoQuickLook", "app")
ET.SubElement(scheme, "AnalyzeAction", buildConfiguration="Debug")
ET.SubElement(scheme, "ArchiveAction", buildConfiguration="Release", revealArchiveInOrganizer="YES")
ET.indent(scheme)
scheme_path = PROJECT / "xcshareddata" / "xcschemes" / "MediaInfoQuickLook.xcscheme"
scheme_path.parent.mkdir(parents=True, exist_ok=True)
ET.ElementTree(scheme).write(scheme_path, encoding="UTF-8", xml_declaration=True)
print(f"Generated {PROJECT} with app, core framework, and XCTest targets.")
