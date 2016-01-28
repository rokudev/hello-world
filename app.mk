#########################################################################
# app.mk: common include file for application Makefiles.
#
# The client Makefile:
#
# 1) must set APPNAME to an app ID, typically the app name encoded as
#    a unique identifier suitable for a file/directory name
#    (i.e. alphanumeric, no spaces or punctuation).
#
# 2) may set IMPORTS, to a list of .brs base file names to be used from
#    the common utilities.
#
# Makefile common usage:
# > make
# > make run
# > make install
# > make remove
#
# Makefile less common usage:
# > make art-opt
# > make pkg
# > make install-native
# > make remove-native
# > make tr
#
# Important Notes:
# To use the "run", "install" and "remove" targets to install your
# application directly from the shell, you must do the following:
#
# 1) Make sure that you have the curl command line executable in your path.
# 2) Set the variable ROKU_DEV_TARGET in your environment to the IP
#    address of your Roku box, e.g.
#      export ROKU_DEV_TARGET=192.168.1.1
# 3) Set the variable DEVPASSWORD in your environment with the developer
#    password that you have set for your Roku box, e.g.
#      export DEVPASSWORD=mypassword
#    (If you don't set this, you will be prompted for every install command.)
##########################################################################

##########################################################################
# Specifying application files to be packaged:
#
# By default, ZIP_EXCLUDE will exclude well-known source directories and
# files that should typically not be included in the application
# distribution.
#
# If you want to entirely override the default settings, you can put your
# own definition of ZIP_EXCLUDE in your Makefile.
#
# Example:
#   ZIP_EXCLUDE= -x keys\*
# will exclude all files from the keys directory (and only those files).
#
# To exclude using more than one pattern, use additional '-x <pattern>'
# arguments, e.g.
#   ZIP_EXCLUDE= -x \*.pkg -x storeassets\*
#
# If you just need to add additional files to the ZIP_EXCLUDE list, you can
# define ZIP_EXCLUDE_LOCAL in your Makefile.  This pattern will be appended
# to the default ZIP_EXCLUDE pattern.
#
# Example:
#   ZIP_EXCLUDE_LOCAL= -x goldens\*
##########################################################################

# improve performance and simplify Makefile debugging by omitting
# default language rules that don't apply to this environment.
MAKEFLAGS += --no-builtin-rules
.SUFFIXES:

# we don't want targets to be made in parallel
.NOTPARALLEL:

##########################################################################

IS_TEAMCITY_BUILD ?=
ifneq ($(TEAMCITY_BUILDCONF_NAME),)
IS_TEAMCITY_BUILD := true
endif

HOST_OS := unknown
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
	HOST_OS := macos
else ifeq ($(UNAME_S),Linux)
	HOST_OS := linux
else ifneq (,$(findstring CYGWIN,$(UNAME_S)))
	HOST_OS := cygwin
endif

# Use native file extensions for executables
ifeq ($(HOST_OS),cygwin)
HOST_EXE_SUFFIX := .exe
else
HOST_EXE_SUFFIX :=
endif

# Use native file extensions for executables
ifeq ($(HOST_OS),cygwin)
MAKE_HOST_PATH = $(shell cygpath -m "$1")
else
MAKE_HOST_PATH = $1
endif

# We want to be able to use escape sequences with echo
ifeq ($(HOST_OS),macos)
ECHO := echo
else
ECHO := echo -e
endif

# get the root directory in absolute form, so that current directory
# can be changed during the make if needed.
APPS_ROOT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

# the current directory is the app root directory
SOURCEDIR := .

DISTREL := $(APPS_ROOT_DIR)/dist
COMMONREL := $(APPS_ROOT_DIR)/common

ZIPREL := $(DISTREL)/apps
PKGREL := $(DISTREL)/packages
CHECK_TMP_DIR := $(DISTREL)/tmp-check

DATE_TIME := $(shell date +%F-%T)

ifeq ($(APPNAME),)
$(error ERROR: APPNAME is not set.)
endif

APP_ZIP_FILE := $(ZIPREL)/$(APPNAME).zip
APP_PKG_FILE := $(PKGREL)/$(APPNAME)_$(DATE_TIME).pkg

# these variables are only used for the .pkg file version tagging.
APP_NAME := $(APPNAME)
APP_VERSION := $(VERSION)
ifeq ($(IS_TEAMCITY_BUILD),true)
APP_NAME    := $(subst /,-,$(TEAMCITY_BUILDCONF_NAME))
APP_VERSION := $(BUILD_NUMBER)
endif

APPSOURCEDIR := $(SOURCEDIR)/source
IMPORTFILES := $(foreach f,$(sort $(IMPORTS)),$f.brs)

APP_LIBSTUB_DIR := $(SOURCEDIR)/libstub

# ROKU_NATIVE_DEV must be set in the calling environment to
# the firmware native-build src directory
NATIVE_DIST_DIR := $(ROKU_NATIVE_DEV)/dist
#
NATIVE_DEV_REL  := $(NATIVE_DIST_DIR)/rootfs/Linux86_dev.OBJ/root/nvram/incoming
NATIVE_DEV_PKG  := $(NATIVE_DEV_REL)/dev.zip
NATIVE_PLETHORA := $(NATIVE_DIST_DIR)/application/Linux86_dev.OBJ/root/bin/plethora
NATIVE_TICKLER  := $(NATIVE_PLETHORA) tickle-plugin-installer

APPS_SCRIPTS_DIR  := $(APPS_ROOT_DIR)/tools/scripts

# only Linux host is supported for these tools currently
APPS_TOOLS_DIR    := $(APPS_ROOT_DIR)/tools/$(HOST_OS)/bin

