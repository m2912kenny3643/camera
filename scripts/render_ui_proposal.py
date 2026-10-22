"""Deterministic design proposals, NOT screenshots of the running app.

Manual references: pp.99-100, 433, 495, 576-579, 1051-1052.
Run with Pillow; fonts are Windows Microsoft JhengHei, overridable via R6_FONT.
"""
import math
import os
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT = Path('docs/design/0.4')
OUT.mkdir(parents=True, exist_ok=True)
FONT = os.environ.get('R6_FONT', 'C:/Windows/Fonts/msjh.ttc')
W, H = 1600, 720
WHITE, AMBER, RED, MAGENTA, CYAN = '#ffffff', '#ffce00', '#f13b39', '#ed30a0', '#55e8ff'

def text(d, xy, label, size=24, color=WHITE, anchor=None):
    d.text(xy, label, font=ImageFont.truetype(FONT, size), fill=color, anchor=anchor)

def box(d, rect, label='', color=WHITE, selected=False, size=24):
    d.rectangle(rect, fill='#080808', outline=color if selected else '#808080', width=3 if selected else 1)
    if label: text(d, ((rect[0]+rect[2])/2,(rect[1]+rect[3])/2), label, size, CYAN if selected else WHITE, 'mm')

def drive(d,x,y,label='',color=WHITE):
    if label.startswith('10') or label=='2':
        d.ellipse((x,y,x+27,y+27),outline=color,width=2)
        d.line((x+13,y+3,x+13,y+13,x+20,y+17),fill=color,width=2)
    else:
        if label: d.rectangle((x+6,y-5,x+35,y+19),outline=color,width=2)
        d.rectangle((x,y,x+29,y+24),outline=color,width=2)
    if label: text(d,(x+43,y-3),label,25,color)

def back(d,x,y):
    d.line((x+30,y+20,x+30,y+6,x,y+6),fill=WHITE,width=3)
    d.line((x+9,y-2,x,y+6,x+9,y+14),fill=WHITE,width=3)

