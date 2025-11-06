TARGET ?= iphone:clang:14.5:14.0
ARCHS ?= arm64e

# conservative flags; avoid hardcoding old sdk include paths
ADDITIONAL_OBJCFLAGS = -fno-modules -Wno-deprecated-module-dot-map -Wno-error

include $(THEOS)/makefiles/common.mk

TOOL_NAME = DirectFM

DirectFM_FILES = $(wildcard src/*.m)
DirectFM_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -Wno-format -Wno-deprecated-module-dot-map -fno-modules
DirectFM_CODESIGN_FLAGS = -Sentitlements.plist
DirectFM_INSTALL_PATH = /usr/local/libexec/

# link required frameworks; theos will resolve against the active sdk
DirectFM_FRAMEWORKS = Foundation UIKit Security
DirectFM_PRIVATE_FRAMEWORKS = MediaRemote

include $(THEOS_MAKE_PATH)/tool.mk
SUBPROJECTS += DirectFMPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk


internal-stage::
	$(ECHO_NOTHING)$(FAKEROOT) chown root:wheel $(THEOS_STAGING_DIR)/Library/LaunchDaemons/playpass.direct.fm.plist$(ECHO_END)
ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
	$(ECHO_NOTHING)/usr/libexec/PlistBuddy -c "Set :ProgramArguments:0 /var/jb/usr/local/libexec/DirectFM" "$(THEOS_STAGING_DIR)/Library/LaunchDaemons/playpass.direct.fm.plist" $(ECHO_END)
endif
