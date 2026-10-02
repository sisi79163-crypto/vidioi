#!/usr/bin/env python3
"""Generate a dependency-free Xcode project; deterministic IDs, no XcodeGen needed."""
import hashlib
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
def uid(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def quoted(value): return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"') + '"'
def main():
    sources = sorted(str(p.relative_to(ROOT)) for folder in ['App', 'Core', 'Engine'] for p in (ROOT / folder).rglob('*.swift'))
    objects = []
    def add(name, body): objects.append(f'{uid(name)} = {{ {body} }};')
    for source in sources:
        add('ref:' + source, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quoted(source)}; sourceTree = "<group>";')
        add('build:' + source, f'isa = PBXBuildFile; fileRef = {uid("ref:" + source)};')
    add('info', 'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = App/Info.plist; sourceTree = "<group>";')
    add('assets', 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = App/Assets.xcassets; sourceTree = "<group>";')
    add('assets-build', f'isa = PBXBuildFile; fileRef = {uid("assets")};')
    add('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = vidioi.app; sourceTree = BUILT_PRODUCTS_DIR;')
    refs = ', '.join(uid('ref:' + s) for s in sources)
    add('rootgroup', f'isa = PBXGroup; children = ({refs}, {uid("info")}, {uid("assets")}, {uid("products")}); sourceTree = "<group>";')
    add('products', f'isa = PBXGroup; children = ({uid("product")}); name = Products; sourceTree = "<group>";')
    builds = ', '.join(uid('build:' + s) for s in sources)
    add('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({builds}); runOnlyForDeploymentPostprocessing = 0;')
    add('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({uid("assets-build")}); runOnlyForDeploymentPostprocessing = 0;')
    add('frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    for config in ['Debug', 'Release']:
        project_settings = {
            'CLANG_ENABLE_MODULES': 'YES', 'CLANG_ENABLE_OBJC_ARC': 'YES',
            'SDKROOT': 'iphoneos', 'IPHONEOS_DEPLOYMENT_TARGET': '17.0', 'SWIFT_VERSION': '5.0',
            'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if config == 'Debug' else '-O',
            'DEBUG_INFORMATION_FORMAT': 'dwarf' if config == 'Debug' else 'dwarf-with-dsym',
            'ENABLE_TESTABILITY': 'YES' if config == 'Debug' else 'NO',
        }
        app_settings = {
            'PRODUCT_NAME': 'vidioi', 'PRODUCT_BUNDLE_IDENTIFIER': 'com.mostafa.vidioi',
            'INFOPLIST_FILE': 'App/Info.plist', 'GENERATE_INFOPLIST_FILE': 'NO',
            'TARGETED_DEVICE_FAMILY': '1,2', 'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator',
            'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon', 'CODE_SIGN_STYLE': 'Automatic',
            'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks',
            'SWIFT_EMIT_LOC_STRINGS': 'YES', 'CURRENT_PROJECT_VERSION': '2', 'MARKETING_VERSION': '0.2.0'
        }
        for prefix, settings in [('project', project_settings), ('app', app_settings)]:
            body = ' '.join(f'{key} = {quoted(value)};' for key, value in settings.items())
            add(prefix + config, f'isa = XCBuildConfiguration; buildSettings = {{ {body} }}; name = {config};')
    for prefix in ['project', 'app']:
        add(prefix + 'configs', f'isa = XCConfigurationList; buildConfigurations = ({uid(prefix + "Debug")}, {uid(prefix + "Release")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    add('target', f'isa = PBXNativeTarget; buildConfigurationList = {uid("appconfigs")}; buildPhases = ({uid("sources")}, {uid("frameworks")}, {uid("resources")}); buildRules = (); dependencies = (); name = vidioi; productName = vidioi; productReference = {uid("product")}; productType = "com.apple.product-type.application";')
    add('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; }}; buildConfigurationList = {uid("projectconfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, ar, Base); mainGroup = {uid("rootgroup")}; productRefGroup = {uid("products")}; projectDirPath = ""; projectRoot = ""; targets = ({uid("target")});')
    directory = ROOT / 'vidioi.xcodeproj'; directory.mkdir(exist_ok=True)
    (directory / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {uid("project")}; }}\n')
    scheme = ET.Element('Scheme', LastUpgradeVersion='1600', version='1.7')
    build = ET.SubElement(scheme, 'BuildAction', parallelizeBuildables='YES', buildImplicitDependencies='YES')
    entries = ET.SubElement(build, 'BuildActionEntries')
    entry = ET.SubElement(entries, 'BuildActionEntry', buildForTesting='YES', buildForRunning='YES', buildForProfiling='YES', buildForArchiving='YES', buildForAnalyzing='YES')
    reference = dict(BuildableIdentifier='primary', BlueprintIdentifier=uid('target'), BuildableName='vidioi.app', BlueprintName='vidioi', ReferencedContainer='container:vidioi.xcodeproj')
    ET.SubElement(entry, 'BuildableReference', **reference)
    ET.SubElement(scheme, 'TestAction', buildConfiguration='Debug', selectedDebuggerIdentifier='Xcode.DebuggerFoundation.Debugger.LLDB', selectedLauncherIdentifier='Xcode.IDEFoundation.Launcher.LLDB', shouldUseLaunchSchemeArgsEnv='YES')
    launch = ET.SubElement(scheme, 'LaunchAction', buildConfiguration='Debug', selectedDebuggerIdentifier='Xcode.DebuggerFoundation.Debugger.LLDB', selectedLauncherIdentifier='Xcode.IDEFoundation.Launcher.LLDB', launchStyle='0', useCustomWorkingDirectory='NO', ignoresPersistentStateOnLaunch='NO', debugDocumentVersioning='YES', debugServiceExtension='internal', allowLocationSimulation='YES')
    runnable = ET.SubElement(launch, 'BuildableProductRunnable', runnableDebuggingMode='0'); ET.SubElement(runnable, 'BuildableReference', **reference)
    profile = ET.SubElement(scheme, 'ProfileAction', buildConfiguration='Release', shouldUseLaunchSchemeArgsEnv='YES', savedToolIdentifier='', useCustomWorkingDirectory='NO', debugDocumentVersioning='YES')
    runnable = ET.SubElement(profile, 'BuildableProductRunnable', runnableDebuggingMode='0'); ET.SubElement(runnable, 'BuildableReference', **reference)
    ET.SubElement(scheme, 'AnalyzeAction', buildConfiguration='Debug')
    ET.SubElement(scheme, 'ArchiveAction', buildConfiguration='Release', revealArchiveInOrganizer='YES')
    schemes = directory / 'xcshareddata/xcschemes'; schemes.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(scheme).write(schemes / 'vidioi.xcscheme', encoding='utf-8', xml_declaration=True)
    print(f'Generated vidioi.xcodeproj with {len(sources)} Swift files')
if __name__ == '__main__': main()
