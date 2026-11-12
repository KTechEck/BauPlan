# Baut aus den PNGs von test/logo_test.dart das Windows-Symbol (.ico) und
# verteilt die iOS-Symbole. Aufruf im Code-Ordner: python tools/logo_einbauen.py <PNG-Ordner>
import json, os, shutil, struct, sys

quelle = sys.argv[1]

# .ico mit eingebetteten PNGs
groessen = [16, 24, 32, 48, 64, 128, 256]
bilder = [open(os.path.join(quelle, 'rund_%d.png' % g), 'rb').read() for g in groessen]
kopf = struct.pack('<HHH', 0, 1, len(groessen))
versatz = 6 + 16 * len(groessen)
eintraege = b''
for g, b in zip(groessen, bilder):
    eintraege += struct.pack('<BBBBHHII', g % 256, g % 256, 0, 0, 1, 32, len(b), versatz)
    versatz += len(b)
with open('windows/runner/resources/app_icon.ico', 'wb') as f:
    f.write(kopf + eintraege + b''.join(bilder))

# iOS: Größen aus Contents.json
ordner = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
inhalt = json.load(open(os.path.join(ordner, 'Contents.json'), encoding='utf-8'))
for bild in inhalt['images']:
    if 'filename' not in bild:
        continue
    px = round(float(bild['size'].split('x')[0]) * int(bild['scale'][0]))
    shutil.copyfile(os.path.join(quelle, 'voll_%d.png' % px), os.path.join(ordner, bild['filename']))

os.makedirs('assets/logo', exist_ok=True)
shutil.copyfile(os.path.join(quelle, 'rund_512.png'), 'assets/logo/bauspur_logo.png')
print('Logo eingebaut')
