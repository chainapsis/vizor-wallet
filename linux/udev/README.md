# Ledger USB on Linux

Vizor supports Ledger over USB on Zcash mainnet. Bluetooth is not available on
Windows or Linux. Unlock the Ledger and open its Zcash app (3.9.3 or newer).

If the device is connected but Vizor cannot access it, install the supplied udev
rule on the host. From this directory:

```sh
sudo install -m 0644 70-vizor-ledger.rules /etc/udev/rules.d/70-vizor-ledger.rules
sudo udevadm control --reload-rules
```

Unplug and reconnect the Ledger afterward. Run Vizor as your normal desktop
user. The rule grants access to the active local seat through `uaccess`; it does
not grant every user access. Existing Ledger udev rules may already grant access.
Systems without a systemd/logind local seat need their distribution's device
permission setup instead. See https://github.com/LedgerHQ/udev-rules.

The rule is included in Linux bundles under `data/ledger-usb`. For an AppImage,
run `./Vizor-linux-<arch>.AppImage --appimage-extract` and find it under
`squashfs-root/usr/bin/data/ledger-usb`. AppImage packaging does not install host
udev rules automatically. Installing the rules does not change device pairing or
wallet data.
