"""Deterministic 4:3 layout proposals; these are not running-app screenshots."""
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT = Path('docs/design/0.5')
OUT.mkdir(parents=True, exist_ok=True)
W, H = 1600, 720
VIEW = (368, 0, 1232, 648)  # exactly 4:3, centered, below HUD only exposure strip.
FONT = 'C:/Windows/Fonts/msjh.ttc'
WHITE, AMBER, CYAN = '#ffffff', '#ffce00', '#62dfff'

def text(d, xy, label, size=24, color=WHITE, anchor=None):
    d.text(xy, label, font=ImageFont.truetype(FONT, size), fill=color, anchor=anchor)

def button(d, rect, label, selected=False, size=24):
    d.rounded_rectangle(rect, radius=4, fill='#151515', outline=AMBER if selected else '#707070', width=2)
    text(d, ((rect[0]+rect[2])/2, (rect[1]+rect[3])/2), label, size, CYAN if selected else WHITE, 'mm')

def base():
    im = Image.new('RGB', (W, H), 'black')
    d = ImageDraw.Draw(im)
    for y in range(648):
        d.line((368, y, 1231, y), fill=(48+y//30, 66+y//35, 55+y//40))
    # Synthetic fixture, deliberately identical dimensions to the app test fixture.
    sx, sy = 864/1200, 648/900
    def r(x,y,w,h): return (368+x*sx,y*sy,368+(x+w)*sx,(y+h)*sy)
    d.rectangle(r(0,470,1200,430), fill='#4d6152')
    d.rectangle(r(420,180,240,540), fill='#6b827a')
    d.ellipse(r(456,198,144,135), fill='#a1977a')
    d.rectangle(r(420,180,240,540), outline=WHITE, width=2)
    text(d, (800,622), '4:3 完整取景', 18, '#c0c7c1', 'mm')
    text(d, (35,22), 'M', 52)
    text(d, (35,98), '[ · ]   全區域', 23)
    text(d, (35,155), 'SERVO AF', 24)
    text(d, (35,217), 'JPEG  L', 24)
    d.rectangle((35,285,64,308), outline=WHITE, width=2)
    d.rectangle((42,279,71,302), outline=WHITE, width=2)
    text(d, (86,279), 'H+', 28)
    text(d, (35,338), '動物', 24)
    text(d, (35,395), '鳥眼：待驗證', 18, '#b0b0b0')
    button(d, (30,573,135,622), 'INFO', size=20)
    text(d, (1260,24), '80%', 22)
    button(d, (1485,18,1570,75), 'Q', size=30)
    text(d, (1260,99), 'AWB', 23)
    text(d, (1440,99), '標準', 23)
    d.line((0,648,W,648), fill='#777777', width=1)
    button(d, (25,664,114,706), '', size=25)
    d.polygon([(60,675),(60,697),(83,686)],fill=WHITE)
    for x,label in [(205,'1/1000'),(440,'F1.6'),(645,'-3..2..1..0..1..2..3+'),(1120,'ISO 400')]:
        text(d,(x,668),label,27)
    button(d, (1420,664,1572,706), 'MENU', size=24)
    return im

def dial(im):
    layer=Image.new('RGBA',im.size)
    d=ImageDraw.Draw(layer)
    cx,cy,r=1845,374,560
    d.ellipse((cx-r,cy-r,cx+r,cy+r),fill=(23,23,23,255))
    for i in range(-16,65):
        value=2**(i/16)
        a=math.pi+math.log2(value)*.46
        major=i%16==0
        p=(cx+(r-10)*math.cos(a),cy+(r-10)*math.sin(a))
        q=(cx+(r-(35 if major else 23))*math.cos(a),cy+(r-(35 if major else 23))*math.sin(a))
        d.line((*p,*q),fill=WHITE if major else '#808080',width=3 if major else 1)
        if major and value!=1:
            tile=Image.new('RGBA',(130,58))
            text(ImageDraw.Draw(tile),(65,29),f'{value:g}×',25,anchor='mm')
            tile=tile.rotate(-math.degrees(a-math.pi),resample=Image.Resampling.BICUBIC,expand=True)
            px=cx+(r-82)*math.cos(a); py=cy+(r-82)*math.sin(a)
            layer.alpha_composite(tile,(round(px-tile.width/2),round(py-tile.height/2)))
    d.polygon([(1294,cy-8),(1318,cy),(1294,cy+8)],fill=AMBER)
    text(d,(1340,cy-20),'1×',32,AMBER)
    # Dial stays entirely in the right rail, including bottom/top clipping.
    layer=layer.crop((1232,145,1600,648))
    im.paste(Image.alpha_composite(im.crop((1232,145,1600,648)).convert('RGBA'),layer).convert('RGB'),(1232,145))

main=base(); dial(main); main.save(OUT/'01-main-43.png')
quick=base(); d=ImageDraw.Draw(quick)
button(d,(25,90,330,139),'[ · ]  自動對焦區域',True,23)
button(d,(1485,18,1570,75),'返回',size=22)
d.rectangle((368,488,1231,647),fill='#111a16')
text(d,(390,505),'自動對焦區域：全區域',25)
button(d,(1070,499,1210,545),'SET',True,23)
button(d,(390,566,630,628),'全區域',True,25)
text(d,(660,584),'觸控指定目標',23)
quick.save(OUT/'02-q-43.png')
sheet=Image.new('RGB',(1640,1740),'#14181b'); d=ImageDraw.Draw(sheet)
text(d,(24,14),'R6 Camera 0.5｜4:3 版面提案（非 App 實際截圖）',30)
text(d,(24,65),'中央 864 × 648；左右控制區；右側刻度盤不遮取景。示範人物與候選框非辨識結果。',22)
for i,(im,title) in enumerate([(main,'01 主畫面｜白框候選・右側展開縮放轉盤'),(quick,'02 Q 速控｜保留 4:3 取景・暫存選項・SET 套用')]):
    y=118+i*800
    text(d,(24,y),title,26)
    sheet.paste(im,(20,y+42))
sheet.save(OUT/'contact-sheet-43.png')
print(OUT.resolve())
