#!/bin/bash
# Tạo toàn bộ kích thước AppIcon từ assets/icon/AppIcon-1024.png theo Contents.json do flutter create sinh ra.
set -e
D=ios/Runner/Assets.xcassets/AppIcon.appiconset
python3 - "$D" <<'P'
import json,sys,subprocess
d=sys.argv[1]
j=json.load(open(d+'/Contents.json'))
for im in j['images']:
    s=float(im['size'].split('x')[0]); sc=int(im['scale'].rstrip('x'))
    px=round(s*sc)
    subprocess.check_call(['sips','-z',str(px),str(px),'assets/icon/AppIcon-1024.png','--out',d+'/'+im['filename']],stdout=subprocess.DEVNULL)
P
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName 'J2ME Play'" ios/Runner/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleName 'J2ME Play'" ios/Runner/Info.plist
