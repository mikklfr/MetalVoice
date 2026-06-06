#!/bin/bash

# MetalVoice Build Script
# Builds the MetalVoice GUI application and MetalVoiceCLI
# Requirements: macOS with Apple Silicon (M1, M2, M3, or newer), Swift 5.9+

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
BUILD_TYPE="${1:-release}"  # Default to release; can pass 'debug' as argument
BUILD_DIR=".build/$BUILD_TYPE"
APP_NAME="MetalVoice"
APP_BUNDLE="$APP_NAME.app"

# Helper functions
print_header() {
    echo -e "\n${GREEN}=== $1 ===${NC}\n"
}

print_error() {
    echo -e "${RED}❌ Error: $1${NC}"
    exit 1
}

print_warning() {
    echo -e "${YELLOW}⚠️  Warning: $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# Check requirements
check_requirements() {
    print_header "Checking Requirements"
    
    # Check for Swift
    if ! command -v swift &> /dev/null; then
        print_error "Swift is not installed. Please install Xcode Command Line Tools: xcode-select --install"
    fi
    
    # Check Swift version
    SWIFT_VERSION=$(swift --version | awk '{print $4}')
    print_success "Swift $SWIFT_VERSION found"
    
    # Check for macOS
    if [[ "$OSTYPE" != "darwin"* ]]; then
        print_error "This project can only be built on macOS. You are running on $OSTYPE. Please build on a Mac with Apple Silicon (M1, M2, M3, or newer)."
    fi
    
    OS_VERSION=$(sw_vers -productVersion)
    MAJOR_VERSION=$(echo $OS_VERSION | cut -d. -f1)
    if [ "$MAJOR_VERSION" -lt 13 ]; then
        print_error "This project requires macOS 13 or later. You have macOS $OS_VERSION"
    fi
    print_success "macOS $OS_VERSION (13.0+ required)"
    
    # Check for Apple Silicon
    ARCH=$(uname -m)
    if [[ "$ARCH" != "arm64" ]]; then
        print_error "This project requires Apple Silicon (M1, M2, M3, or newer). You are running on $ARCH architecture, which is not supported."
    fi
    print_success "Apple Silicon detected ($ARCH)"
}

# Clean build artifacts
clean() {
    print_header "Cleaning Previous Builds"
    rm -rf .build
    rm -rf "$APP_BUNDLE"
    rm -f MetalVoiceCLI
    print_success "Cleaned build artifacts"
}

# Build the Swift package
build_package() {
    print_header "Building Swift Package ($BUILD_TYPE)"
    swift build --configuration "$BUILD_TYPE"
    print_success "Swift package built successfully"
}

# Find executables built by Swift
find_executable() {
    local exe_name="$1"
    local build_dir="$2"
    
    # Swift 5.5+ uses architecture-specific directories
    # Try direct path first
    if [ -f "$build_dir/$exe_name" ]; then
        echo "$build_dir/$exe_name"
        return 0
    fi
    
    # Search in architecture-specific subdirectories (arm64-apple-macosx*, x86_64-apple-macosx*)
    local found=$(find "$build_dir" -maxdepth 2 -name "$exe_name" -type f ! -path "*/.*" 2>/dev/null | head -1)
    if [ -n "$found" ] && [ -f "$found" ]; then
        echo "$found"
        return 0
    fi
    
    # If not found, return empty
    return 1
}

# Create the macOS App bundle
create_app_bundle() {
    print_header "Creating macOS App Bundle"
    
    # Create directory structure
    mkdir -p "$APP_BUNDLE/Contents/MacOS"
    mkdir -p "$APP_BUNDLE/Contents/Resources"
    
    # Find and copy MetalVoice executable
    METALVOICE_EXEC=$(find_executable "MetalVoice" "$BUILD_DIR")
    if [ -z "$METALVOICE_EXEC" ] || [ ! -f "$METALVOICE_EXEC" ]; then
        print_error "MetalVoice executable not found. Build may have failed. Checked: $BUILD_DIR"
    fi
    
    cp "$METALVOICE_EXEC" "$APP_BUNDLE/Contents/MacOS/"
    print_success "Copied MetalVoice executable"
    
    # Copy Info.plist
    if [ -f "Resources/Info.plist" ]; then
        cp "Resources/Info.plist" "$APP_BUNDLE/Contents/"
        print_success "Copied Info.plist"
    else
        print_warning "Info.plist not found. The app bundle may not launch correctly."
    fi
    
    # Copy CoreML model
    if [ -d "Resources/DeepFilterNet3_Streaming.mlmodelc" ]; then
        cp -r "Resources/DeepFilterNet3_Streaming.mlmodelc" "$APP_BUNDLE/Contents/Resources/"
        print_success "Copied CoreML model"
    else
        print_warning "CoreML model not found at Resources/DeepFilterNet3_Streaming.mlmodelc"
    fi
    
    # Copy App Icon
    if [ -f "Resources/AppIcon.icns" ]; then
        cp "Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
        print_success "Copied App Icon"
    else
        print_warning "AppIcon.icns not found"
    fi
    
    # Copy Logo (used in the app)
    if [ -f "Resources/MetalVoiceLogo.png" ]; then
        cp "Resources/MetalVoiceLogo.png" "$APP_BUNDLE/Contents/Resources/"
        print_success "Copied Logo"
    else
        print_warning "MetalVoiceLogo.png not found"
    fi
}

# Code sign the app bundle (required for microphone access)
sign_app_bundle() {
    print_header "Code Signing App Bundle"
    
    if [ -f "Resources/MetalVoice.entitlements" ]; then
        codesign --force --deep --sign - --entitlements "Resources/MetalVoice.entitlements" "$APP_BUNDLE"
        print_success "Code signed $APP_BUNDLE with entitlements"
    else
        # Fallback: sign without specific entitlements
        codesign --force --deep --sign - "$APP_BUNDLE"
        print_warning "Code signed $APP_BUNDLE (entitlements file not found)"
    fi
}

# Export CLI
export_cli() {
    print_header "Exporting MetalVoiceCLI"
    
    # Find MetalVoiceCLI executable
    METALVOICECLI_EXEC=$(find_executable "MetalVoiceCLI" "$BUILD_DIR")
    if [ -z "$METALVOICECLI_EXEC" ] || [ ! -f "$METALVOICECLI_EXEC" ]; then
        print_error "MetalVoiceCLI executable not found. Build may have failed. Checked: $BUILD_DIR"
    fi
    
    cp "$METALVOICECLI_EXEC" .
    chmod +x MetalVoiceCLI
    print_success "Exported MetalVoiceCLI to ./MetalVoiceCLI"
}

# Display final build summary
build_summary() {
    print_header "Build Complete"
    echo "Build artifacts:"
    echo "  • App Bundle: $APP_BUNDLE (ready to use or distribute)"
    echo "  • CLI: ./MetalVoiceCLI (command-line interface)"
    echo ""
    echo "Next steps:"
    echo "  • Move '$APP_BUNDLE' to /Applications for installation"
    echo "  • Or run './MetalVoice.app/Contents/MacOS/MetalVoice' to test"
    echo "  • Use './MetalVoiceCLI --help' for CLI usage"
    echo ""
    print_success "Build successful!"
}

# Display usage information
usage() {
    cat << EOF
Usage: ./build.sh [OPTIONS]

Build the MetalVoice application and CLI

OPTIONS:
    release             Build in release mode (default, optimized)
    debug               Build in debug mode (with debug symbols)
    clean               Clean build artifacts
    help                Show this help message

EXAMPLES:
    ./build.sh                      # Build in release mode
    ./build.sh release              # Explicit release build
    ./build.sh debug                # Build in debug mode
    ./build.sh clean                # Clean artifacts
    ./build.sh help                 # Show this help

REQUIREMENTS:
    • macOS 13.0 or later
    • Apple Silicon (M1, M2, M3, or newer)
    • Swift 5.9 or later
    • Xcode Command Line Tools

INSTALLATION:
    After building, move the app bundle to /Applications:
        mv MetalVoice.app ~/Applications/

EOF
}

# Main execution
main() {
    case "${1:-release}" in
        clean)
            clean
            exit 0
            ;;
        help)
            usage
            exit 0
            ;;
        release|debug)
            check_requirements
            clean
            build_package
            create_app_bundle
            sign_app_bundle
            export_cli
            build_summary
            ;;
        *)
            print_error "Unknown option: $1. Use './build.sh help' for usage."
            ;;
    esac
}

# Run main
main "$@"
