TARGET := iphone:clang:14.5:14.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = DirectFMPrefs

DirectFMPrefs_FILES = DirectFMRootListController.m DirectFMScrobbledTracksViewController.m
DirectFMPrefs_FRAMEWORKS = UIKit
DirectFMPrefs_PRIVATE_FRAMEWORKS = Preferences

DirectFMPrefs_INSTALL_PATH = /Library/PreferenceBundles
DirectFMPrefs_CFLAGS = -fobjc-arc -Iinclude -I../src -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/bundle.mk
