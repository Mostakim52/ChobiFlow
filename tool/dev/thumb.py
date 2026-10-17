import sys
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
base = r"C:\Users\Rubu\AppData\Local\Temp\opencode\\"
im = Image.open(base + src)
print(im.size)
im.thumbnail((480, 1100))
im.save(base + dst)
print("saved", im.size)
