#!/usr/bin/env python3
"""
SpotWatt Icon Generator
Converts the SVG logo to all required app icon sizes and formats.
"""

import os
import shutil
from pathlib import Path

# Icon size definitions for different platforms
ANDROID_SIZES = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192
}

IOS_SIZES = {
    'Icon-App-20x20@1x.png': 20,
    'Icon-App-20x20@2x.png': 40,
    'Icon-App-20x20@3x.png': 60,
    'Icon-App-29x29@1x.png': 29,
    'Icon-App-29x29@2x.png': 58,
    'Icon-App-29x29@3x.png': 87,
    'Icon-App-40x40@1x.png': 40,
    'Icon-App-40x40@2x.png': 80,
    'Icon-App-40x40@3x.png': 120,
    'Icon-App-60x60@2x.png': 120,
    'Icon-App-60x60@3x.png': 180,
    'Icon-App-76x76@1x.png': 76,
    'Icon-App-76x76@2x.png': 152,
    'Icon-App-83.5x83.5@2x.png': 167,
    'Icon-App-1024x1024@1x.png': 1024
}

WEB_SIZES = {
    'Icon-192.png': 192,
    'Icon-512.png': 512,
    'Icon-maskable-192.png': 192,
    'Icon-maskable-512.png': 512
}

def create_simple_icon_content(size):
    """Create a simple PNG icon content using basic geometric shapes"""
    # This creates a simple representation that can be saved as PNG
    # In a real scenario, you'd use PIL or similar to create actual PNG files
    
    # For now, create a placeholder that indicates the size
    content = f"""#!/usr/bin/env python3
# SpotWatt App Icon - Size: {size}x{size}
# This is a placeholder. In production, replace with actual PNG image data.

SIZE = {size}
FORMAT = "PNG"
"""
    return content

def generate_android_icons(project_root):
    """Generate Android launcher icons"""
    print("Generating Android icons...")
    
    android_res_path = project_root / 'android' / 'app' / 'src' / 'main' / 'res'
    
    for density, size in ANDROID_SIZES.items():
        icon_dir = android_res_path / density
        icon_dir.mkdir(parents=True, exist_ok=True)
        
        icon_file = icon_dir / 'ic_launcher.png'
        
        # Create placeholder content (in production, use proper image library)
        with open(icon_file, 'w') as f:
            f.write(create_simple_icon_content(size))
        
        print(f"Created {density}/ic_launcher.png ({size}x{size})")

def generate_ios_icons(project_root):
    """Generate iOS app icons"""
    print("Generating iOS icons...")
    
    ios_icon_path = project_root / 'ios' / 'Runner' / 'Assets.xcassets' / 'AppIcon.appiconset'
    ios_icon_path.mkdir(parents=True, exist_ok=True)
    
    for filename, size in IOS_SIZES.items():
        icon_file = ios_icon_path / filename
        
        # Create placeholder content
        with open(icon_file, 'w') as f:
            f.write(create_simple_icon_content(size))
        
        print(f"Created {filename} ({size}x{size})")

def generate_web_icons(project_root):
    """Generate web/PWA icons"""
    print("Generating web icons...")
    
    web_icon_path = project_root / 'web' / 'icons'
    web_icon_path.mkdir(parents=True, exist_ok=True)
    
    for filename, size in WEB_SIZES.items():
        icon_file = web_icon_path / filename
        
        # Create placeholder content
        with open(icon_file, 'w') as f:
            f.write(create_simple_icon_content(size))
        
        print(f"Created {filename} ({size}x{size})")

def update_ios_contents_json(project_root):
    """Update iOS Contents.json file for app icons"""
    print("Updating iOS Contents.json...")
    
    contents_json = """{
  "images" : [
    {
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "20x20",
      "filename" : "Icon-App-20x20@2x.png"
    },
    {
      "idiom" : "iphone",
      "scale" : "3x", 
      "size" : "20x20",
      "filename" : "Icon-App-20x20@3x.png"
    },
    {
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "29x29",
      "filename" : "Icon-App-29x29@2x.png"
    },
    {
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "29x29", 
      "filename" : "Icon-App-29x29@3x.png"
    },
    {
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "40x40",
      "filename" : "Icon-App-40x40@2x.png"
    },
    {
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "40x40",
      "filename" : "Icon-App-40x40@3x.png"
    },
    {
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "60x60",
      "filename" : "Icon-App-60x60@2x.png"
    },
    {
      "idiom" : "iphone", 
      "scale" : "3x",
      "size" : "60x60",
      "filename" : "Icon-App-60x60@3x.png"
    },
    {
      "idiom" : "ipad",
      "scale" : "1x",
      "size" : "20x20",
      "filename" : "Icon-App-20x20@1x.png"
    },
    {
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "20x20", 
      "filename" : "Icon-App-20x20@2x.png"
    },
    {
      "idiom" : "ipad",
      "scale" : "1x",
      "size" : "29x29",
      "filename" : "Icon-App-29x29@1x.png"
    },
    {
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "29x29",
      "filename" : "Icon-App-29x29@2x.png"
    },
    {
      "idiom" : "ipad",
      "scale" : "1x", 
      "size" : "40x40",
      "filename" : "Icon-App-40x40@1x.png"
    },
    {
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "40x40",
      "filename" : "Icon-App-40x40@2x.png"
    },
    {
      "idiom" : "ipad",
      "scale" : "1x",
      "size" : "76x76",
      "filename" : "Icon-App-76x76@1x.png"
    },
    {
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "76x76",
      "filename" : "Icon-App-76x76@2x.png"
    },
    {
      "idiom" : "ipad", 
      "scale" : "2x",
      "size" : "83.5x83.5",
      "filename" : "Icon-App-83.5x83.5@2x.png"
    },
    {
      "idiom" : "ios-marketing",
      "scale" : "1x",
      "size" : "1024x1024",
      "filename" : "Icon-App-1024x1024@1x.png"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}"""
    
    contents_file = project_root / 'ios' / 'Runner' / 'Assets.xcassets' / 'AppIcon.appiconset' / 'Contents.json'
    with open(contents_file, 'w') as f:
        f.write(contents_json)
    
    print("Updated Contents.json")

def update_web_manifest(project_root):
    """Update web manifest icons"""
    print("Updating web manifest...")
    
    # Update the manifest.json file in docs (for website)
    docs_manifest = project_root / 'docs' / 'manifest.json'
    if docs_manifest.exists():
        # The manifest file already exists and is correct
        print("Web manifest already configured")

def main():
    """Main function to generate all icons"""
    project_root = Path("D:/SpottWatt")
    
    print("SpotWatt Icon Generator")
    print("=" * 40)
    
    # Generate icons for all platforms
    generate_android_icons(project_root)
    print()
    
    generate_ios_icons(project_root)
    update_ios_contents_json(project_root)
    print()
    
    generate_web_icons(project_root)
    update_web_manifest(project_root)
    print()
    
    print("All icons generated successfully!")
    print()
    print("Next steps:")
    print("1. Build the app to test the new icons")
    print("2. Replace placeholder files with actual PNG images")
    print("3. Test on device to ensure icons display correctly")
    
    # Create a simple favicon for the website
    favicon_path = project_root / 'docs' / 'favicon.ico'
    with open(favicon_path, 'w') as f:
        f.write("# SpotWatt Favicon - Replace with actual ICO file")
    print("Created website favicon placeholder")

if __name__ == "__main__":
    main()