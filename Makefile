TARGET := iphone:clang:8.4:8.0
ARCHS = armv7

include $(THEOS)/makefiles/common.mk

TOOL_NAME = Scrubble

Scrubble_FILES = $(wildcard src/*.m)
Scrubble_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -Wno-format
Scrubble_CODESIGN_FLAGS = -Sentitlements.plist
Scrubble_INSTALL_PATH = /usr/local/libexec/

# Link MediaRemote framework for iOS 8
Scrubble_LDFLAGS = -F$(THEOS)/sdks/iPhoneOS8.4.sdk/System/Library/PrivateFrameworks -F$(THEOS)/sdks/iPhoneOS8.4.sdk/System/Library/Frameworks -framework MediaRemote
ADDITIONAL_OBJCFLAGS = -I$(THEOS)/include/MediaRemote -I$(THEOS)/sdks/iPhoneOS8.4.sdk/System/Library/PrivateFrameworks/MediaRemote.framework/Headers

include $(THEOS_MAKE_PATH)/tool.mk
SUBPROJECTS += ScrubblePrefs
include $(THEOS_MAKE_PATH)/aggregate.mk


internal-stage::
	$(ECHO_NOTHING)$(FAKEROOT) chown root:wheel $(THEOS_STAGING_DIR)/Library/LaunchDaemons/fr.rootfs.scrubble.plist$(ECHO_END)
ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
	$(ECHO_NOTHING)/usr/libexec/PlistBuddy -c "Set :ProgramArguments:0 /var/jb/usr/local/libexec/Scrubble" "$(THEOS_STAGING_DIR)/Library/LaunchDaemons/fr.rootfs.scrubble.plist" $(ECHO_END)
endif
