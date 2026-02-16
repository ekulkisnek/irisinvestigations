#!/bin/bash
cd "$(dirname "$0")"
swiftc -o ScreenWarmth.app/Contents/MacOS/ScreenWarmth \
  -framework AppKit -framework Foundation -framework CoreGraphics \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -target arm64-apple-macos13.0 \
  ScreenWarmth/main.swift ScreenWarmth/AppDelegate.swift \
  ScreenWarmth/GammaController.swift ScreenWarmth/PopoverContentViewController.swift
echo "Built."
