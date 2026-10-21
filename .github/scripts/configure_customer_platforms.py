#!/usr/bin/env python3
"""Apply reproducible settings to Flutter-generated Android/iOS folders."""
from pathlib import Path
import re

root = Path.cwd()
manifest = root / "android/app/src/main/AndroidManifest.xml"
gradle_kts = root / "android/app/build.gradle.kts"
info_plist = root / "ios/Runner/Info.plist"

if not manifest.exists() or not gradle_kts.exists() or not info_plist.exists():
    raise SystemExit("Expected generated Android and iOS files were not found.")

manifest_text = manifest.read_text(encoding="utf-8")
permissions = [
    '    <uses-permission android:name="android.permission.INTERNET" />',
    '    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />',
    '    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />',
]
for permission in permissions:
    if permission not in manifest_text:
        manifest_text = manifest_text.replace("<application", permission + "\n    <application", 1)

if 'android:scheme="com.alteo.customer"' not in manifest_text:
    activity = re.search(r'(<activity\b[^>]*android:name="[^"]*MainActivity"[^>]*>)(.*?)(</activity>)', manifest_text, re.S)
    if not activity:
        raise SystemExit("Could not locate MainActivity in generated AndroidManifest.xml.")
    deep_link = '''
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="com.alteo.customer" android:host="login-callback" />
            </intent-filter>
'''
    manifest_text = manifest_text[:activity.end(2)] + deep_link + manifest_text[activity.end(2):]
manifest_text = re.sub(r'android:label="[^"]*"', 'android:label="Alteo"', manifest_text, count=1)
manifest.write_text(manifest_text, encoding="utf-8")

gradle = gradle_kts.read_text(encoding="utf-8")
gradle = re.sub(r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 24', gradle)
gradle = re.sub(r'targetSdk\s*=\s*flutter\.targetSdkVersion', 'targetSdk = 36', gradle)
gradle_kts.write_text(gradle, encoding="utf-8")

plist_text = info_plist.read_text(encoding="utf-8")
plist_text = re.sub(
    r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)',
    r'\1Alteo\2',
    plist_text,
    count=1,
)
if "com.alteo.customer" not in plist_text:
    entry = '''
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>com.alteo.customer</string>
            </array>
        </dict>
    </array>
'''
    insert_at = plist_text.rfind("</dict>")
    if insert_at < 0:
        raise SystemExit("Could not find the top-level Info.plist dictionary end.")
    plist_text = plist_text[:insert_at] + entry + plist_text[insert_at:]
if "NSLocationWhenInUseUsageDescription" not in plist_text:
    entry = '''
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>Alteo uses your location to show service availability and help set pickup or delivery addresses when you choose to share it.</string>
'''
    insert_at = plist_text.rfind("</dict>")
    plist_text = plist_text[:insert_at] + entry + plist_text[insert_at:]
info_plist.write_text(plist_text, encoding="utf-8")

print("Generated Android/iOS settings applied (API 36, app display name and OAuth deep link).")
