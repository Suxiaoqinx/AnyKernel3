### AnyKernel3 Ramdisk Mod ScriptMore actions
## osm0sis @ xda-developers & GitHub @ Xiaomichael

### AnyKernel setup
# global properties
properties() { '
kernel.string=KernelSU by KernelSU Developers | Build by Suxiaoqingx
do.devicecheck=0
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=
device.name2=
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

### AnyKernel install
## boot shell variables
block=boot
is_slot_device=auto
ramdisk_compression=auto
patch_vbmeta_flag=auto
no_magisk_check=1

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh

ui_print ""
ui_print "-> 开始执行刷机脚本... ✨"
ui_print "↓↓↓👇向下滑动解锁👇↓↓↓" 
ui_print "----------------------------------------"
ui_print "-> 检测设备信息..."
ui_print "-> 设备信息："
ui_print "   设备名称: $(getprop ro.product.device)"
ui_print "   设备型号: $(getprop ro.product.model)"
ui_print "   Android 版本: $(getprop ro.build.version.release)"
ui_print "   内核版本: $(uname -r)"

if [ -d /data/adb/magisk -a -f $AKHOME/magisk_patched ]; then
    ui_print "注意❗Magisk/Alpha直接刷入可能有奇怪的问题，建议完全卸载后安装❗"
    ui_print ""
    ui_print "-> 检测到 Magisk/Alpha 环境，是否继续？"
    ui_print "   音量上键/下键：退出安装 ❌"
    ui_print "   5秒无操作将自动继续 ▶️"

    timeout=5
    key_pressed=false
    for i in $(seq $timeout); do
        key_output=$(getevent -qlc 1 2>/dev/null)
        if [ -n "$key_output" ]; then
            key=$(echo "$key_output" | awk '{print $3}')
            case "$key" in
                "KEY_VOLUMEUP" | "KEY_VOLUMEDOWN")
                    key_pressed=true
                    break
                    ;;
            esac
        fi
        sleep 1
        ui_print "   ⏳ 剩余时间: $((timeout - i))秒"
    done

    if [ "$key_pressed" = true ]; then
        abort "-> 用户选择退出安装（检测到 Magisk/Alpha 环境）❌"
    else
        ui_print "-> 无操作，继续安装（风险自负）⚠️"
    fi
fi

ui_print ""
ui_print "-> 正在尝试删除冲突部分..."

clean_targets="
/data/adb/modules/zygisk_shamiko|卸载Zygisk-Shamiko模块
/data/adb/shamiko|清理Shamiko残留文件
/data/adb/magisk.db|移除Magisk数据库
"

echo "$clean_targets" | while read -r target; do
    if [ -z "$target" ]; then
        continue
    fi

    path=$(echo "$target" | cut -d '|' -f 1)
    message=$(echo "$target" | cut -d '|' -f 2)

    if [ -e "$path" ]; then
        ui_print "▸ 正在处理: $message"
        target_name=$(basename "$path")

        if rm -rf "$path" 2>/dev/null; then
            ui_print "✅ 清理成功: $target_name"
            case "$target_name" in
                "zygisk_shamiko"|"shamiko")
                    ui_print "   ▸ 已卸载shamiko，susfs和它不兼容也不需要"
                    ;;
                "magisk.db")
                    ui_print "   ▸ 注意: Magisk配置可能需要手动清除"
                    ;;
                "zram"|"ksu_zram")
                    ui_print "   ▸ 旧版ZRAM模块已移除"
                    ;;
            esac
        else
            ui_print "⚠️ 清理失败: $target_name (可能需要手动删除)"
        fi
    else
        ui_print "ℹ️ 未发现: $(basename "$path")"
    fi
done

ui_print "✔️ 冲突模块处理完成"

kernel_version=$(cat /proc/version | awk -F '-' '{print $1}' | awk '{print $3}')
case $kernel_version in
    5.1*) ksu_supported=true ;;
    6.1*) ksu_supported=true ;;
    6.6*) ksu_supported=true ;;
    *) ksu_supported=false ;;
esac

ui_print "内核构建者: Coolapk@Suxiaoqing"
ui_print " " "  -> ksu_supported: $ksu_supported"
$ksu_supported || abort "  -> Non-GKI device, abort."

# 设置路径（提前定义，确保即使跳过补丁后续也能用）
IMG_SRC="$AKHOME/Image"
PATCH_BIN="$AKHOME/patch_android"

