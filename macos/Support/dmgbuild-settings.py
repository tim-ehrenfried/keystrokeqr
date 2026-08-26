# dmgbuild settings for the KeystrokeQR Host DMG.
#
# dmgbuild writes the Finder window layout (.DS_Store: background image,
# icon positions, window size) programmatically — no Finder/AppleScript
# involved, so the styled DMG builds identically on headless CI runners.
# Invoked by Support/make-dmg.sh via:
#   python3 -m dmgbuild -s Support/dmgbuild-settings.py \
#     -D app=<path>.app -D background=<png> -D icns=<icns> <volname> <out.dmg>
import os.path

app = defines.get("app", "dist/KeystrokeQR Host.app")  # noqa: F821
app_name = os.path.basename(app)

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}

# Volume icon (brand icon on the mounted volume and the DMG file itself).
icon = defines.get("icns")  # noqa: F821

# Window: 600x400 at (200,120) — matches Support/dmg-background.png (600x400).
window_rect = ((200, 120), (600, 400))
background = defines.get("background")  # noqa: F821
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = 110
text_size = 13
icon_locations = {
    app_name: (150, 205),
    "Applications": (450, 205),
}
