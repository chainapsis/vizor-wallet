# Touch ID icon

`assets/icons/touch_id.svg` contains Apple's SF Symbols `touchid` geometry,
exported at Semibold weight, Medium scale, and 17-point optical size. It is a
filled vector path, not a traced or embedded bitmap. Use it for iOS Touch ID;
Android fingerprint authentication retains the Material fingerprint icon.

Source: https://developer.apple.com/sf-symbols/

The local macOS symbol renderer was exported using
https://github.com/yapstudios/sfsym at
`b27db2f92a71281b1f0e755147224dd071d03e26`:

```sh
sfsym export touchid --weight semibold --size 17 --viewbox tight -o touchid.svg
```

The tight bounds were centered in a square, then uniformly scaled to the
existing Face ID asset's `0 0 16.6667 16.6667` viewBox. The exporter retains a
small antialiasing margin. Shape proportions and Apple's outlines are unchanged.
Regular, Medium, and Semibold were compared at 16 and 24 logical pixels;
Semibold was chosen for legibility alongside the heavier Face ID artwork.

The export utility is development tooling only. There is no new package or
native runtime API dependency. `AppIcon` supplies size and theme color through
its existing SVG renderer. No PNG density variants are needed.
