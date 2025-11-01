#!/sbin/sh
#
# DFE Standalone for TWRP & addon.d
# Created by HinohArata
# Don't forget join @ArataXDummy
#

# --- GLOBAL VAR ---
BACKED_UP_FILES=""
dynamic=`getprop ro.boot.dynamic_partitions`

prin() {
    echo -e "ui_print $1\nui_print"
}

abort() {
    prin "$1" && exit 1
}

rollback() {
    prin "| ! SCRIPT FAILED! Starting rollback..."
    if ! mountpoint -q /vendor; then
        if [ "$dynamic" = "true" ]; then
            mount -o rw -t auto /dev/block/mapper/vendor /vendor 2>/dev/null
        fi
    fi
    for file_bak in $BACKED_UP_FILES; do
        local file_orig="${file_bak%.bak}"
        if [ -f "$file_bak" ]; then
            prin "| > Restoring $file_orig from $file_bak..."
            mv "$file_bak" "$file_orig"
        else
            prin "| ! Backup $file_bak not found. Cannot restore $file_orig."
        fi
    done
    prin "| Rollback complete."
    vndumnt
    exit 1
}

mount_sys() {
    prin "| Checking system_root mount..."
    if ! mountpoint -q /system_root; then
        prin "| Mounting /system_root (rw)..."
        mount -o rw /system_root >/dev/null 2>&1
        mount -o remount,rw /system_root >/dev/null 2>&1
    else
        prin "| /system_root already mounted. Ensuring RW..."
        mount -o remount,rw /system_root >/dev/null 2>&1
    fi
}

vndmnt() {
    prin "| Checking vendor mount..."
    if ! mountpoint -q /vendor; then
        prin "| /vendor not mounted. Mounting..."
        if [ "$dynamic" = "true" ]; then
            prin "| Dynamic partition detected";
            mount -o ro -t auto /dev/block/mapper/vendor /vendor
        else
            abort "| Dynamic partitions not detected, aborting..."
        fi
    else
        prin "| /vendor is already mounted."
    fi
    prin "| Ensuring /vendor is RW..."
    blockdev --setrw /dev/block/mapper/vendor 2>/dev/null
    mount -o remount,rw -t auto /vendor
}

vndumnt() {
    umount /product 2>/dev/null
    umount /vendor 2>/dev/null
    umount /system_root 2>/dev/null
}

