TARGET := iphone:clang:9.3:8.0
ARCHS = armv7

# Disable modules and suppress deprecated warnings for iOS 9.3 SDK compatibility
ADDITIONAL_OBJCFLAGS = -fno-modules -Wno-deprecated-module-dot-map -Wno-error

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = ScrubblePrefs

ScrubblePrefs_FILES = SCRUBRootListController.m
ScrubblePrefs_FRAMEWORKS = UIKit
ScrubblePrefs_PRIVATE_FRAMEWORKS = Preferences

ScrubblePrefs_INSTALL_PATH = /Library/PreferenceBundles
ScrubblePrefs_CFLAGS = -fobjc-arc -Iinclude -Wno-deprecated-declarations -Wno-unused-variable -Wno-format -Wno-deprecated-module-dot-map -fno-modules

include $(THEOS_MAKE_PATH)/bundle.mk