APP_PACKAGE_TOOL  ?= $(APPS_TOOLS_DIR)/app-package$(HOST_EXE_SUFFIX)
MAKE_TR_TOOL      ?= $(APPS_TOOLS_DIR)/maketr$(HOST_EXE_SUFFIX)
BRIGHTSCRIPT_TOOL ?= $(APPS_TOOLS_DIR)/brightscript$(HOST_EXE_SUFFIX)

CHECK_MANIFEST_TOOL ?= $(APPS_SCRIPTS_DIR)/check-manifest.pl
CHECK_THEME_TOOL    ?= $(APPS_SCRIPTS_DIR)/check-theme.pl

# if building from a firmware tree, use the BrightScript libraries from there
ifneq (,$(wildcard $(APPS_ROOT_DIR)/../3rdParty/brightscript/Scripts/LibCore/.))
BRIGHTSCRIPT_LIBS_DIR ?= $(APPS_ROOT_DIR)/../3rdParty/brightscript/Scripts/LibCore
endif
# else use the reference libraries from the tools directory.
BRIGHTSCRIPT_LIBS_DIR ?= $(APPS_ROOT_DIR)/tools/brightscript/Scripts/LibCore

APP_KEY_PASS_TMP := /tmp/app_key_pass
DEV_SERVER_TMP_FILE := /tmp/dev_server_out

# The developer password that was set on the player is required for
# plugin_install operations on modern versions of firmware.
# It may be pre-specified in the DEVPASSWORD environment variable on entry,
# otherwise the make will stop and prompt the user to enter it when needed.
ifdef DEVPASSWORD
	USERPASS := rokudev:$(DEVPASSWORD)
else
	USERPASS := rokudev
endif

ifeq ($(HOST_OS),macos)
	# Mac doesn't support these args
	CP_ARGS =
else
	CP_ARGS = --preserve=ownership,timestamps --no-preserve=mode
endif

# For a quick ping, we want the command to return success as soon as possible,
# and a timeout failure in no more than a second or two.
ifeq ($(HOST_OS),cygwin)
	# This assumes that the Windows ping command is used, not cygwin's.
	QUICK_PING_ARGS = -n 1 -w 1000
else ifeq ($(HOST_OS),macos)
	QUICK_PING_ARGS = -c 1 -t 1
else # Linux
	QUICK_PING_ARGS = -c 1 -w 1
endif

ifndef ZIP_EXCLUDE
	ZIP_EXCLUDE =
	# exclude hidden files (name starting with .)
	ZIP_EXCLUDE += -x .\*
	ZIP_EXCLUDE += -x \*/.\*
	# exclude shell scripts (typically top-level build helpers)
	ZIP_EXCLUDE += -x \*.sh
	# exclude files with name ending with ~
	ZIP_EXCLUDE += -x \*~
	ZIP_EXCLUDE += -x \*.mod
	ZIP_EXCLUDE += -x \*.pkg
	ZIP_EXCLUDE += -x \*.zip
	ZIP_EXCLUDE += -x Makefile
	ZIP_EXCLUDE += -x keys/\*
	ZIP_EXCLUDE += -x libapi/\*
	ZIP_EXCLUDE += -x libstub/\*
	ZIP_EXCLUDE += -x storeassets/\*
	# exclude Mac OS X desktop metadata
	ZIP_EXCLUDE += -x \*__MACOSX\*
	ZIP_EXCLUDE += -x \*.DS_Store
endif

ZIP_EXCLUDE_PATTERN = $(ZIP_EXCLUDE)
ZIP_EXCLUDE_PATTERN += $(ZIP_EXCLUDE_LOCAL)

ZIP_ARGS :=

#ifneq ($(APP_VERBOSE_ARCHIVE),true)
#	ZIP_ARGS += -q
#endif

ifeq ($(APP_QUIET_ARCHIVE),true)
	ZIP_ARGS += -q
endif

# -------------------------------------------------------------------------
# Colorized output support.
# If you don't want it, do 'export APP_MK_COLOR=false' in your env.
# -------------------------------------------------------------------------
ifndef APP_MK_COLOR
APP_MK_COLOR := false
ifeq ($(TERM),$(filter $(TERM),xterm xterm-color xterm-256color))
	APP_MK_COLOR := true
endif
endif

COLOR_START  :=
COLOR_INFO   :=
COLOR_PROMPT :=
COLOR_DONE   :=
COLOR_ERR    :=
COLOR_OFF    :=

