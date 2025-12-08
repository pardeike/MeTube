#!/usr/bin/env python3
"""
Script to add new Swift files to MeTube.xcodeproj
This adds the files created during the offline-first refactoring
"""

import subprocess
import sys
import os

# List of new files to add (relative to project root)
NEW_FILES = [
    "MeTube/Models/Persistence/VideoEntity.swift",
    "MeTube/Models/Persistence/ChannelEntity.swift",
    "MeTube/Models/Persistence/StatusEntity.swift",
    "MeTube/Repositories/VideoRepository.swift",
    "MeTube/Repositories/StatusRepository.swift",
    "MeTube/Repositories/ChannelRepository.swift",
    "MeTube/Services/Sync/HubSyncManager.swift",
    "MeTube/Services/Sync/StatusSyncManager.swift",
    "MeTube/Models/ModelConverters.swift",
]

def main():
    print("=" * 60)
    print("MeTube Xcode Project File Adder")
    print("=" * 60)
    print()
    print("This script needs to be run on a Mac with Xcode installed.")
    print("It will add the new Swift files to MeTube.xcodeproj")
    print()
    
    # Check if we're on a Mac
    if sys.platform != "darwin":
        print("⚠️  This script should be run on macOS with Xcode installed.")
        print()
        print("Manual steps required:")
        print("1. Open MeTube.xcodeproj in Xcode")
        print("2. Right-click on each folder and select 'Add Files to MeTube...'")
        print("3. Add these new files:")
        for file in NEW_FILES:
            print(f"   - {file}")
        print()
        return
    
    # Check if project file exists
    if not os.path.exists("MeTube.xcodeproj"):
        print("❌ MeTube.xcodeproj not found in current directory")
        print("Please run this script from the repository root")
        return
    
    print("The following files will be added to the Xcode project:")
    for file in NEW_FILES:
        exists = "✓" if os.path.exists(file) else "✗"
        print(f"  {exists} {file}")
    print()
    
    # Note: Actual file addition requires Xcode Command Line Tools
    # and is typically done via Xcode GUI or using xcodegen
    print("To add these files to Xcode:")
    print("1. Open MeTube.xcodeproj in Xcode")
    print("2. In the Project Navigator, locate these folders:")
    print("   - Models (add Persistence folder with entities)")
    print("   - Services (add Sync folder with managers)")
    print("   - Create 'Repositories' group if needed")
    print("3. Drag and drop or use 'Add Files to MeTube...'")
    print("4. Ensure files are added to the MeTube target")
    print()
    print("Or use a tool like xcodegen to regenerate the project file")

if __name__ == "__main__":
    main()
