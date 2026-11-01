from plate_reference import sample,run_cases,W,H,M
from PIL import Image
cases=[('six',sample('AUY359'),6,128),('inverse',sample('DMN112',True),6,128),
       ('border_noise',sample('TR7750',border=True,noise=True),6,128),
       ('blank',Image.new('L',(W,H),180),0,128),('eight',sample('A1B2C3D4',size=42),8,128),
       ('overflow',sample('A1B2C3D4E',size=38),0,128),('adjust',sample('OI7105'),6,133)]

run_cases(cases,'plate_seg')
