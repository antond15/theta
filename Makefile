export ARCHS = arm64
export SDKVERSION = 14.5

GO_EASY_ON_ME = 1
FINALPACKAGE = 1

THETA_VERSION_NUMBER = 1.0.1

# Non-obfuscating toolchain (no Hikari)
export PREFIX = $(THEOS)/toolchain/Xcode14.xctoolchain/usr/bin/

# Diagnostic logging (THDebugLog, notification extension traces). Off in normal builds.
ifeq ($(THETA_DEBUG), 1)
	Theta_CFLAGS += -DTHETA_DEBUG=1
	ThetaNSE_CFLAGS += -DTHETA_DEBUG=1
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Theta

Theta_FILES = TweakCOMPILE.xm fishhook.c \
	$(wildcard Source/UI/*.m) \
	$(wildcard Source/Media/*.m) \
	$(wildcard Source/ProfileAnalyzer/*.m)

Theta_FRAMEWORKS = UIKit Foundation CoreGraphics Photos CoreServices SystemConfiguration SafariServices Security QuartzCore AuthenticationServices WebKit UserNotifications AVFoundation
Theta_LDFLAGS = -lsqlite3
Theta_PRIVATE_FRAMEWORKS = Preferences

Theta_CFLAGS += -fobjc-arc \
	-Wno-unused-variable -Wno-unused-value -Wno-deprecated-declarations \
	-Wno-nullability-completeness -Wno-unused-function -Wno-incompatible-pointer-types \
	-I$(THEOS_PROJECT_DIR) \
	-DTHETA_VERSION='"v$(THETA_VERSION_NUMBER)"' \
	-DTHETA_PROJECT='"theta v$(THETA_VERSION_NUMBER)"'

# FFmpeg headers (runtime loaded via dlopen)
Theta_CFLAGS += -I"$(THEOS_PROJECT_DIR)/vendor/ffmpeg.framework"

# build.sh injects the dylibs into the IPA; the re-signer signs them. No ldid, no dSYM
# (dsymutil writes a same-named MH_DSYM under *.dSYM/).
CODESIGN_IPA = 0
TARGET_CODESIGN =
LDID_FLAGS =
TARGET_DSYMUTIL =

include $(THEOS_MAKE_PATH)/tweak.mk

LIBRARY_NAME = ThetaNSE
ThetaNSE_FILES = Source/SideloadNSE/ThetaNSE.m Source/SideloadNSE/ThetaHPKEKeyFile.m fishhook.c
ThetaNSE_FRAMEWORKS = Foundation Security
ThetaNSE_CFLAGS += -fobjc-arc -fvisibility=hidden -I$(THEOS_PROJECT_DIR)
include $(THEOS_MAKE_PATH)/library.mk

before-all::
	@rm -f TweakCOMPILE.xm
	@python3 scripts/assemble.py

after-all::
	@rm -f TweakCOMPILE.xm
