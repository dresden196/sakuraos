#!/usr/bin/env python3
"""Generate the Sakura colour schemes from Breeze.

Derived rather than hand-authored: Plasma has tuned every colour in Breeze
across many releases, and the only things Sakura actually changes are the
accent and a slight warm cast on the background neutrals.

The accent differs between variants on purpose. The literal cherry blossom
pink measures 1.60:1 against a light background -- far under the 3.0:1 that
focus rings and controls require -- but 10.24:1 against a dark one. So light
gets a deep rose and dark gets the real blossom pink.

Run this to regenerate; do not hand-edit the .colors files.
"""
import pathlib
import sys

BREEZE = {"light": "/usr/share/color-schemes/BreezeLight.colors",
          "dark":  "/usr/share/color-schemes/BreezeDark.colors"}
ACCENT = {"light": "216,27,96", "dark": "255,183,197"}
SEL_FG = {"light": "252,252,252", "dark": "27,30,32"}
NAME   = {"light": "Sakura Light", "dark": "Sakura Dark"}

# Background neutrals nudged toward magenta. A neutral grey UI under a pink
# wallpaper reads as "Breeze with a photo"; a few points of cast is enough to
# feel like one system without becoming a novelty theme.
#
# Values are picked per key, never shifted algorithmically: green carries
# ~71% of perceived luminance, so nudging it blindly moves every contrast
# ratio in the scheme. Tooltip and Complementary are left alone -- in the
# light scheme they invert (dark background, light text), and tinting them
# with the light-background values makes tooltip text invisible.
TINT = {
    "dark": {
        "[Colors:Window]": "38,33,40",
        "[Colors:View]":   "26,22,28",
        "[Colors:Button]": "44,38,46",
        "[Colors:Header]": "38,33,40",
    },
    "light": {
        "[Colors:Window]": "244,239,242",
        "[Colors:View]":   "255,253,254",
        "[Colors:Button]": "244,239,242",
        "[Colors:Header]": "240,234,238",
    },
}


def lin(c):
    c = c / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def lum(t):
    r, g, b = t
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def ratio(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def rgb(s):
    return tuple(int(x) for x in s.split(","))


def build(variant, out_dir):
    src = pathlib.Path(BREEZE[variant]).read_text().splitlines()
    out, section = [], ""
    for line in src:
        st = line.strip()
        if st.startswith("[") and st.endswith("]"):
            section = st
            out.append(line)
            continue

        line = line.replace("61,174,233", ACCENT[variant])

        if section == "[Colors:Selection]" and st.startswith("ForegroundNormal="):
            line = f"ForegroundNormal={SEL_FG[variant]}"
        elif section in TINT[variant] and st.startswith("BackgroundNormal="):
            line = f"BackgroundNormal={TINT[variant][section]}"
        elif st.startswith("Name="):
            line = f"Name={NAME[variant]}"

        out.append(line)

    dest = out_dir / f"Sakura{variant.capitalize()}.colors"
    dest.write_text("\n".join(out) + "\n")

    want = [l.strip() for l in src if l.strip().startswith("[")]
    got = [l.strip() for l in out if l.strip().startswith("[")]
    missing = [s for s in want if s not in got]

    bg, cur, worst = {}, "", None
    for line in out:
        st = line.strip()
        if st.startswith("[") and st.endswith("]"):
            cur = st
        elif st.startswith("BackgroundNormal="):
            bg[cur] = rgb(st.split("=", 1)[1])
        elif st.startswith("ForegroundNormal=") and cur in bg:
            r = ratio(rgb(st.split("=", 1)[1]), bg[cur])
            if worst is None or r < worst[1]:
                worst = (cur, r)

    return dest, missing, worst


def main():
    out_dir = pathlib.Path(__file__).parent / "color-schemes"
    out_dir.mkdir(exist_ok=True)
    ok = True
    for variant in ("light", "dark"):
        dest, missing, worst = build(variant, out_dir)
        if missing:
            print(f"  {dest.name}: MISSING SECTIONS {missing}")
            ok = False
        elif worst[1] < 4.5:
            print(f"  {dest.name}: text contrast {worst[1]:.2f}:1 in {worst[0]} -- FAILS 4.5:1")
            ok = False
        else:
            print(f"  {dest.name}: all sections present, worst text contrast "
                  f"{worst[1]:.2f}:1 ({worst[0]})  OK")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