patchfs() {
    local fstab_files=""
    local fstab_list="/vendor/etc/fstab.qcom /vendor/etc/fstab.emmc /vendor/etc/fstab.default"
    
    for f in $fstab_list; do
        if [ -f "$f" ]; then
            fstab_files="$fstab_files $f"
        fi
    done
    if [ -z "$fstab_files" ]; then
        prin "| ! Error: Cannot find fstab (qcom, emmc, or default) in /vendor/etc."
        return 1
    fi
    prin "| Found fstab: $fstab_files"

    if [ -f /system_root/system/build.prop ]; then
        vndk=$(grep ro.system.build.version.sdk= /system_root/system/build.prop 2>/dev/null | cut -d= -f2)
    else
        prin "| ! Warning: /system_root/system/build.prop not found. Skipping VNDK check."
        vndk="unknown"
    fi
    prin "| VNDK version: ${vndk}"
    sleep 1

    for fstab_path in $fstab_files; do
        prin "--------------------------------------"
        prin "| Processing: $fstab_path"
        if [ ! -w "$fstab_path" ]; then
            prin "| ! Error: $fstab_path is not writable."
            return 1
        else
            prin "| $fstab_path is writable."
            prin "| Backup original fstab..."
            local fstab_bak="${fstab_path}.bak"
            if [ -f "$fstab_bak" ]; then
                prin "| $fstab_bak already exists."
            else
                cp $fstab_path "$fstab_bak"
                BACKED_UP_FILES="$BACKED_UP_FILES $fstab_bak"
                prin "| Backup created: $fstab_bak"
            fi
            sleep 1
        fi

        prin "| Patching $fstab_path (RO2RW DFE)..."
        local fstab="$fstab_path"
        tabul="
"
        g=$(echo "fileencryption= forcefdeorfbe= encryptable= forceencrypt= metadata_encryption= keydirectory= avb= avb_keys=")
        g2=$(echo "avb quota inlinecrypt wrappedkey emmc_optimized")

        prin "| Patching (Phase 1)..."
        while ($(for i in $g; do grep -q "$i" $fstab && return 0; done; return 1)); do
            fstabp_now=$(cat "$fstab")
            for remove in $g; do
                if grep -q "$remove" "$fstab"; then
                    remove_now="${fstabp_now#*"$remove"}"
                    remove_now="${remove_now%%,*}"
                    remove_now="${remove}${remove_now%%"$tabul"*}"
                } else { continue; }
                prin "| - Attempting to remove: $remove_now"
                local content_before_sed=$(cat "$fstab")
                if grep -q ",$remove_now" "$fstab"; then
                    sed -i 's|,'$remove_now'||' $fstab
                elif grep -q "$remove_now" "$fstab"; then
                    sed -i 's|'$remove_now'||' $fstab
                else
                    prin "|   > Flag format not found. Skipping."
                    continue
                fi
                local content_after_sed=$(cat "$fstab")
                if [ "$content_before_sed" != "$content_after_sed" ]; then
                    prin "|   > Success."
                else
                    prin "|   > ! FAILED. (sed command had no effect)"
                fi
                sleep 0.5
            done
        done

        prin "| Patching (Phase 2)..."
        if ($(for i in $g2; do grep -q "$i" $fstab && return 0; done; return 1)); then
            for remove in $g2; do
                if grep -q "$remove" "$fstab"; then
                    prin "| - Attempting to remove flag: $remove"
                    local content_before_sed=$(cat "$fstab")
                    sed -i 's|,'$remove'||g' $fstab &>/dev/null
                    sed -i 's|'$remove',||g' $fstab &>/dev/null
                    sed -i 's|'$remove'||g' $fstab &>/dev/null
                    local content_after_sed=$(cat "$fstab")
                    if [ "$content_before_sed" != "$content_after_sed" ]; then
                        prin "|   > Success."
                    else
                        prin "|   > No change detected (or failed)."
                    fi
                    sleep 0.5
                fi
            done
        fi
        prin "| Finished patching $fstab_path"
    done
}

setup_addond() {
    prin "| Setting up addon.d ..."
    local addond_path="/system_root/system/addon.d"
    local target_script="$addond_path/99-dynDFE.sh"

    if [ ! -d "$addond_path" ]; then
        prin "| ! addon.d path not found. Creating..."
        mkdir -p "$addond_path"
    fi

    if [ ! -w "$addond_path" ]; then
        prin "| ! Can't write to addon.d (mount failed?)"
    else
        prin "| addon.d path is writable."
        cp "$0" "$target_script"
    fi
}

unencrypt() {
    trap 'rollback' ERR
    prin "========================================"
    prin "=       Disable Force Encryption       ="
    prin "=         script by HinohArata         ="
    prin "=        Join to Telegram group        ="
    prin "=             @ArataXDummy             ="
    prin "========================================"

    sleep 2
    
    vndumnt
    vndmnt
    mount_sys
    patchfs

    [ -f "$0" ] && setup_addond

    prin "| Unmounting filesystem..."
    sleep 1
    vndumnt
    trap - ERR
    prin " "
    prin "| DFE Patching finished successfully."
}

case "$1" in
    post-restore|addond-v2)
        unencrypt
    ;;
    "")
        unencrypt
    ;;
    *)
        prin "| ! Unknown argument: $1"
        prin "| ! Aborting."
        exit 1
    ;;
esac

exit 0
