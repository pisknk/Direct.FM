TARGET := iphone:clang:8.4:8.0
ARCHS = armv7

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = ScrubblePrefs

ScrubblePrefs_FILES = SCRUBRootListController.m
ScrubblePrefs_FRAMEWORKS = UIKit
ScrubblePrefs_PRIVATE_FRAMEWORKS = Preferences

ScrubblePrefs_INSTALL_PATH = /Library/PreferenceBundles
ScrubblePrefs_CFLAGS = -fobjc-arc -Iinclude -Wno-deprecated-declarations -Wno-unused-variable -Wno-format

include $(THEOS_MAKE_PATH)/bundle.mk
