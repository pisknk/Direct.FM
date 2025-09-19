TARGET := iphone:clang:latest:8.0

# support building for different architectures
# use: make ARCHS="armv7" for iOS 8.4.1/32-bit
# use: make ARCHS="arm64 arm64e" for modern iOS
# use: make ARCHS="armv7 arm64 arm64e" for universal build
ARCHS ?= armv7 arm64 arm64e

include $(THEOS)/makefiles/common.mk

TOOL_NAME = Scrubble

Scrubble_FILES = $(wildcard src/*.m)
Scrubble_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -Wno-format
Scrubble_CODESIGN_FLAGS = -Sentitlements.plist
Scrubble_INSTALL_PATH = /usr/local/libexec/
$(TOOL_NAME)_PRIVATE_FRAMEWORKS = MediaRemote

include $(THEOS_MAKE_PATH)/tool.mk
SUBPROJECTS += ScrubblePrefs
include $(THEOS_MAKE_PATH)/aggregate.mk


internal-stage::
	$(ECHO_NOTHING)$(FAKEROOT) chown root:wheel $(THEOS_STAGING_DIR)/Library/LaunchDaemons/fr.rootfs.scrubble.plist$(ECHO_END)
ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
	$(ECHO_NOTHING)/usr/libexec/PlistBuddy -c "Set :ProgramArguments:0 /var/jb/usr/local/libexec/Scrubble" "$(THEOS_STAGING_DIR)/Library/LaunchDaemons/fr.rootfs.scrubble.plist" $(ECHO_END)
endif
