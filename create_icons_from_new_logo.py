#!/usr/bin/env python3
"""
Create all app icons from the new SpotWatt_Logo_neu.png
This new logo is perfect for app icons - no text, clean symbol design
"""

from PIL import Image, ImageOps
from pathlib import Path

def create_app_icon_from_new_logo(logo_img, target_size, fill_ratio=0.90):
    """
    Create an app icon from the new logo, optimized for maximum visibility
    """
    # Create square canvas with transparent background
    canvas = Image.new('RGBA', (target_size, target_size), (0, 0, 0, 0))
    
    # Calculate size to fill the specified ratio of the canvas
    max_logo_size = int(target_size * fill_ratio)
    
    # Get logo dimensions
    logo_width, logo_height = logo_img.size
    
    # Scale logo proportionally to fit within max_logo_size
    if logo_width > logo_height:
        new_width = max_logo_size
        new_height = int((logo_height * max_logo_size) / logo_width)
    else:
        new_height = max_logo_size
        new_width = int((logo_width * max_logo_size) / logo_height)
    
    # Resize logo with high quality
    resized_logo = logo_img.resize((new_width, new_height), Image.Resampling.LANCZOS)
    
    # Center the logo on canvas
    x_offset = (target_size - new_width) // 2
    y_offset = (target_size - new_height) // 2
    
    # Paste with proper alpha handling
    if resized_logo.mode == 'RGBA':
        canvas.paste(resized_logo, (x_offset, y_offset), resized_logo)
    else:
        canvas.paste(resized_logo, (x_offset, y_offset))
    
    return canvas

