name: Build Driver Helper Dylib

on:
  push:
    branches: [ "main", "master" ]
  workflow_dispatch:

jobs:
  build:
    runs-on: macos-latest

    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Compile Dylib
        run: |
          SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)
          echo "Building with SDK: $SDK_PATH"
          
          # Tự động nhận diện file ViewInspector.m hoặc DriverHelper.m
          SOURCE_FILE="ViewInspector.m"
          if [ -f "DriverHelper.m" ]; then
            SOURCE_FILE="DriverHelper.m"
          fi
          
          echo "Compiling from source: $SOURCE_FILE"
          
          clang -target arm64-apple-ios13.0 \
                -isysroot "$SDK_PATH" \
                -dynamiclib \
                -install_name @rpath/DriverHelper.dylib \
                -fobjc-arc \
                -framework UIKit \
                -framework Foundation \
                -framework CoreGraphics \
                -framework QuartzCore \
                -framework Vision \
                -O2 \
                "$SOURCE_FILE" -o DriverHelper.dylib

      - name: Validate Binary
        run: |
          file DriverHelper.dylib
          otool -L DriverHelper.dylib

      - name: Upload Binary Artifact
        uses: actions/upload-artifact@v4
        with:
          name: DriverHelper.dylib
          path: DriverHelper.dylib