def scene():
    im = Image.new('RGB', (W,H), '#34483d'); d = ImageDraw.Draw(im)
    # Same deliberately synthetic subject in every proposal: no apparent model accuracy claim.
    for y in range(H):
        d.line((0,y,W,y), fill=(45+y//22, 64+y//35, 52+y//40))
    d.polygon([(0,570),(W,490),(W,650),(0,650)], fill='#4b5543')
    d.ellipse((640,110,830,310), fill='#b4a58b')
    d.rectangle((590,290,880,650), fill='#728c85')
    return im

def level(d, small=False, roll=0, pitch=0):
    cx,cy,r=800,350,75 if small else 140
    color='#31ed75' if abs(roll)<1 and abs(pitch)<1 else WHITE
    d.arc((cx-r,cy-r,cx+r,cy+r),145,215,fill=WHITE,width=3)
    d.arc((cx-r,cy-r,cx+r,cy+r),-35,35,fill=WHITE,width=3)
    for x in [-1,1]:
        d.line((cx+x*30,cy,cx+x*r,cy),fill=color,width=3)
    d.rectangle((cx-9,cy-4,cx+9,cy+4),outline=color,width=2)
    for dy in [-30,30]: d.line((cx-12,cy+dy,cx+12,cy+dy),fill=WHITE,width=2)

def hud(im, dial=False, show_level=False):
    d=ImageDraw.Draw(im)
    left=[('M',48),('[ · ]',24),('SERVO AF',19),('',25),('',25),('FULL',20)]
    y=18
    for label,size in left: text(d,(32,y),label,size); y+=70 if size==48 else 64
    right=[('Q',32),('AWB',24),('[ S ]',25),('[ ⊙ ]',24),('動物',22),('1×',26)]
    for i,(label,size) in enumerate(right):
        if not dial or i==0: box(d,(1470,20+i*91,1568,79+i*91),label,size=size)
    d.pieslice((32,215,68,251),180,270,fill=WHITE); text(d,(77,215),'L',25)
    drive(d,32,287,'H')
    d.rectangle((1210,30,1260,53),outline=WHITE,width=2)
    d.rectangle((1215,35,1250,48),fill=WHITE); text(d,(1270,24),'80%',25)
    d.rectangle((0,650,W,H),fill='black')
    d.polygon([(55,671),(55,699),(80,685)],fill=WHITE)
    for x,label in [(290,'1/1000'),(535,'F1.6'),(720,'-3..2..1..0..1..2..3+'),(1120,'ISO 400'),(1460,'MENU')]: text(d,(x,670),label,28)
    box(d,(710,205,759,254),color=CYAN,selected=True)
    text(d,(30,588),'INFO',20)
    if show_level: level(d)
    if dial:
        # Same dimensionless hub/radius as ZoomDialGeometry.
        rh=650; r=rh*.63; cx=W+r-W*.15; cy=rh*.55
        layer=Image.new('RGBA',(W,H)); ld=ImageDraw.Draw(layer)
        ld.ellipse((cx-r,cy-r,cx+r,cy+r),fill=(0,0,0,185))
        for i in range(-16,65):
            value=2**(i/16); a=math.pi+math.log2(value)*.46
            p=(cx+(r-8)*math.cos(a),cy+(r-8)*math.sin(a)); major=i%16==0
            q=(cx+(r-(31 if major else 20))*math.cos(a),cy+(r-(31 if major else 20))*math.sin(a))
            ld.line((*p,*q),fill='white' if major else '#909090',width=3 if major else 1)
            if major and value!=1:
                label=Image.new('RGBA',(150,80)); ll=ImageDraw.Draw(label)
                text(ll,(75,20),f'{value:g}×',28,anchor='mm')
                label=label.rotate(-math.degrees(a-math.pi),resample=Image.Resampling.BICUBIC,expand=True)
                x=cx+(r-78)*math.cos(a); y=cy+(r-78)*math.sin(a)
                layer.alpha_composite(label,(round(x-label.width/2),round(y-label.height/2)))
        tip=cx-r+5
        ld.polygon([(tip,cy-8),(tip+23,cy),(tip,cy+8)],fill=AMBER)
        text(ld,(tip+42,cy-20),'1×',33,AMBER)
        im=Image.alpha_composite(im.convert('RGBA'),layer).convert('RGB')
    return im

images=[]
def save(im,name,title):
    im.save(OUT/name)
    images.append((im,title))

save(hud(scene(),dial=True),'01-main.png','01 主畫面 / 右側局部圓弧轉盤')
im=hud(scene()); d=ImageDraw.Draw(im)
box(d,(32,94,130,149),'[ · ]',AMBER,True)
box(d,(1470,20,1568,79)); back(d,1500,40)
d.rectangle((150,508,1450,570),fill='#151b16'); text(d,(175,520),'自動對焦區域：全區域・觸控指定',27)
box(d,(30,580,270,637),'[ · ]',AMBER,True)
text(d,(310,590),'INFO   觸控指定目標',24)
save(im,'02-q.png','02 Q / 保留取景、側欄選取與底部選項')
im=Image.new('RGB',(W,H),'black'); d=ImageDraw.Draw(im)
for i,(label,c) in enumerate([('拍攝',RED),('AF',MAGENTA),('回放','#4891ff'),('設定',AMBER),('C','#f3a64c'),('★','#4ac979')]):
    box(d,(55+i*150,20,185+i*150,80),label,c,i==0)
d.line((40,92,1560,92),fill=RED,width=4); text(d,(60,108),'1   2   3                         拍攝設定',24)
for i,(name,value) in enumerate([('影像畫質','JPEG'),('白平衡','AWB'),('相片風格','標準'),('驅動模式','H'),('曝光補償','0'),('水平儀顯示大小','大')]):
    y=166+i*66; d.rectangle((60,y,1540,y+58),fill='#242424',outline=RED if i==3 else None,width=3)
    text(d,(82,y+11),name,27); text(d,(900,y+11),value,27,CYAN if i==3 else WHITE)
text(d,(60,662),'MENU 返回',25); text(d,(1340,662),'SET 確認',25)
save(im,'03-menu.png','03 MENU / 分類色、頁碼、左右欄')
im=Image.new('RGB',(W,H),'black'); d=ImageDraw.Draw(im)
text(d,(60,32),'自動對焦操作',36); d.line((50,97,1550,97),fill=MAGENTA,width=4)
d.rectangle((50,114,1550,180),fill='#303030'); text(d,(75,129),'SERVO AF',28)
box(d,(100,235,640,350),'ONE SHOT',MAGENTA,False,38)
box(d,(700,235,1240,350),'SERVO',MAGENTA,True,38)
text(d,(80,420),'MF 由手動對焦項目切換',23)
back(d,65,664); text(d,(115,653),'返回（取消）',25); box(d,(1320,625,1530,688),'SET OK',MAGENTA)
save(im,'04-af.png','04 AF / 洋紅分類、青色選項、SET 套用')
im=hud(scene()); d=ImageDraw.Draw(im)
d.rectangle((155,450,1450,520),fill='#171b16'); text(d,(185,467),'驅動模式   高速連拍 H（上限 2 張／秒）',27)
for i,label in enumerate(['','H+','H','L','10','2','10+']):
    box(d,(160+i*180,540,320+i*180,622),'',AMBER,i==2,29)
    drive(d,180+i*180,568,label,CYAN if i==2 else WHITE)
text(d,(185,630),'實際速度依格式、曝光與緩衝狀態調整',20)
save(im,'05-drive.png','05 驅動模式 / 單張、H+、H、L、自拍')
im=hud(scene(),show_level=True); d=ImageDraw.Draw(im)
text(d,(540,480),'電子水平儀：大 / 小，INFO 切換',25)
save(im,'06-level.png','06 水平儀 / 俯仰與左右傾斜')
sheet=Image.new('RGB',(1640,1280),'#16191c'); sd=ImageDraw.Draw(sheet)
text(sd,(24,12),'R6 Camera 0.4 — 設計提案（非 App 實際截圖）',26)
for i,(im,title) in enumerate(images):
    x=20+(i%2)*810; y=65+(i//2)*400
    text(sd,(x,y),title,22)
    sheet.paste(im.resize((790,356),Image.Resampling.LANCZOS),(x,y+35))
sheet.save(OUT/'contact-sheet.png')
print(OUT.resolve())