def create_all_icons_from_new_logo():
    """Create all required icon sizes from the new logo"""
    project_root = Path("D:/SpottWatt")
    new_logo_path = project_root / "SpotWatt_Logo_neu.png"
    
    if not new_logo_path.exists():
        print(f"Error: {new_logo_path} not found!")
        return
    
    print(f"Loading new logo: {new_logo_path}")
    new_logo = Image.open(new_logo_path)
    
    # Convert to RGBA if needed
    if new_logo.mode != 'RGBA':
        new_logo = new_logo.convert('RGBA')
    
    print(f"New logo size: {new_logo.size}")
    
    # Android icons - aggressive fill ratios for maximum impact
    android_sizes = {
        'mipmap-mdpi': 48,
        'mipmap-hdpi': 72,
        'mipmap-xhdpi': 96, 
        'mipmap-xxhdpi': 144,
        'mipmap-xxxhdpi': 192
    }
    
    print("\nCreating Android app icons from new logo...")
    android_res_path = project_root / 'android' / 'app' / 'src' / 'main' / 'res'
    
    for density, size in android_sizes.items():
        icon_dir = android_res_path / density
        icon_file = icon_dir / 'ic_launcher.png'
        
        # Use high fill ratio - the new logo is designed for this
        fill_ratio = 0.92 if size >= 144 else 0.88  # Larger fill for bigger icons
        
        icon_img = create_app_icon_from_new_logo(new_logo, size, fill_ratio)
        icon_img.save(str(icon_file), 'PNG', optimize=True)
        
        file_size = icon_file.stat().st_size
        print(f"Created {density}/ic_launcher.png ({size}x{size}) - {file_size} bytes")
    
    # iOS icons
    ios_sizes = {
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
    
    print("\nCreating iOS app icons from new logo...")
    ios_icon_path = project_root / 'ios' / 'Runner' / 'Assets.xcassets' / 'AppIcon.appiconset'
    
    for filename, size in ios_sizes.items():
        icon_file = ios_icon_path / filename
        
        # Size-optimized fill ratios
        if size <= 29:
            fill_ratio = 0.82  # Conservative for tiny icons
        elif size <= 60:
            fill_ratio = 0.86  # Medium for small icons  
        elif size >= 1024:
            fill_ratio = 0.95  # Maximum for App Store icon
        else:
            fill_ratio = 0.90  # Standard for most sizes
        
        icon_img = create_app_icon_from_new_logo(new_logo, size, fill_ratio)
        icon_img.save(str(icon_file), 'PNG', optimize=True)
        
        file_size = icon_file.stat().st_size
        print(f"Created {filename} ({size}x{size}) - {file_size} bytes")
    
    # Web icons - different strategies for different uses
    web_sizes = {
        'Icon-192.png': (192, 0.90),          # Standard web icon
        'Icon-512.png': (512, 0.88),          # Larger web icon, slightly more padding
        'Icon-maskable-192.png': (192, 0.75), # Extra padding for system masking
        'Icon-maskable-512.png': (512, 0.70), # Extra padding for system masking
    }
    
    print("\nCreating web icons from new logo...")
    web_icon_path = project_root / 'web' / 'icons'
    
    for filename, (size, fill_ratio) in web_sizes.items():
        icon_file = web_icon_path / filename
        
        icon_img = create_app_icon_from_new_logo(new_logo, size, fill_ratio)
        icon_img.save(str(icon_file), 'PNG', optimize=True)
        
        file_size = icon_file.stat().st_size
        maskable_note = " (maskable)" if "maskable" in filename else ""
        print(f"Created {filename} ({size}x{size}){maskable_note} - {file_size} bytes")
    
    # Website favicons - all sizes use the new logo now
    favicon_sizes = [16, 32, 48, 64]
    
    print("\nCreating website favicons from new logo...")
    docs_path = project_root / 'docs'
    
    favicon_images = []
    for size in favicon_sizes:
        favicon_file = docs_path / f'favicon-{size}x{size}.png'
        
        # Favicon-specific fill ratios for optimal visibility
        if size <= 16:
            fill_ratio = 0.95  # Maximum fill for tiny favicons
        elif size <= 32:
            fill_ratio = 0.92  # High fill for small favicons
        else:
            fill_ratio = 0.88  # Standard for larger favicons
        
        icon_img = create_app_icon_from_new_logo(new_logo, size, fill_ratio)
        icon_img.save(str(favicon_file), 'PNG', optimize=True)
        favicon_images.append(icon_img)
        
        file_size = favicon_file.stat().st_size
        print(f"Created favicon-{size}x{size}.png - {file_size} bytes")
    
    # Create multi-size ICO file
    if favicon_images:
        favicon_ico = docs_path / 'favicon.ico'
        favicon_images[0].save(
            str(favicon_ico),
            format='ICO',
            sizes=[(img.width, img.height) for img in favicon_images]
        )
        
        ico_size = favicon_ico.stat().st_size
        print(f"Created favicon.ico with {len(favicon_images)} sizes - {ico_size} bytes")
        
        # Create standard favicon.png (32x32)
        favicon_png = docs_path / 'favicon.png'
        if len(favicon_images) >= 2:
            favicon_images[1].save(str(favicon_png), 'PNG')
            png_size = favicon_png.stat().st_size
            print(f"Created favicon.png (32x32) - {png_size} bytes")
    
    # Save the new logo to assets for reference
    assets_path = project_root / 'assets' / 'icons'
    assets_path.mkdir(parents=True, exist_ok=True)
    
    new_logo_copy = assets_path / 'spotwatt_logo_final.png'
    new_logo.save(str(new_logo_copy), 'PNG')
    print(f"\nSaved final logo to: {new_logo_copy}")
    
    print(f"\nNew logo implementation complete!")
    print(f"Original logo size: {new_logo.size[0]}x{new_logo.size[1]}")
    print(f"Perfect for app icons - no text, clean design")
    print(f"Fill ratios: 82-95% (size-optimized)")
    print(f"Created {len(android_sizes)} Android icons")
    print(f"Created {len(ios_sizes)} iOS icons")
    print(f"Created {len(web_sizes)} web icons")
    print(f"Created {len(favicon_sizes)} favicon sizes")
    print(f"\nReady for app store submission!")

if __name__ == "__main__":
    create_all_icons_from_new_logo()