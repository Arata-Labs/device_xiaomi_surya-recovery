LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
    LOCAL_MODULE := dfe_prebuilt
    LOCAL_MODULE_TAGS := optional
    LOCAL_SRC_FILES := force_disable_encryption.sh
    LOCAL_MODULE_PATH := $(TARGET_RECOVERY_ROOT_OUT)/customfeatures/dfe
    LOCAL_MODULE_CLASS := EXECUTABLES
    LOCAL_MODULE_MODE := 0755
include $(BUILD_PREBUILT)