# 进入 KPM 补丁选择阶段
ui_print "-> 进入 KPM 补丁选择阶段"

KPM_PATCH_SUCCESS=false
KPM_RETRIES=0
MAX_RETRIES=3

# 修改：如果跳过补丁，直接继续执行后续流程
ui_print "-> 是否应用 KPM 补丁？"
ui_print "   音量上键：应用 👍"
ui_print "   音量下键：跳过 👎"
SKIP_PATCH=1

timeout=10
key_pressed=false
detected_key=""
end_time=$(( $(date +%s) + timeout ))

while [ $(date +%s) -lt $end_time ]; do
    key_output=$(getevent -qlc 1 2>/dev/null)
    if [ -n "$key_output" ]; then
        key=$(echo "$key_output" | awk '{print $3}')
        case "$key" in
            "KEY_VOLUMEUP" | "KEY_VOLUMEDOWN")
                detected_key="$key"
                key_pressed=true
                break
                ;;
        esac
    fi
    sleep 0.1
done

if [ "$key_pressed" = true ]; then
    if [ "$detected_key" = "KEY_VOLUMEUP" ]; then
        SKIP_PATCH=0
        ui_print "-> 用户选择：应用 KPM 补丁"
    else
        SKIP_PATCH=1
        ui_print "-> 用户选择：跳过 KPM 补丁"
    fi
else
    ui_print "-> 未检测到按键，默认为跳过 KPM 补丁"
fi

# 无论是否跳过KPM补丁，都继续执行后续流程
if [ "$SKIP_PATCH" -eq 0 ]; then
    # 如果选择应用 KPM 补丁，则开始应用补丁
    ui_print ""
    ui_print "-> 开始应用 KPM 补丁... 🩹"
    [ ! -f "$PATCH_BIN" ] && abort "ERROR：找不到补丁工具 $PATCH_BIN ❌"
    TMPDIR="/data/local/tmp/kpm_patch_$(date +%Y%m%d_%H%M%S)_$$"
    mkdir -p "$TMPDIR" || abort "ERROR：创建临时目录失败 ❌"
    cp "$IMG_SRC" "$TMPDIR/" || abort "ERROR：复制 Image 失败 ❌"
    cp "$PATCH_BIN" "$TMPDIR/" || abort "ERROR：复制 patch_android 失败 ❌"
    chmod +x "$TMPDIR/patch_android"
    cd "$TMPDIR" || abort "ERROR: 切换到临时目录失败 ❌"

    ui_print "-> 执行 patch_android..."
    ./patch_android
    PATCH_EXIT_CODE=$?

    ui_print "-> patch_android 执行返回码: $PATCH_EXIT_CODE"

    if [ "$PATCH_EXIT_CODE" -eq 0 ]; then
        [ ! -f "oImage" ] && abort "ERROR：补丁生成失败，未找到 oImage ❌"
        mv oImage Image
        cp Image "$AKHOME" || abort "ERROR：复制 Image 到目标失败 ❌"
        ui_print "-> KPM 补丁应用完成 🎉"
        KPM_PATCH_SUCCESS=true
        rm -rf "$TMPDIR"
    else
        ui_print "ERROR：补丁应用失败 ❌"
        ui_print "-> 尝试重试补丁应用... 🛠️"
        rm -rf "$TMPDIR"
    fi
else
    ui_print "-> 跳过 KPM 补丁应用，继续执行后续流程"
fi

# ✅ ZRAM 安装逻辑（不会被补丁跳过影响）
ui_print ""
ui_print "-> 进入 ZRAM 模块安装阶段"
ui_print ""
ui_print "-> 是否安装 ZRAM 模块？"
ui_print "用于管理/支持官方不支持的ZRAM"
ui_print ""
ui_print "   音量上键：安装 👇"
ui_print "   音量下键：跳过 👆"
INSTALL_ZRAM=0
timeout=10
key_pressed=false
detected_key=""
end_time=$(( $(date +%s) + timeout ))

while [ $(date +%s) -lt $end_time ]; do
    key_output=$(getevent -qlc 1 2>/dev/null)
    if [ -n "$key_output" ]; then
        key=$(echo "$key_output" | awk '{print $3}')
        case "$key" in
            "KEY_VOLUMEDOWN" | "KEY_VOLUMEUP")
                detected_key="$key"
                key_pressed=true
                break
                ;;
        esac
    fi
    sleep 0.1