ifeq ($(APP_MK_COLOR),true)
	# ANSI color escape codes:

	#	\e[0;30m	black
	#	\e[0;31m	red
	#	\e[0;32m	green
	#	\e[0;33m	yellow
	#	\e[0;34m	blue
	#	\e[0;35m	magenta
	#	\e[0;36m	cyan
	#	\e[0;37m	light gray

	#	\e[1;30m	gray
	#	\e[1;31m	light red
	#	\e[1;32m	light green
	#	\e[1;33m	light yellow
	#	\e[1;34m	light blue
	#	\e[1;35m	light purple
	#	\e[1;36m	light cyan
	#	\e[1;37m	white

	COLOR_START  := \033[1;36m
	COLOR_INFO   := \033[1;35m
	COLOR_PROMPT := \033[0;31m
	COLOR_DONE   := \033[1;32m
	COLOR_ERROR  := \033[1;31m
	COLOR_OFF    := \033[0m
endif

# empty if not theme
APP_IS_THEME := $(shell grep '^theme=' manifest)

# -------------------------------------------------------------------------
# $(APPNAME): the default target is to create the zip file for the app.
# This contains the set of files that are to be deployed on a Roku.
# -------------------------------------------------------------------------
.PHONY: $(APPNAME)
$(APPNAME): manifest
	@$(ECHO) "$(COLOR_START)**** Creating $(APPNAME).zip ****$(COLOR_OFF)"

	@$(ECHO) "  >> removing old application zip $(APP_ZIP_FILE)"
	@if [ -e "$(APP_ZIP_FILE)" ]; then \
		rm $(APP_ZIP_FILE); \
	fi

	@$(ECHO) "  >> creating destination directory $(ZIPREL)"
	@if [ ! -d $(ZIPREL) ]; then \
		mkdir -p $(ZIPREL); \
	fi

	@$(ECHO) "  >> setting directory permissions for $(ZIPREL)"
	@if [ ! -w $(ZIPREL) ]; then \
		chmod 755 $(ZIPREL); \
	fi

	@if [ "$(IMPORTFILES)" ]; then \
		$(ECHO) "  >> copying imports"; \
		rm -rf $(APPSOURCEDIR)/common; \
		mkdir $(APPSOURCEDIR)/common; \
		for IMPORTFILE in $(IMPORTFILES); do \
			echo "  copying: common/$$IMPORTFILE"; \
			cp -f $(CP_ARGS) $(COMMONREL)/$$IMPORTFILE $(APPSOURCEDIR)/common/; \
		done; \
	fi

# Note: zip .png files without compression
# FIXME: shouldn't it exclude .jpg too?
# FIXME: if no .png files are found, outputs bogus "zip warning: zip file empty"
	@$(ECHO) "  >> creating application zip $(APP_ZIP_FILE)"
	@if [ -d $(SOURCEDIR) ]; then \
		zip $(ZIP_ARGS) -0 -r "$(APP_ZIP_FILE)" . -i \*.png $(ZIP_EXCLUDE_PATTERN); \
		zip $(ZIP_ARGS) -9 -r "$(APP_ZIP_FILE)" . -x \*.png $(ZIP_EXCLUDE_PATTERN); \
	else \
		$(ECHO) "$(COLOR_ERROR)Source for $(APPNAME) not found at $(SOURCEDIR)$(COLOR_OFF)"; \
	fi

	@if [ "$(IMPORTFILES)" ]; then \
		$(ECHO) "  >> deleting imports"; \
		rm -rf $(APPSOURCEDIR)/common; \
	fi

# If DISTDIR is not empty then copy the zip package to the DISTDIR.
# Note that this is used by the firmware build, to build applications that are
# embedded in the firmware software image, such as the built-in screensaver.
# For those cases, the Netflix/Makefile calls this makefile for each app
# with DISTDIR and DISTZIP set to the target directory and base filename
# respectively.
	@if [ $(DISTDIR) ]; then \
		rm -f $(DISTDIR)/$(DISTZIP).zip; \
		mkdir -p $(DISTDIR); \
		cp -f --preserve=ownership,timestamps --no-preserve=mode \
			$(APP_ZIP_FILE) $(DISTDIR)/$(DISTZIP).zip; \
	fi

	@$(ECHO) "$(COLOR_DONE)**** packaging $(APPNAME) complete ****$(COLOR_OFF)"

# -------------------------------------------------------------------------
# clean: remove any build output for the app.
# -------------------------------------------------------------------------
.PHONY: clean
clean:
	rm -f $(APP_ZIP_FILE)
# FIXME: we should use a canonical output file name, rather than having
# the date-time stamp in the output file name.
#	rm -f $(APP_PKG_FILE)
	rm -f $(PKGREL)/$(APPNAME)_*.pkg

# -------------------------------------------------------------------------
# clobber: remove any build output for the app.
# -------------------------------------------------------------------------
.PHONY: clobber
clobber: clean

# -------------------------------------------------------------------------
# dist-clean: remove the dist directory for the sandbox.
# -------------------------------------------------------------------------
.PHONY: dist-clean
dist-clean:
	rm -rf $(DISTREL)/*

# -------------------------------------------------------------------------
# CHECK_OPTIONS: this is used to specify configurable options, such
# as which version of the BrightScript library sources should be used
# to compile the app.
# -------------------------------------------------------------------------
CHECK_OPTIONS =

# add the path to the common/LibCore sources, if available
ifneq (,$(wildcard $(BRIGHTSCRIPT_LIBS_DIR)/.))
	CHECK_OPTIONS += -lib $(call MAKE_HOST_PATH,$(BRIGHTSCRIPT_LIBS_DIR))
endif

# if the app uses BS libraries, it can provide stub libraries to compile with.
ifneq (,$(wildcard $(APP_LIBSTUB_DIR)/.))
	CHECK_OPTIONS += -applib $(call MAKE_HOST_PATH,$(APP_LIBSTUB_DIR))
endif

ifneq ($(APP_IS_LIBRARY),)
	# if the app is a BS library, let it find auxiliary internal sources
	CHECK_OPTIONS += -applib $(call MAKE_HOST_PATH,$(CHECK_TMP_DIR)/libsource)
endif

ifneq ($(APP_IS_LIBRARY),)
	# if the app is a BS library, we only compile the specific .brs file
	CHECK_OPTIONS += $(call MAKE_HOST_PATH,$(CHECK_TMP_DIR)/libsource/$(APP_IS_LIBRARY))
else
	# else implicitly check all the .brs files in the source directory
	CHECK_OPTIONS += $(call MAKE_HOST_PATH,$(CHECK_TMP_DIR))
endif

# -------------------------------------------------------------------------
# CHECK_TMP_BEGIN is used to create a temporary directory containing
# a copy of the app archive contents.
# -------------------------------------------------------------------------
define CHECK_TMP_BEGIN
	rm -rf $(CHECK_TMP_DIR)
	mkdir -p $(CHECK_TMP_DIR)
	unzip -q $(APP_ZIP_FILE) -d $(CHECK_TMP_DIR)
endef

# -------------------------------------------------------------------------
# CHECK_TMP_END is used to remove the temporary directory created by
# CHECK_TMP_BEGIN.
# -------------------------------------------------------------------------
define CHECK_TMP_END
	rm -rf $(CHECK_TMP_DIR)
endef

# -------------------------------------------------------------------------
# check-manifest: run the check tool on the application manifest and
# any referenced asset files.
# -------------------------------------------------------------------------
.PHONY: check-manifest
check-manifest: $(APPNAME)
ifeq ($(APP_CHECK_MANIFEST_DISABLED),true)
ifeq ($(IS_TEAMCITY_BUILD),true)
	@$(ECHO) "**** Warning: manifest check skipped ****"
endif
else
ifeq ($(wildcard $(CHECK_MANIFEST_TOOL)),)
	@$(ECHO) "**** Note: manifest check not available ****"
else
	@$(ECHO) "$(COLOR_START)**** Checking manifest ****$(COLOR_OFF)"
	@$(CHECK_TMP_BEGIN)
	@$(CHECK_MANIFEST_TOOL)
	@$(CHECK_TMP_END)
	@$(ECHO) "$(COLOR_DONE)**** Checking complete ****$(COLOR_OFF)"
endif
endif

# -------------------------------------------------------------------------
# check: run the desktop BrightScript compiler/check tool on the
# application.
# You can bypass checking on the application by setting
# APP_CHECK_DISABLED=true in the app's Makefile or in the environment.
# -------------------------------------------------------------------------
.PHONY: check
check: $(APPNAME) check-manifest
ifeq ($(APP_CHECK_DISABLED),true)
ifeq ($(IS_TEAMCITY_BUILD),true)
	@$(ECHO) "**** Warning: application check skipped ****"
endif
else
ifeq ($(wildcard $(BRIGHTSCRIPT_TOOL)),)
	@$(ECHO) "**** Note: application check not available ****"
else
	@$(ECHO) "$(COLOR_START)**** Checking application ****$(COLOR_OFF)"
	@$(CHECK_TMP_BEGIN)
	@$(BRIGHTSCRIPT_TOOL) check $(CHECK_OPTIONS)
	@$(CHECK_TMP_END)
	@$(ECHO) "$(COLOR_DONE)**** Checking complete ****$(COLOR_OFF)"
endif
endif

# -------------------------------------------------------------------------
# check-strict: run the desktop BrightScript compiler/check tool on the
# application using strict mode.
# -------------------------------------------------------------------------
.PHONY: check-strict
check-strict: $(APPNAME)
	@$(ECHO) "$(COLOR_START)**** Checking application (strict) ****$(COLOR_OFF)"
	@$(CHECK_TMP_BEGIN)
	@$(BRIGHTSCRIPT_TOOL) check -strict $(CHECK_OPTIONS)
	@$(CHECK_TMP_END)
	@$(ECHO) "$(COLOR_DONE)**** Checking complete ****$(COLOR_OFF)"

# -------------------------------------------------------------------------
# check-info: run the desktop BrightScript compiler/check tool on the
# application to print out some summary info (currently just function listing).
# -------------------------------------------------------------------------
.PHONY: check-info
check-info: $(APPNAME)
	@$(ECHO) "$(COLOR_START)**** Dumping application info ****$(COLOR_OFF)"
	@$(CHECK_TMP_BEGIN)
	@$(BRIGHTSCRIPT_TOOL) info $(CHECK_OPTIONS)
	@$(CHECK_TMP_END)
	@$(ECHO) "$(COLOR_DONE)**** Checking complete ****$(COLOR_OFF)"

# -------------------------------------------------------------------------
# check-theme: check the theme xml and assets.
# -------------------------------------------------------------------------
.PHONY: check-theme
check-theme: $(APPNAME)
ifneq ($(APP_IS_THEME),)
ifeq ($(APP_CHECK_THEME_DISABLED),true)
else
	@$(ECHO) "$(COLOR_START)**** Checking theme. ****$(COLOR_OFF)"
	@$(CHECK_TMP_BEGIN)
	@-cd $(CHECK_TMP_DIR) && $(CHECK_THEME_TOOL)
	@$(CHECK_TMP_END)
	@$(ECHO) "$(COLOR_DONE)**** Checking complete ****$(COLOR_OFF)"
endif
else
	@$(ECHO) "$(COLOR_DONE)**** app is not theme ****$(COLOR_OFF)"
endif

# -------------------------------------------------------------------------
# GET_FRIENDLY_NAME_FROM_DD is used to extract the Roku device ID
# from the ECP device description XML response.
# -------------------------------------------------------------------------
define GET_FRIENDLY_NAME_FROM_DD
	cat $(DEV_SERVER_TMP_FILE) | \
		grep -o "<friendlyName>.*</friendlyName>" | \
		sed "s|<friendlyName>||" | \
		sed "s|</friendlyName>||"
endef

# -------------------------------------------------------------------------
# CHECK_ROKU_DEV_TARGET is used to check if ROKU_DEV_TARGET refers a
# Roku device on the network that has an enabled developer web server.
# If the target doesn't exist or doesn't have an enabled web server
# the connection should fail.
# -------------------------------------------------------------------------
define CHECK_ROKU_DEV_TARGET
	if [ -z "$(ROKU_DEV_TARGET)" ]; then \
		$(ECHO) "$(COLOR_ERROR)ERROR: ROKU_DEV_TARGET is not set.$(COLOR_OFF)"; \
		exit 1; \
	fi
	$(ECHO) "$(COLOR_START)Checking dev server at $(ROKU_DEV_TARGET)...$(COLOR_OFF)"

	# first check if the device is on the network via a quick ping
	ping $(QUICK_PING_ARGS) $(ROKU_DEV_TARGET) &> $(DEV_SERVER_TMP_FILE) || \
		( \
			$(ECHO) "$(COLOR_ERROR)ERROR: Device is not responding to ping.$(COLOR_OFF)"; \
			exit 1 \
		)

	# second check ECP, to verify we are talking to a Roku
	rm -f $(DEV_SERVER_TMP_FILE)
	curl --connect-timeout 2 --silent --output $(DEV_SERVER_TMP_FILE) \
		http://$(ROKU_DEV_TARGET):8060 || \
		( \
			$(ECHO) "$(COLOR_ERROR)ERROR: Device is not responding to ECP...is it a Roku?$(COLOR_OFF)"; \
			exit 1 \
		)

	# print the device friendly name to let us know what we are talking to
	ROKU_DEV_NAME=`$(GET_FRIENDLY_NAME_FROM_DD)`; \
	$(ECHO) "$(COLOR_INFO)Device reports as \"$$ROKU_DEV_NAME\".$(COLOR_OFF)"

	# third check dev web server.
	# Note, it should return 401 Unauthorized since we aren't passing the password.
	rm -f $(DEV_SERVER_TMP_FILE)
	HTTP_STATUS=`curl --connect-timeout 2 --silent --output $(DEV_SERVER_TMP_FILE) \
		http://$(ROKU_DEV_TARGET)` || \
		( \
			$(ECHO) "$(COLOR_ERROR)ERROR: Device server is not responding...$(COLOR_OFF)"; \
			$(ECHO) "$(COLOR_ERROR)is the developer installer enabled?$(COLOR_OFF)"; \
			$(ECHO) "$(COLOR_ERROR)3H 2U R L R L R$(COLOR_OFF)"; \
			exit 1 \
		)

	$(ECHO) "$(COLOR_DONE)Dev server is ready.$(COLOR_OFF)"
endef

# -------------------------------------------------------------------------
# CHECK_ROKU_DEV_PASSWORD is used to let the user know they might want to set
# their DEVPASSWORD environment variable.
# -------------------------------------------------------------------------
define CHECK_ROKU_DEV_PASSWORD
	if [ -z "$(DEVPASSWORD)" ]; then \
		$(ECHO) "Note: DEVPASSWORD is not set."; \
	fi
endef

# -------------------------------------------------------------------------
# CHECK_DEVICE_HTTP_STATUS is used to that the last curl command
# to the dev web server returned HTTP 200 OK.
# -------------------------------------------------------------------------
define CHECK_DEVICE_HTTP_STATUS
	if [ "$$HTTP_STATUS" != "200" ]; then \
		$(ECHO) "$(COLOR_ERROR)ERROR: Device returned HTTP $$HTTP_STATUS$(COLOR_OFF)"; \
		exit 1; \
	fi
endef

# -------------------------------------------------------------------------
# GET_PLUGIN_PAGE_RESULT_STATUS is used to extract the status message
# (e.g. Success/Failed) from the dev server plugin_* web page response.
# (Note that the plugin_install web page has two fields, whereas the
# plugin_package web page just has one).
# -------------------------------------------------------------------------
define GET_PLUGIN_PAGE_RESULT_STATUS
	cat $(DEV_SERVER_TMP_FILE) | \
		grep -o "<font color=\"red\">.*" | \
		sed "s|<font color=\"red\">||" | \
		sed "s|</font>||"
endef

# -------------------------------------------------------------------------
# GET_PLUGIN_PAGE_PACKAGE_LINK is used to extract the installed package
# URL from the dev server plugin_package web page response.
# -------------------------------------------------------------------------
define GET_PLUGIN_PAGE_PACKAGE_LINK =
	cat $(DEV_SERVER_TMP_FILE) | \
		grep -o "<a href=\"pkgs//[^\"]*\"" | \
		sed "s|<a href=\"pkgs//||" | \
		sed "s|\"||"
endef

# -------------------------------------------------------------------------
# GET_PLUGIN_PAGE_DEV_ID is used to extract the keyed developer ID
# from the dev server plugin_package web page response.
#
# In 6.x firmware, response text has a line like:
#  <p> Your Dev ID: <font face="Courier">THE_DEVID</font> </p>
#
# In 7.0 firmware, response text has a line like:
#  devDiv.innerHTML = "<label>Your Dev ID: &nbsp;</label> THE_DEVID </label><hr />";
#
# If the box is not keyed, or doesn't have a dev app installed, 
# the response doesn't contain html:
#  <meta HTTP-EQUIV="REFRESH" content="0; url=plugin_install">
# -------------------------------------------------------------------------
define GET_PLUGIN_PAGE_DEV_ID =
	cat $(DEV_SERVER_TMP_FILE) | \
		grep 'Dev ID' | \
		grep -o -E '[0-9a-f]{40}'
endef

# -------------------------------------------------------------------------
# install: install the app as the dev channel on the Roku target device.
# -------------------------------------------------------------------------
.PHONY: install
install: $(APPNAME) check
ifneq ($(APP_IS_THEME),)
install: check-theme
endif
	@$(CHECK_ROKU_DEV_TARGET)

	@$(ECHO) "$(COLOR_START)Installing $(APPNAME)...$(COLOR_OFF)"
	@rm -f $(DEV_SERVER_TMP_FILE)
	@$(CHECK_ROKU_DEV_PASSWORD)
	@HTTP_STATUS=`curl --user $(USERPASS) --digest --silent --show-error \
		-F "mysubmit=Install" -F "archive=@$(APP_ZIP_FILE)" \
		--output $(DEV_SERVER_TMP_FILE) \
		--write-out "%{http_code}" \
		http://$(ROKU_DEV_TARGET)/plugin_install`; \
	$(CHECK_DEVICE_HTTP_STATUS)

	@MSG=`$(GET_PLUGIN_PAGE_RESULT_STATUS)`; \
	$(ECHO) "$(COLOR_DONE)Result: $$MSG$(COLOR_OFF)"

# -------------------------------------------------------------------------
# remove: uninstall the dev channel from the Roku target device.
# -------------------------------------------------------------------------
.PHONY: remove
remove:
	@$(CHECK_ROKU_DEV_TARGET)

	@$(ECHO) "$(COLOR_START)Removing dev app...$(COLOR_OFF)"
	@rm -f $(DEV_SERVER_TMP_FILE)
	@$(CHECK_ROKU_DEV_PASSWORD)
	@HTTP_STATUS=`curl --user $(USERPASS) --digest --silent --show-error \
		-F "mysubmit=Delete" -F "archive=" \
		--output $(DEV_SERVER_TMP_FILE) \
		--write-out "%{http_code}" \
		http://$(ROKU_DEV_TARGET)/plugin_install`; \
	$(CHECK_DEVICE_HTTP_STATUS)

	@MSG=`$(GET_PLUGIN_PAGE_RESULT_STATUS)`; \
	$(ECHO) "$(COLOR_DONE)Result: $$MSG$(COLOR_OFF)"

# -------------------------------------------------------------------------
# check-roku-dev-target: check the status of the Roku target device.
# -------------------------------------------------------------------------
.PHONY: check-roku-dev-target
check-roku-dev-target:
	@$(CHECK_ROKU_DEV_TARGET)

# -------------------------------------------------------------------------
# run: the install target is 'smart' and doesn't do anything if the package
# didn't change.
# But usually I want to run it even if it didn't change, so force a fresh
# install by doing a remove first.
# Some day we should look at doing the force run via a plugin_install flag,
# but for now just brute force it.
# -------------------------------------------------------------------------
.PHONY: run
run: remove install

# -------------------------------------------------------------------------
# get-target-key: return what developer ID the target Roku is keyed to.
#
# FIXME: this will only work if there is a dev app installed.
# If not, it will incorrectly report 'Not keyed'.
# -------------------------------------------------------------------------
.PHONY: get-target-key
get-target-key:
	@$(CHECK_ROKU_DEV_TARGET)

	@rm -f $(DEV_SERVER_TMP_FILE)
	@$(CHECK_ROKU_DEV_PASSWORD)
	@HTTP_STATUS=`curl --user $(USERPASS) --digest --silent --show-error \
		--output $(DEV_SERVER_TMP_FILE) \
		--write-out "%{http_code}" \
		http://$(ROKU_DEV_TARGET)/plugin_package`; \
	$(CHECK_DEVICE_HTTP_STATUS)

	@MSG=`$(GET_PLUGIN_PAGE_DEV_ID)`; \
	if [ -z "$$MSG" ]; then \
		MSG="Not keyed (or no dev app installed)"; \
	fi; \
	$(ECHO) "$(COLOR_DONE)Result: Dev ID: $$MSG$(COLOR_OFF)"

# -------------------------------------------------------------------------
# rekey-target: key the target Roku with the devid from a .pkg.
# -------------------------------------------------------------------------
.PHONY: rekey-target
rekey-target:
	@$(CHECK_ROKU_DEV_TARGET)

	@if [ -z "$(APP_KEY_FILE)" ]; then \
		$(ECHO) "$(COLOR_ERROR)ERROR: APP_KEY_FILE not defined$(COLOR_OFF)"; \
		exit 1; \
	fi
	@if [ ! -f "$(APP_KEY_FILE)" ]; then \
		$(ECHO) "$(COLOR_ERROR)ERROR: key file not found: $(APP_KEY_FILE)$(COLOR_OFF)"; \
		exit 1; \
	fi

	@if [ -z "$(APP_KEY_PASS)" ]; then \
		read -r -p "Password: " REPLY; \
		echo "$$REPLY" > $(APP_KEY_PASS_TMP); \
	else \
		echo "$(APP_KEY_PASS)" > $(APP_KEY_PASS_TMP); \
	fi

	@rm -f $(DEV_SERVER_TMP_FILE)
	@$(CHECK_ROKU_DEV_PASSWORD)
	@PASSWD=`cat $(APP_KEY_PASS_TMP)`; \
	HTTP_STATUS=`curl --user $(USERPASS) --digest --silent --show-error \
		-F "mysubmit=Rekey" -F "archive=@$(APP_KEY_FILE)" \
		-F "passwd=$$PASSWD" \
		--output $(DEV_SERVER_TMP_FILE) \
		--write-out "%{http_code}" \
		http://$(ROKU_DEV_TARGET)/plugin_inspect`; \
	$(CHECK_DEVICE_HTTP_STATUS)

	@MSG=`$(GET_PLUGIN_PAGE_RESULT_STATUS)`; \
	$(ECHO) "$(COLOR_DONE)Result: $$MSG$(COLOR_OFF)"

# -------------------------------------------------------------------------
# pkg: use to create a pkg file from the application sources.
#
# Usage:
# The application name should be specified via $APPNAME.
# The application version should be specified via $VERSION.
# The developer's signing password (from genkey) should be passed via
# $APP_KEY_PASS, or via stdin, otherwise the script will prompt for it.
# -------------------------------------------------------------------------
.PHONY: pkg
pkg: install
	@$(ECHO) "$(COLOR_START)**** Creating package ****$(COLOR_OFF)"

	@$(ECHO) "  >> creating destination directory $(PKGREL)"
	@if [ ! -d $(PKGREL) ]; then \
		mkdir -p $(PKGREL); \
	fi

	@$(ECHO) "  >> setting directory permissions for $(PKGREL)"
	@if [ ! -w $(PKGREL) ]; then \
		chmod 755 $(PKGREL); \
	fi

	@$(CHECK_ROKU_DEV_TARGET)

	@$(ECHO) "Packaging $(APP_NAME)/$(APP_VERSION) to $(APP_PKG_FILE)"

	@if [ -z "$(APP_KEY_PASS)" ]; then \
		read -r -p "Password: " REPLY; \
		echo "$$REPLY" > $(APP_KEY_PASS_TMP); \
	else \
		echo "$(APP_KEY_PASS)" > $(APP_KEY_PASS_TMP); \
	fi

	@rm -f $(DEV_SERVER_TMP_FILE)
	@$(CHECK_ROKU_DEV_PASSWORD)
	@PASSWD=`cat $(APP_KEY_PASS_TMP)`; \
	PKG_TIME=`expr \`date +%s\` \* 1000`; \
	HTTP_STATUS=`curl --user $(USERPASS) --digest --silent --show-error \
		-F "mysubmit=Package" -F "app_name=$(APP_NAME)/$(APP_VERSION)" \
		-F "passwd=$$PASSWD" -F "pkg_time=$$PKG_TIME" \
		--output $(DEV_SERVER_TMP_FILE) \
		--write-out "%{http_code}" \
		http://$(ROKU_DEV_TARGET)/plugin_package`; \
	$(CHECK_DEVICE_HTTP_STATUS)

	@MSG=`$(GET_PLUGIN_PAGE_RESULT_STATUS)`; \
	case "$$MSG" in \
		*Success*) \
			;; \
		*)	$(ECHO) "$(COLOR_ERROR)Result: $$MSG$(COLOR_OFF)"; \
			exit 1 \
			;; \
	esac

	@$(CHECK_ROKU_DEV_PASSWORD)
	@PKG_LINK=`$(GET_PLUGIN_PAGE_PACKAGE_LINK)`; \
	HTTP_STATUS=`curl --user $(USERPASS) --digest --silent --show-error \
		--output $(APP_PKG_FILE) \
		--write-out "%{http_code}" \
		http://$(ROKU_DEV_TARGET)/pkgs/$$PKG_LINK`; \
	$(CHECK_DEVICE_HTTP_STATUS)

	@$(ECHO) "$(COLOR_DONE)**** Package $(APPNAME) complete ****$(COLOR_OFF)"

# -------------------------------------------------------------------------
# app-pkg: use to create a pkg file from the application sources.
# Similar to the pkg target, but does not require a player to do the signing.
# Instead it requires the developer key file and signing password to be
# specified, which are then passed to the app-package desktop tool to create
# the package file.
#
# Usage:
# The application name should be specified via $APPNAME.
# The application version should be specified via $VERSION.
# The developer's key file (.pkg file) should be specified via $APP_KEY_FILE.
# The developer's signing password (from genkey) should be passed via
# $APP_KEY_PASS, or via stdin, otherwise the script will prompt for it.
# -------------------------------------------------------------------------
.PHONY: app-pkg
app-pkg: $(APPNAME) check
	@$(ECHO) "$(COLOR_START)**** Creating package ****$(COLOR_OFF)"

	@$(ECHO) "  >> creating destination directory $(PKGREL)"
	@mkdir -p $(PKGREL) && chmod 755 $(PKGREL)

	@if [ -z "$(APP_KEY_FILE)" ]; then \
		$(ECHO) "$(COLOR_ERROR)ERROR: APP_KEY_FILE not defined$(COLOR_OFF)"; \
		exit 1; \
	fi
	@if [ ! -f "$(APP_KEY_FILE)" ]; then \
		$(ECHO) "$(COLOR_ERROR)ERROR: key file not found: $(APP_KEY_FILE)$(COLOR_OFF)"; \
		exit 1; \
	fi

	@if [ -z "$(APP_KEY_PASS)" ]; then \
		read -r -p "Password: " REPLY; \
		echo "$$REPLY" > $(APP_KEY_PASS_TMP); \
	else \
		echo "$(APP_KEY_PASS)" > $(APP_KEY_PASS_TMP); \
	fi

	@$(ECHO) "Packaging $(APP_NAME)/$(APP_VERSION) to $(APP_PKG_FILE)"

	@if [ -z "$(APP_VERSION)" ]; then \
		$(ECHO) "WARNING: VERSION is not set."; \
	fi

	@PASSWD=`cat $(APP_KEY_PASS_TMP)`; \
	$(APP_PACKAGE_TOOL) package $(APP_ZIP_FILE) \
		-n $(APP_NAME)/$(APP_VERSION) \
		-k $(APP_KEY_FILE) \
		-p "$$PASSWD" \
		-o $(APP_PKG_FILE)

	@rm $(APP_KEY_PASS_TMP)

	@$(ECHO) "$(COLOR_DONE)**** Package $(APPNAME) complete ****$(COLOR_OFF)"

# -------------------------------------------------------------------------
# teamcity: used to build .zip and .pkg file on TeamCity.
# See app-pkg target for info on options for specifying the signing password.
# -------------------------------------------------------------------------
.PHONY: teamcity
teamcity: app-pkg
ifeq ($(IS_TEAMCITY_BUILD),true)
	@$(ECHO) "Adding TeamCity artifacts..."

	sudo rm -rf /tmp/artifacts
	sudo mkdir -p /tmp/artifacts

	cp $(APP_ZIP_FILE) /tmp/artifacts/$(APP_NAME)-$(APP_VERSION).zip
	@$(ECHO) "##teamcity[publishArtifacts '/tmp/artifacts/$(APP_NAME)-$(APP_VERSION).zip']"

	cp $(APP_PKG_FILE) /tmp/artifacts/$(APP_NAME)-$(APP_VERSION).pkg
	@$(ECHO) "##teamcity[publishArtifacts '/tmp/artifacts/$(APP_NAME)-$(APP_VERSION).pkg']"

	@$(ECHO) "TeamCity artifacts complete."
else
	@$(ECHO) "Not running on TeamCity, skipping artifacts."
endif

##########################################################################

# -------------------------------------------------------------------------
# CHECK_NATIVE_TARGET is used to check if the Roku simulator is
# configured.
# -------------------------------------------------------------------------
define CHECK_NATIVE_TARGET
	if [ -z "$(ROKU_NATIVE_DEV)" ]; then \
		$(ECHO) "$(COLOR_ERROR)ERROR: ROKU_NATIVE_DEV not defined$(COLOR_OFF)"; \
		exit 1; \
	fi
	if [ ! -d "$(ROKU_NATIVE_DEV)" ]; then \
		$(ECHO) "$(COLOR_ERROR)ERROR: native dev dir not found: $(ROKU_NATIVE_DEV)$(COLOR_OFF)"; \
		exit 1; \
	fi
	if [ ! -d "$(NATIVE_DIST_DIR)" ]; then \
		$(ECHO) "$(COLOR_ERROR)ERROR: native build dir not found: $(NATIVE_DIST_DIR)$(COLOR_OFF)"; \
		exit 1; \
	fi
endef

# -------------------------------------------------------------------------
# install-native: install the app as the dev channel on the Roku simulator.
# -------------------------------------------------------------------------
.PHONY: install-native
install-native: $(APPNAME) check
	@$(CHECK_NATIVE_TARGET)
	@$(ECHO) "$(COLOR_START)Installing $(APPNAME) to native.$(COLOR_OFF)"
	@if [ ! -d "$(NATIVE_DEV_REL)" ]; then \
		mkdir "$(NATIVE_DEV_REL)"; \
	fi
	@$(ECHO) "Source is $(APP_ZIP_FILE)"
	@$(ECHO) "Target is $(NATIVE_DEV_PKG)"
	@cp $(APP_ZIP_FILE) $(NATIVE_DEV_PKG)
	@$(NATIVE_TICKLER)

# -------------------------------------------------------------------------
# remove-native: uninstall the dev channel from the Roku simulator.
# -------------------------------------------------------------------------
.PHONY: remove-native
remove-native:
	@$(CHECK_NATIVE_TARGET)
	@$(ECHO) "$(COLOR_START)Removing $(APPNAME) from native.$(COLOR_OFF)"
	@rm $(NATIVE_DEV_PKG)
	@$(NATIVE_TICKLER)

##########################################################################

# -------------------------------------------------------------------------
# art-jpg-opt: compress any jpg files in the source tree.
# Used by the art-opt target.
# -------------------------------------------------------------------------
APPS_JPG_ART=`\find . -name "*.jpg"`

.PHONY: art-jpg-opt
art-jpg-opt:
	p4 edit $(APPS_JPG_ART)
	for i in $(APPS_JPG_ART); \
	do \
		TMPJ=`mktemp` || return 1; \
		$(ECHO) "Optimizing $$i"; \
		jpegtran -copy none -optimize -outfile $$TMPJ $$i && mv -f $$TMPJ $$i; \
	done
	p4 revert -a $(APPS_JPG_ART)

# -------------------------------------------------------------------------
# art-png-opt: compress any png files in the source tree.
# Used by the art-opt target.
# -------------------------------------------------------------------------
APPS_PNG_ART=`\find . -name "*.png"`

.PHONY: art-png-opt
art-png-opt:
	p4 edit $(APPS_PNG_ART)
	for i in $(APPS_PNG_ART); \
	do \
		$(ECHO) "Optimizing $$i"; \
		optipng -strip all -quiet $$i; \
	done
	p4 revert -a $(APPS_PNG_ART)

# -------------------------------------------------------------------------
# art-opt: compress any png and jpg files in the source tree using
# lossless compression options.
# This assumes a Perforce client/workspace is configured.
# Modified files are opened for edit in the default changelist.
# -------------------------------------------------------------------------
.PHONY: art-opt
art-opt: art-png-opt art-jpg-opt

##########################################################################

# -------------------------------------------------------------------------
# tr: this target is used to update translation files for an application
#
# Preconditions: 'locale' subdirectory must be present
# Also there must be a locale subdirectory for each desired locale to be output,
# e.g. en_US, fr_CA, es_ES, de_DE, ...
#
# MAKE_TR_OPTIONS may be set to [-t] [-d] etc. in the external environment,
# if needed.
#
# -n => don't add fake translation placeholders, e.g. 'esES: OK'.
# Instead, leave the translation empty so it will only get used when
# an actual translation is provided.
# -------------------------------------------------------------------------
MAKE_TR_OPTIONS ?= -n
.PHONY: tr
tr:
	@if [ ! -d locale ]; then \
		echo "Creating locale directory"; \
		mkdir locale; \
	fi
	@if [ ! -d locale/en_US ]; then \
		echo "Creating locale/en_US directory"; \
		mkdir locale/en_US; \
	fi
ifneq ($(P4CLIENT),)
	@-p4 edit locale/.../translations.xml > /dev/null 2>&1
endif
	@echo "========================================"
	@$(MAKE_TR_TOOL) $(MAKE_TR_OPTIONS)
	@echo "========================================"
ifneq ($(P4CLIENT),)
	@-p4 add locale/*/translations.xml > /dev/null 2>&1
	@-p4 revert locale/en_US/translations.xml > /dev/null 2>&1
	@-p4 revert -a locale/.../translations.xml > /dev/null 2>&1
	@-p4 opened -c default
endif

##########################################################################

