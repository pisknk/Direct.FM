TARGET := iphone:clang:14.5:14.0

include $(THEOS)/makefiles/common.mk

TOOL_NAME = DirectFM

DirectFM_FILES = $(wildcard src/*.m)
DirectFM_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
DirectFM_CODESIGN_FLAGS = -Sentitlements.plist
DirectFM_INSTALL_PATH = /usr/local/libexec/
$(TOOL_NAME)_PRIVATE_FRAMEWORKS = MediaRemote

include $(THEOS_MAKE_PATH)/tool.mk
SUBPROJECTS += DirectFMPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk


internal-stage::
	$(ECHO_NOTHING)$(FAKEROOT) chown root:wheel $(THEOS_STAGING_DIR)/Library/LaunchDaemons/playpass.direct.fm.plist$(ECHO_END)
ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
	$(ECHO_NOTHING)/usr/libexec/PlistBuddy -c "Set :ProgramArguments:0 /var/jb/usr/local/libexec/DirectFM" "$(THEOS_STAGING_DIR)/Library/LaunchDaemons/playpass.direct.fm.plist" $(ECHO_END)
endif
