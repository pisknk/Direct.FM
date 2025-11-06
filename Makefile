TARGET := iphone:clang:9.3:8.0
ARCHS = armv7

# Disable modules and suppress deprecated warnings for iOS 9.3 SDK compatibility
ADDITIONAL_OBJCFLAGS = -fno-modules -Wno-deprecated-module-dot-map -Wno-error -I$(THEOS)/include/MediaRemote -I$(THEOS)/sdks/iPhoneOS9.3.sdk/System/Library/PrivateFrameworks/MediaRemote.framework/Headers

include $(THEOS)/makefiles/common.mk

TOOL_NAME = DirectFM

DirectFM_FILES = $(wildcard src/*.m)
DirectFM_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -Wno-format -Wno-deprecated-module-dot-map -fno-modules
DirectFM_CODESIGN_FLAGS = -Sentitlements.plist
DirectFM_INSTALL_PATH = /usr/local/libexec/

# Link MediaRemote framework (using iOS 9.3 SDK with iOS 8.0 deployment target)
DirectFM_LDFLAGS = -F$(THEOS)/sdks/iPhoneOS9.3.sdk/System/Library/PrivateFrameworks -F$(THEOS)/sdks/iPhoneOS9.3.sdk/System/Library/Frameworks -framework MediaRemote

include $(THEOS_MAKE_PATH)/tool.mk
SUBPROJECTS += DirectFMPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk


internal-stage::
	$(ECHO_NOTHING)$(FAKEROOT) chown root:wheel $(THEOS_STAGING_DIR)/Library/LaunchDaemons/playpass.direct.fm.plist$(ECHO_END)
ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
	$(ECHO_NOTHING)/usr/libexec/PlistBuddy -c "Set :ProgramArguments:0 /var/jb/usr/local/libexec/DirectFM" "$(THEOS_STAGING_DIR)/Library/LaunchDaemons/playpass.direct.fm.plist" $(ECHO_END)
endif
