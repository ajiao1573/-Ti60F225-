import inspect
import run_plate_locator as m
source=inspect.getsource(m.verify).replace("[9:0]","[10:0]")
exec(source,m.__dict__)
p=m.glyph_edges(1920,1080,1320,1032,32,32,48)
m.verify("native_locator_bottom",1920,1080,[p],gaps=False)
