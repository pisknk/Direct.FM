TARGET := iphone:clang:latest:8.0

# inherit architecture settings from parent makefile
ARCHS ?= armv7 arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = ScrubblePrefs

ScrubblePrefs_FILES = SCRUBRootListController.m
ScrubblePrefs_FRAMEWORKS = UIKit
ScrubblePrefs_PRIVATE_FRAMEWORKS = Preferences

ScrubblePrefs_INSTALL_PATH = /Library/PreferenceBundles
ScrubblePrefs_CFLAGS = -fobjc-arc -Iinclude -Wno-deprecated-declarations -Wno-unused-variable

include $(THEOS_MAKE_PATH)/bundle.mk
