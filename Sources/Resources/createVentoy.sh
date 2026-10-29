#!/bin/bash
set -euo pipefail

# -------------------------------------------------
#  createVentoy.sh – Partiziona e copia i file EFI di Ventoy su macOS
# -------------------------------------------------
# Argomento: device (es. /dev/disk2)
# -------------------------------------------------
DEVICE="$1"

# -------------------------------------------------
# 1️⃣ Verify that the device appears to be a disk (skip strict removable check)
# -------------------------------------------------
# We try to retrieve info; if it fails, we just warn and continue.
if ! diskutil info "$DEVICE" >/dev/null 2>&1; then
    echo "Warning: could not verify $DEVICE – proceeding anyway." >&2
fi

# -------------------------------------------------
# 1️⃣✱ Force unmount the whole disk before partitioning (prevents partition errors)
# -------------------------------------------------
echo "Tentativo di smontare forzatamente $DEVICE …"
# Ignore any error – we just want to ensure it's not mounted
if ! diskutil unmountDisk force "$DEVICE" 2>/dev/null; then
    echo "Warning: could not force unmount $DEVICE (it may already be unmounted)." >&2
fi

# -------------------------------------------------
# 2️⃣ Partiziona: GPT con 2 partizioni
#    • 100 MiB FAT32 (VentoyEFI) → sarà montata come EFI
#    • resto ExFAT (VentoyData)
# -------------------------------------------------

echo "Partizionamento di $DEVICE …"

diskutil partitionDisk "$DEVICE" 2 GPT \
    FAT32 VentoyEFI 100M \
    ExFAT VentoyData R

# -------------------------------------------------
# 3️⃣ Mount the EFI partition read‑write (multiple attempts)
# -------------------------------------------------
EFI_PART="${DEVICE}s1"
TMP_MOUNT="/tmp/efi_${DEVICE##*/}"
mkdir -p "$TMP_MOUNT"

# Ensure the EFI partition is unmounted before mounting it read‑write
if diskutil info "$EFI_PART" | grep -q 'Mounted: Yes'; then
    echo "Unmounting $EFI_PART before read‑write mount …"
    diskutil unmount "$EFI_PART" 2>/dev/null || true
fi

EFI_MOUNT=""

# Attempt diskutil mount (default read/write) first
if diskutil mount "$EFI_PART" >/dev/null 2>&1; then
    EFI_MOUNT="/Volumes/EFI"
else
    echo "diskutil mount failed, trying forced mount with noowners..." >&2
    if /sbin/mount -t msdos -o rw,noowners,force "$EFI_PART" "$TMP_MOUNT" >/dev/null 2>&1; then
        EFI_MOUNT="$TMP_MOUNT"
    else
        echo "Forced mount with noowners failed, trying forced mount without noowners..." >&2
        if /sbin/mount -t msdos -o rw,force "$EFI_PART" "$TMP_MOUNT" >/dev/null 2>&1; then
            EFI_MOUNT="$TMP_MOUNT"
        else
            echo "Error: could not mount $EFI_PART as read‑write (all attempts failed)" >&2
            exit 1
        fi
    fi
fi

echo "EFI mounted at $EFI_MOUNT"

# -------------------------------------------------
# 4️⃣ Crea le directory necessarie e copia i file EFI nella ESP
# -------------------------------------------------
mkdir -p "$EFI_MOUNT/EFI/BOOT"

# -------------------------------------------------
# 5️⃣ Copia i file EFI nella ESP
# -------------------------------------------------
SRC_DIR="$(dirname "$0")/EFI/BOOT"

echo "Copia dei file EFI da $SRC_DIR …"
cp -v "$SRC_DIR"/* "$EFI_MOUNT/EFI/BOOT/"

# Unmount the EFI partition (whether mounted at /Volumes/EFI or TMP_MOUNT)
if diskutil unmount "$EFI_PART" 2>/dev/null; then
    echo "EFI partition $EFI_PART unmounted successfully."
else
    echo "Warning: could not unmount $EFI_PART after copy." >&2
fi

echo "Ventoy USB creato correttamente su $DEVICE"
exit 0