done

if [ "$key_pressed" = true ]; then
    if [ "$detected_key" = "KEY_VOLUMEUP" ]; then
        INSTALL_ZRAM=1
        ui_print "-> 用户选择：安装 ZRAM 模块"
    else
        INSTALL_ZRAM=0
        ui_print "-> 用户选择：跳过 ZRAM 模块安装"
    fi
else
    ui_print "-> 未检测到按键，默认为跳过 ZRAM 模块安装"
fi

if [ "$INSTALL_ZRAM" -eq 1 ]; then
    ui_print ""
    ui_print "-> 开始安装 ZRAM 模块 'zram.zip'... 📦"
    MODULE_ZIP="$AKHOME/zram.zip"
    KSUD_PATH="/data/adb/ksud"

    if [ ! -f "$MODULE_ZIP" ]; then
        ui_print "ERROR：找不到模块文件 $MODULE_ZIP，跳过安装 ❌"
    elif [ ! -x "$KSUD_PATH" ]; then
        ui_print "ERROR：ksud 工具不可执行，请确保已正确安装KernelSU ❌"
    else
        ui_print "-> 正在执行模块安装命令..."
        "$KSUD_PATH" module install "$MODULE_ZIP"
        if [ $? -eq 0 ]; then
            ui_print "✅ ZRAM 模块安装成功！"
        else
            ui_print "⚠️ 模块安装失败，请检查日志 ❌"
        fi
    fi
fi

# ------------------------- 新增的 SUSFS 模块安装部分 ------------------------

ui_print ""
ui_print "-> 进入 SUSFS 模块安装阶段"
ui_print ""
ui_print "-> 是否安装 SUSFS 模块？"
ui_print "用于支持 SUSFS 文件系统"
ui_print ""
ui_print "   音量上键：安装 👇"
ui_print "   音量下键：跳过 👆"
INSTALL_SUSFS=0
timeout=10
key_pressed=false
detected_key=""
end_time=$(( $(date +%s) + timeout ))

while [ $(date +%s) -lt $end_time ]; do
    key_output=$(getevent -qlc 1 2>/dev/null)
    if [ -n "$key_output" ]; then
        key=$(echo "$key_output" | awk '{print $3}')
        case "$key" in
            "KEY_VOLUMEDOWN" | "KEY_VOLUMEUP")
                detected_key="$key"
                key_pressed=true
                break
                ;;
        esac
    fi
    sleep 0.1
done

if [ "$key_pressed" = true ]; then
    if [ "$detected_key" = "KEY_VOLUMEUP" ]; then
        INSTALL_SUSFS=1
        ui_print "-> 用户选择：安装 SUSFS 模块"
    else
        INSTALL_SUSFS=0

        ui_print "-> 用户选择：跳过 SUSFS 模块安装"
    fi
else
    ui_print "-> 未检测到按键，默认为跳过 SUSFS 模块安装"
fi


if [ "$INSTALL_SUSFS" -eq 1 ]; then
    ui_print ""
    ui_print "-> 开始安装 SUSFS 模块 'ksu_module_susfs.zip'... 📦"
    MODULE_SUSFS_ZIP="$AKHOME/ksu_module_susfs.zip"
    KSUD_PATH="/data/adb/ksud"

    if [ ! -f "$MODULE_SUSFS_ZIP" ]; then
        ui_print "ERROR：找不到模块文件 $MODULE_SUSFS_ZIP，跳过安装 ❌"
    elif [ ! -x "$KSUD_PATH" ]; then
        ui_print "ERROR：ksud 工具不可执行，请确保已正确安装KernelSU ❌"
    else
        ui_print "-> 正在执行模块安装命令..."
        "$KSUD_PATH" module install "$MODULE_SUSFS_ZIP"
        if [ $? -eq 0 ]; thenMore actions
            ui_print "✅ SUSFS 模块安装成功！"
        else
            ui_print "⚠️ 模块安装失败，请检查日志 ❌"
        fi
    fi
fi

# ------------------------- 安装完毕 ------------------------

ui_print "----------------------------------------"
ui_print "刷机脚本执行完毕，请重启设备以应用更改 🎉"
ui_print "----------------------------------------"
exit 0
