from pathlib import Path
from copy import deepcopy
from zipfile import ZipFile, ZIP_DEFLATED
from io import BytesIO
import hashlib, json, re, shutil
from docx import Document
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_CELL_VERTICAL_ALIGNMENT
from docx.enum.style import WD_STYLE_TYPE
from docx.oxml import OxmlElement
from docx.oxml.ns import qn

ROOT=Path(__file__).resolve().parent.parent
WORK=ROOT/'_doc_work'
REF=WORK/'技术文档_原始模板.docx'
OUT=ROOT/'技术文档.docx'
if not REF.exists(): shutil.copy2(OUT,REF)
baseline=hashlib.sha256(REF.read_bytes()).hexdigest()
d=Document(REF)
body=d._element.body
for el in list(body):
    if el.tag!=qn('w:sectPr'): body.remove(el)

for name in ['Title','技术三级标题']:
    if name not in d.styles: d.styles.add_style(name,WD_STYLE_TYPE.PARAGRAPH)
    d.styles[name].base_style=d.styles['Normal']

def font(run,size=12,bold=False):
    run.font.name='Times New Roman'; run.font.size=Pt(size)
    run.font.bold=bold;run.font.color.rgb=RGBColor(0,0,0)
    rp=run._element.get_or_add_rPr();rf=rp.find(qn('w:rFonts'))
    if rf is None: rf=OxmlElement('w:rFonts');rp.insert(0,rf)
    for k,v in [('ascii','Times New Roman'),('hAnsi','Times New Roman'),('eastAsia','宋体'),('cs','Times New Roman')]:rf.set(qn('w:'+k),v)
    for k in ['asciiTheme','hAnsiTheme','eastAsiaTheme','cstheme']:rf.attrib.pop(qn('w:'+k),None)

def para(txt='',style='Normal',size=12,bold=False,indent=True):
    p=d.add_paragraph(style=style)
    pf=p.paragraph_format;pf.line_spacing=1.5;pf.space_before=Pt(0);pf.space_after=Pt(4)
    pf.left_indent=Pt(0);pf.right_indent=Pt(0);pf.first_line_indent=Pt(24 if indent else 0)
    pf.widow_control=True
    font(p.add_run(txt),size,bold)
    return p

def heading(txt,level=2,newpage=False):
    p=para(txt, 'Heading 1' if level==1 else 'Heading 2' if level==2 else '技术三级标题',14 if level==1 else 12,True,False)
    p.paragraph_format.space_before=Pt(5);p.paragraph_format.space_after=Pt(6)
    p.paragraph_format.keep_with_next=True;p.paragraph_format.keep_together=True
    p.paragraph_format.page_break_before=newpage
    pp=p._p.get_or_add_pPr();ol=OxmlElement('w:outlineLvl');ol.set(qn('w:val'),str(level-1));pp.append(ol)
    return p

def page(txt,level=3):return heading(txt,level,txt.startswith('第五部分'))

def table(headers,rows,widths=None,size=10.5):
    t=d.add_table(rows=1,cols=len(headers));t.alignment=WD_TABLE_ALIGNMENT.CENTER;t.autofit=False
    total=5.768
    widths=widths or [total/len(headers)]*len(headers)
    for c,w in zip(t.columns,widths):c.width=Inches(w)
    pr=t._tbl.tblPr
    borders=OxmlElement('w:tblBorders')
    for edge in ['top','left','bottom','right','insideH','insideV']:
        e=OxmlElement('w:'+edge);e.set(qn('w:val'),'single');e.set(qn('w:sz'),'4');e.set(qn('w:color'),'D9D9D9');borders.append(e)
    pr.append(borders)
    for vals,row in [(headers,t.rows[0])]+[(vals,t.add_row()) for vals in rows]:
        for j,(cell,txt,w) in enumerate(zip(row.cells,vals,widths)):
            cell.width=Inches(w);cell.vertical_alignment=WD_CELL_VERTICAL_ALIGNMENT.CENTER
            cp=cell._tc.get_or_add_tcPr();mar=OxmlElement('w:tcMar')
            for edge,val in [('top',75),('bottom',75),('left',90),('right',90)]:
                a=OxmlElement('w:'+edge);a.set(qn('w:w'),str(val));a.set(qn('w:type'),'dxa');mar.append(a)
            cp.append(mar)
            p=cell.paragraphs[0];p.paragraph_format.line_spacing=1.15;p.paragraph_format.space_after=Pt(0);p.paragraph_format.space_before=Pt(0)
            p.paragraph_format.widow_control=True;p.paragraph_format.first_line_indent=Pt(0)
            p.alignment=WD_ALIGN_PARAGRAPH.CENTER if j==0 and len(headers)>2 else WD_ALIGN_PARAGRAPH.LEFT
            font(p.add_run(str(txt)),size,row is t.rows[0])
        trpr=row._tr.get_or_add_trPr();cant=OxmlElement('w:cantSplit');trpr.append(cant)
    hdr=t.rows[0]
    repeat=OxmlElement('w:tblHeader');hdr._tr.get_or_add_trPr().append(repeat)
    for cell in hdr.cells:
        sh=OxmlElement('w:shd');sh.set(qn('w:fill'),'E7E6E6');cell._tc.get_or_add_tcPr().append(sh)
        cell.paragraphs[0].paragraph_format.keep_with_next=True
        for r in cell.paragraphs[0].runs:r.font.bold=True
    spacer=para('',size=2,indent=False);spacer.paragraph_format.line_spacing=1;spacer.paragraph_format.space_after=Pt(1)
    return t

limited={}
def limited_text(key,limit,txt):
    assert len(re.sub(r'\s','',txt))<=limit,(key,len(txt),limit)
    limited[key]={'limit':limit,'characters':len(re.sub(r'\s','',txt))}
    return para(txt)

p=para('基于 Ti60 FPGA 的边缘处理与多任务视觉实验系统','Title',18,False,False)
p.alignment=WD_ALIGN_PARAGRAPH.CENTER;p.paragraph_format.space_after=Pt(14)
heading('摘要',2)
limited_text('摘要',800,'本作品基于Titanium Ti60F225 FPGA与OV5640摄像头，围绕实时图像边缘处理构建可交互的视觉实验系统。主体Function_0_CMP采用960×720 RAW8采集链路，完成Bayer转RGB、公共降噪、灰度变换以及Sobel、Sobel加中值、Canny、Canny加中值、三帧投票五种算法选择，通过DDR缓存实现八帧历史、冻结回放和双帧比较，并支持圆、矩形、三角形识别。针对静态弱轮廓跳动，系统在Canny非极大值抑制阶段引入每像素1 bit历史强峰参考，结合当前梯度、方向与邻域支持保留有效轮廓；配置改变时使历史失效。双按键完成五档操作，HDMI以1080P60左右对照显示。扩展工程分别实现原生1080P车牌定位与六字符识别、豆子连通域计数和零件轮廓特征分类；Host提供三模式中文离线控制与状态查询。四个FPGA工程分别加载位流，尚未合并为同时运行的固件。Function_0已完成逐像素回归、完整尺寸连续帧测试及编译时序检查，XLR占用80.67%，最小建立余量0.309 ns，最新稳定版仍待上板验收。车牌已有固定手机图场景实机记录，豆子和零件新增Host位流已完成离线验证。作品形成了从采集、算法、存储、显示到交互和验证的工程链路，适用于视觉算法教学与受控场景实验。')
para('关键词：FPGA；Canny；历史选峰；帧缓存；形状识别；多任务视觉',indent=False)
heading('第一部分  作品概述',1)
heading('1.1 功能与特性',2)
limited_text('1.1',400,'系统以Function_0为核心，支持五种边缘算法在线对照、0～1023阈值调节、灰度与边缘分屏、彩色红边叠加、八帧历史冻结及回放、两历史帧比较和三类基本形状识别。五档双键控制与屏幕状态显示便于现场调试。扩展能力覆盖六字符车牌自动识别、豆子计数及冻结框选、零件OK/NG/INVALID分类。Host通过USB串口显示三种扩展工程的真实结果，并提供各自允许的控制；视频由HDMI输出。工程按位流独立运行，Function_0当前主要使用板上按键交互。[1][11]')
heading('1.2 应用领域',2)
limited_text('1.2',400,'主要面向FPGA图像处理教学、边缘算法对比、轮廓与形状分析、帧间稳定性研究及嵌入式视觉原型开发。车牌工程适合受控光照下的新西兰普通六字符车牌识别演示；豆子工程适合分散、对比度可调目标的数量分析；零件工程用于外轮廓拟合和整数分类研究。不同应用可复用相机、DDR、HDMI与串口基础链路。实际部署需分别验证光照、焦距、遮挡、粘连、目标分布和异常恢复，现有样本回归不代表开放场景性能。')

page('1.3 主要技术特点',2)
limited_text('1.3',400,'图像处理采用流式RTL与行缓存，按像素组织有效信号和帧首尾标记，避免对整帧反复软件搬运。Function_0将空间降噪、局部弱边连接与历史选峰分层实现，MAJORITY3另在DDR侧进行三帧投票并配合保护逻辑。灰度、边缘与彩色缓存按源帧组织，显示端在完整帧边界切换。形状识别综合候选分组、几何判断及模板回退，并以投票迟滞稳定结果。扩展工程采用ROI处理、连通域标签合并和有限位宽数值运算控制资源；Host通过CRC、身份检查、事务编号及过期清除保持结果与模式一致。[2][4][11]')
heading('1.4 主要性能指标',2)
performance=[['主处理','960×720，目标60 fps'],['显示','1920×1080，60 Hz'],['算法与历史','5种算法，8帧历史'],['识别与通信','3类形状；扩展UART 115200 bit/s'],['资源与时序','XLR 80.67%；setup +0.309 ns']]
table(['项目','Function_0及平台指标'],performance,[1.3,4.468],11)
limited['1.4']={'limit':200,'characters':len(''.join(''.join(r) for r in performance))}
para('主处理帧率为配置目标，最新Function_0稳定版尚未实测；资源和余量来自最终编译报告。[2][3]',size=10.5,indent=False)
heading('1.5 主要创新点',2)
innovations=['（1）将历史强峰参考引入Canny选峰，以当前证据约束轮廓保持，兼顾弱边连续性与变化响应。','（2）在同一交互流程中组合算法对照、历史回放、双帧比较和稳定形状识别。','（3）采用独立视觉位流与统一Host身份协议，复用交互框架并防止跨模式误控。']
assert sum(len(x) for x in innovations)<200
for x in innovations:para(x,indent=False)
limited['1.5']={'limit':200,'characters':sum(len(x) for x in innovations)}
heading('1.6 设计流程',2)
limited_text('1.6',200,'需求与场景确定后，先建立相机采集、DDR和HDMI基础链路，再实现灰度及空间边缘算法，接入历史缓存、时域稳定和形状识别，完善按键与OSD。随后开发车牌、计数与零件独立工程及Host协议；以参考模型、逐像素仿真、完整帧回归、资源时序报告和上板记录分层验收，按版本保存位流与源文件哈希。')

page('第二部分  系统组成及功能说明',1)
heading('2.1 整体介绍',2)
para('系统由相机采集、FPGA处理、DDR帧存储、HDMI显示和可选PC控制五个层次组成。OV5640通过SCCB完成配置，经DVP送入像素；FPGA完成格式转换与所选任务，DDR隔离采集和显示节拍，HDMI输出画面、轮廓及状态。板上按键直接控制当前工程。Host只经USB串口交换命令与结构化结果，不承担实时视频传输。')
table(['工程','主要数据流','交互与输出'],[
 ['Function_0_CMP','RAW8→RGB降噪/灰度→空间边缘→历史/形状','双键五档；1080P60对照显示'],
 ['Function_1_CMP','原生1080P→定位→ROI校正→分割/OCR','冻结识别帧；HDMI及Host结果'],
 ['Function_2_CMP','RGB565→去噪→阈值/轮廓→半分辨率CCA','数量、冻结框与编号；双键菜单'],
 ['Function_3','灰度/边缘→扫描筛点→拟合→13维分类','采样/清除；状态与有符号ACC'],
 ['Host','浏览器→HTTP→控制器→UART；反向解码状态','车牌/豆子/零件三模式离线界面']
],[1.22,2.55,1.998])
para('四个FPGA目录各有Ti60_Demo.xml与example_top.v，是共享基础架构的独立工程。切换应用需要加载对应位流；网页标签切换只改变查看页面，不下载固件。Function_0的通用边缘处理与历史分析构成本文的设计主体，另外三个工程展示这一平台向具体任务扩展的方式。')
heading('2.2 硬件系统介绍',2)
heading('2.2.1 硬件整体介绍',3)
para('处理核心为Titanium Ti60F225。硬件链路包括OV5640相机接口、DDR3控制器及存储、时钟与复位逻辑、HDMI发送通道、双按键和板载USB串口。工程由Efinity完成综合、接口配置、布局布线与位流导出。Function_0以24 MHz向相机提供XVCLK，采用84 MHz候选DVP时钟配置，系统/AXI相关逻辑工作于96 MHz，HDMI像素时钟为148.5 MHz。[3][4]')

page('2.2.2 机械设计介绍',3)
para('作品采用开发板、摄像头和外接显示器的模块式实验构成，机械结构不作为独立创新成果。使用时应保证相机与目标相对稳定，保留镜头视场，并避免线缆牵拉影响拍摄角度。后续可围绕固定焦距、工作距离与照明条件设计一体化支架及遮光结构。')
heading('2.2.3 电路各模块介绍',3)
table(['模块','关键输入','关键输出与关系'],[
 ['相机初始化','配置表、复位、系统时钟','SCCB SCL/SDA、配置完成；允许后续采集'],
 ['DVP采集','cmos_pclk、data[7:0]、VSYNC、HREF','RAW8、像素有效、帧首/尾和坐标'],
 ['RGB与灰度','Bayer像素流、同步标记','RGB888、8 bit灰度及对齐有效信号'],
 ['DDR与AXI','采集写流、显示读请求、冻结/历史请求','AXI AW/W/B及AR/R；完整帧与读回流'],
 ['HDMI发送','像素时钟、RGB、DE/HS/VS','TMDS数据与时钟；1485 Mbit/s通道速率'],
 ['按键控制','key1与key0低有效输入','阈值、算法、档位、冻结和历史索引'],
 ['扩展UART','串口RX、命令与源域状态','TX、ACK、48字节状态快照']
],[1.1,2.0,2.668])
para('相机像素域、AXI域和显示域通过FIFO及完整事务握手衔接。多位状态不能仅逐位打拍；应保持数据总线稳定，通过事件或toggle握手同步后统一取样。显示读取与帧切换使用完整提交条件，防止一帧内混合不同源图。引脚、电压和时钟以各工程peri.xml与SDC为准；扩展车牌UART采用1.8 V LVCMOS板载通道。[4][5]')
heading('2.3 软件系统介绍',2)
heading('2.3.1 软件整体介绍',3)
para('本系统的软件包括FPGA侧RTL、离线参考与验证脚本、PC端Host。RTL负责逐像素实时处理和接口时序；Python脚本生成测试输入、参考结果与发布校验数据；Host以本地HTTP服务组织界面与串口事务。下面按顶层连接到核心模块的顺序说明实现，Function_0重点展开数据、时域和交互路径。')

page('2.3.2 Function_0 图像前端与空间边缘',3)
para('顶层example_top.v以960×720为有效图像尺寸。ov5640_dvp输出RAW8流，raw8_rgb_frame及相关ISP逻辑完成Bayer转换；camera_rgb_denoise提供公共彩色降噪，camera_full_view输出完整尺寸像素。灰度由RGB加权形成，代码采用(R+2G+B)/4，便于移位实现。公共前端同时供灰度显示、边缘与彩色叠加使用，避免对照画面来自不同预处理链。[4]')
para('canny_frame以capture_ready、in_valid和in_sop决定是否接纳新帧。接纳时锁存算法和阈值，在该帧结束前保持一致；灰度与边缘数据分别带valid/sop/eop输出。DDR未完成提交时不开始新事务，防止前后帧交叉。算法编号与处理方式如下。')
table(['编号','算法','主要处理'],[
 ['0','Sobel','梯度和阈值判定；不使用历史选峰'],
 ['1','Sobel加中值','3×3中值后计算Sobel'],
 ['2','Canny','两遍高斯、梯度方向、NMS、双阈值、两轮局部连接'],
 ['3','Canny加中值','3×3中值后进入Canny链路'],
 ['4','MAJORITY3','以Canny加中值为空间前端，在DDR侧进行三帧投票']
],[0.45,1.35,3.968])
para('3×3窗口和行缓存形成空间邻域。Canny以|Gx|+|Gy|近似梯度幅值，并按水平、垂直和两条对角方向量化梯度方向；两遍二项高斯具有5×5空间支撑。非极大值抑制后，像素分为非边缘、弱候选和强边缘，再由两轮局部弱边连接输出边缘。该实现采用有界局部连接，不能直接等同无限范围的全图滞后追踪。')
para('高阈值T来自用户设置；当前LOW_TIGHTEN配置下低阈值为floor(5T/8)。例如T=27时低阈值为16。高低阈值和方向支持共同抑制平坦区域噪点；中值与高斯保留为独立步骤，便于比较细节保持与降噪的权衡。')

page('2.3.3 Function_0 历史选峰与时域稳定',3)
para('静态弱轮廓在相邻像素间跳动，既可能来自源图噪声，也可能来自相近梯度峰的竞争。Function_0在Canny选峰阶段增加每像素1 bit历史强峰，而非直接把上一帧边缘复制到当前帧。历史位经32 bit打包存储，随像素流对齐读出；只有同配置的完整前帧写完后，历史才有效。[1][2]')
table(['判定阶段','保留或建立条件'],[
 ['新强峰','当前幅值不低于高阈值T，并满足当前方向和双侧切向支持'],
 ['旧峰保持','幅值不低于max(floor(5T/8),T−3)，有当前切向支持，距邻近法线峰不超过2级'],
 ['邻峰竞争','参考邻近同方向、同极性的历史位置，抑制不必要的位置交换'],
 ['释放与失效','当前证据消失即释放；算法/阈值改变使旧历史失效；Sobel不使用该机制']
],[1.15,4.618],11)
para('T=27时，新种子仍需达到27，已建立峰的保持门槛为24，低候选门槛为16。三个门槛承担不同职责，不能将24当作新的全局阈值。持续满足当前支持的旧峰可以持续存在，并非固定一帧后自动清除；失去支持则撤销。机制的目标是减少相邻近峰抖动，不能创造从未达到种子条件的极弱结构。')
para('历史选峰与MAJORITY3是两级不同机制：前者作用于空间NMS，Canny两种模式及MAJORITY3前端均使用；后者读取DDR中的多帧结果，进行三帧投票并结合运动/细节保护。修改参数时CONFIG_GUARD避免旧配置数据参与新结果。历史回放是交互功能，也不能与这两类稳定处理混为一谈。')
para('验证保留了中值、两遍高斯和两轮连接。已有模型记录表明，减少高斯可能让平坦噪声反弹，因此当前稳定版选择保持公共空间处理。1像素/帧的已测运动中最多观察到1像素位置滞后，仅适用于该测试；源图曝光和增益造成的整体明暗变化仍应从相机侧定位。[2]')

page('2.3.4 Function_0 DDR 历史与显示组织',3)
para('split_frame_ctrl负责灰度、边缘和彩色写入及显示读取。当前启用八帧环形历史、紧凑突发、彩色存储、三帧处理、配置保护和运动保护。AXI数据宽度128 bit，每个帧槽按8 MiB配置，实际各类图像使用独立地址区域。96 MHz AXI域与相机、显示域通过FIFO及帧事件协调。[4]')
para('采集端先获得可写帧槽，随后将同一源帧的灰度、边缘及所需彩色流写入。各流提交完成后才发布新帧，显示端在输出帧边界选择读槽。历史索引、冻结请求与比较请求形成独立控制；冻结意味着固定已经完成的数据，不停止显示扫描。')
table(['模式','数据选择','一致性要求'],[
 ['实时','显示最近完成的图像和边缘','灰度、边缘来自同一源帧'],
 ['冻结','保持当前完整帧','请求在帧事务边界处理'],
 ['单帧回放','从已冻结的八帧历史选择一帧','仅在有效历史数量内选择'],
 ['双帧比较','分别选择左、右历史索引','使用现存历史，不另抓一批比较帧'],
 ['MAJORITY3','读取连续历史结果并投票','配置变更及有效帧条件受保护']
],[1.05,2.45,2.268])
para('HDMI输出1920×1080/60 Hz，总时序2200×1125，像素时钟148.5 MHz。左右各显示完整960×720图像，垂直有效区为第180～899行。灰度/边缘模式便于比较提取结果；彩色模式将红色边缘叠加在彩色画面上，保留目标的纹理与背景语境。[3]')
para('OSD呈现阈值、处理FPS、档位、算法、显示模式、冻结和历史状态、左右帧号、输入帧率与尺寸及UND/TOT欠载。输入FPS描述相机输入节拍，处理FPS描述被接纳的处理帧，显示刷新率则由HDMI时序决定。三者需要分别观察，不能只依据显示稳定就认定算法达到目标帧率。')

page('2.3.5 Function_0 形状识别与双键控制',3)
para('shape_detect基于扫描线分组生成最多四个候选，结合几何、DP、Hough及多边形模板回退选择匹配目标，输出无形状、圆、矩形或三角形。shape_stabilizer只在一次识别完成时投票：最近五次三票建立类别，四票切换类别，连续八次不匹配后清除。它稳定类别输出，不是多目标跟踪器。[4]')
para('形状档实际处理阈值为max(设置值−10,0)，以增加轮廓候选的可见性，OSD显示这一实际处理值。同一阈值寄存器设置在形状档与普通边缘档对应的门槛不同，比较功能时应结合档位和实际显示值解释参数。')
table(['操作或档位','KEY+ 与 KEY− 的行为'],[
 ['键位','KEY+=key1，KEY−=key0；均低有效并经同步消抖'],
 ['切换档位','单键长按至少1秒后松开，分别前进/后退一档，1～5循环'],
 ['第1档 阈值','短按阈值±1，0～1023饱和'],
 ['第2档 算法','短按前后选择五种算法'],
 ['第3档 显示','短按切换灰度/边缘或彩色叠加，并释放冻结'],
 ['第4档 历史','回放时选帧；比较时分别调左右帧；双键短按切换回放/比较'],
 ['第5档 形状','短按调整该档使用的阈值设置'],
 ['冻结','双键长按至少1秒后全部松开，切换冻结请求']
],[1.18,4.588])
para('短按要求不足0.5秒；0.5～1秒的单键手势不调参也不换档。长按超过2秒仍只换一档，组合键拥有整个手势，直到两键全部松开才结算。当前顶层DEFAULT_TEMPORAL=1，上电算法为MAJORITY3、阈值为72；Canny加中值、THR27是稳定版推荐上板对照条件。[1][4]')
para('控制链关键输出为gear、algorithm、display_mode、threshold、freeze_requested、compare_mode及replay/left/right_frame。它们分别进入算法锁存、显示选择及历史控制，减少在多个模块中重复解释按键的风险。')

page('2.3.6 Function_1 车牌识别扩展',3)
para('Function_1_CMP将相机、全帧Canny与定位、灰度DDR预览、HDMI全部保持在1920×1080，采集及输出为30 fps/30 Hz。边缘密度定位提出候选框，后续被接纳的源帧动态抓取ROI，归一化为256×96，再进行镜头校正、灰度统计、六字符分割与模板OCR。支持新西兰普通单行ABC123和AB1234两种格式，模板库包含359个逐字符模板。[5]')
table(['模块','关键输入与输出','处理职责'],[
 ['plate_locator','原生边缘流→候选框','按边缘密度定位并记录候选状态'],
 ['native_gray_capture','源灰度/坐标→ROI及帧ID','抓取完整源帧对应区域'],
 ['lens_roi_warp','ROI及映射ROM→校正ROI','反向映射、双线性插值'],
 ['plate_segmenter','灰度与局部统计→字符掩码','牌面边界、笔画和字符几何筛选'],
 ['nz_plate_ocr','六字符图→号码/拒绝原因','模板匹配、误差与差距拒绝'],
 ['autoplate_core','候选、ROI和识别状态→调度','搜索、校正、同帧回退、冻结与发布']
],[1.45,2.05,2.268])
para('生产位流启用LENS_CORRECTION，关闭标定抓图缓存。lens_grid_lookup读取64像素间隔的正反向网格，供ROI校正使用；HDMI与定位仍处于原始坐标，未做整屏去畸变。校正结果被分割/OCR拒绝后，恢复同源帧原始ROI重试一次，仍失败才继续搜索。更换镜头、调焦或改变读出模式需要重新标定。[6]')
para('识别成功后冻结图像，定位框、结果和抓帧ID一致；失败释放重搜。原生1080P版为满足RAM预算关闭整帧历史选峰，不能直接套用Function_0的全部时域功能。UART支持阈值、字符偏移、重识别、运行控制和状态查询；命令先进入跨域邮箱，在帧边界生效，ACK只表示已接收。物理键短按以5为步长调整ADJ，双键长按恢复128并重新识别。')

page('2.3.7 Function_2 豆子轮廓与计数扩展',3)
para('Function_2_CMP采用1920×1080 RGB565采集，目标15 fps；74.4 MHz像素时钟对应约1080P30输出，并重复显示最近完整帧。DDR使用四个帧槽，每个图像有效数据4,147,200字节，槽位按4 MiB对齐，总预留16 MiB。显示读流先做精确5×5 RGB中值，再做3×3边缘保护加权平滑；原图、轮廓和计数共享去噪流。[7][8]')
para('全分辨率分支执行阈值、ROI、开闭运算及两像素红色内轮廓；当前绕过旧灰度高斯。2×2抽样生成960×540分析图，经二值多数滤波进入bean_cca，完成标签合并与根区域统计，再按面积、宽高、边界条件筛选。冻结时分析对应冻结帧并保持数量；最多标注128个合格目标绿框和编号，超限仍保留完整计数。')
table(['模块','输入到输出','一致性控制'],[
 ['bean_preprocess','RGB/配置→二值分析流','ROI与阈值使用同组帧锁存配置'],
 ['bean_cca','二值像素→根区域/数量','标签等价合并后按统一条件筛选'],
 ['bean_objects','合格区域→绿框/编号','只显示完整冻结批次；最多128框'],
 ['bean_runtime_controls','K1/K2→待生效配置','消抖、菜单、范围和偶数边界约束'],
 ['video_frame_banks','采集/读流→完整帧','冻结、发布和错误恢复'],
 ['camera_sccb_verify','寄存器读回→ready','核对芯片ID、尺寸、格式和ACK']
],[1.65,1.85,2.268])
para('默认阈值112、深色目标、RESULT视图；ROI为[96,1824)×[72,1008)，分析图面积36～11250、宽高下限5和上限240。菜单支持RAW/BINARY/RESULT、极性、ROI、面积、尺寸及步长1/8/32/256。正常K1冻结/恢复，K2进入菜单；菜单K1短按增加、约0.5秒长按减少，K2短按切项、约1秒长按退出。参数在帧边界整组应用，旧结果失效后重算。')
para('可靠性链路检查SCCB ACK与回读、AXI响应与ID、帧长度、FIFO溢出和读终止；严重无进展故障触发DDR相关模块共同复位。新增Host位流提供数量、可见框数、批次ID、ROI与错误字，并接受冻结/恢复；图像参数仍沿用板上菜单，当前协议不提供豆子FPS有效测量。[9][11]')

page('2.3.8 Function_3 零件外轮廓与整数分类',3)
para('Function_3当前只启用第六档零件测试，固定960×720、Canny加中值及THR27，关闭DDR三帧投票和历史请求，显示采用彩色边缘叠加。KEY+或Host触发采样，KEY−或Host清除/取消；长按与组合键不切回原五档。一次采样等待下一完整灰度/边缘帧，由事务控制防止复用上一结果。[10][11]')
table(['阶段','实现细节','关键输出'],[
 ['ml_scan','在[128,832)×[8,712)按6像素扫描，取行列首末边缘并检查灰度阶跃','最多472槽位的点、方向、真实槽号与保护信息'],
 ['point_gap_filter','查找至少60像素垂直空档，两侧均不少于24点时保留点数较多侧','保持原顺序的筛后点集；相等保留上侧'],
 ['ml_num_core','中位数、归一化、5×5 Gram与Gauss-Jordan求解，三轮拟合/掩码','几何量、Q24残差及13维整数特征'],
 ['ml_int13_classifier','冻结的整数线性模型；有限位宽与范围检查','类别、有效性、原因码与有符号ACC'],
 ['结果同步与OSD','完整结果快照跨域；十进制转换','WAIT / BUSY / OK / NG\nINVALID、样本号与ACC']
],[1.45,2.6,1.718])
para('分类计算ACC=offset+Σ(weight[i]×feature[i])。ACC<0为OK，ACC≥0为NG；特征无效、越域、编码或算术错误输出INVALID。INVALID不是缺陷类别，也没有有效ACC。模型参数保存在ml_int13_params.vh，现场不训练。[10]')
para('乘除、平方根与移位复用ml_num_au；点数不足、病态矩阵、溢出或非椭圆均返回原因。保留原2^30拟合保护上限，筛点模块约需720周期初始化，过早点输入导向无效结果。垂直分组可能误删真实主体或缺陷，当前能力适用于研究与演示，需要扩大场景验证。新增Host位流发布原始/筛后点数、采样号和原因码，便于区分扫描、拟合与分类失败。')

page('2.3.9 Host 本地服务与三模式通信',3)
para('Host由start_control.cmd启动，优先运行dist/Ti60PlateControl.exe，也可用app.py源码启动。本地服务只绑定127.0.0.1，默认端口8765，占用时选择空闲端口，并自动打开浏览器。界面提供车牌、豆子、零件三种模式，展示板端身份和真实状态；网页不承载视频流。[11][12]')
table(['层次与入口','输入','输出与关键流程'],[
 ['app.py make_server','HTTP请求与JSON','端口枚举、连接、状态及命令API；检查Host/Origin'],
 ['Controller.connect','COM端口','建立串口、清理旧状态并启动轮询'],
 ['Controller.command','命令名与数值','先查身份→校验模式→封包→等待ACK/读回'],
 ['Controller._exchange','序号、命令、载荷','匹配序号/回复类型；处理超时和链路错误'],
 ['Parser.feed','任意分段串口字节','找A5 5A→查版本/长度→CRC→有效包；坏包重同步'],
 ['decode_status','48字节状态载荷','按task解码车牌、数量或ACC与原因'],
 ['static/app.js','API快照与用户操作','模式跟随、控件使能、过期清除与结果呈现']
],[1.55,1.15,3.068])
para('串口采用115200、8N1、无流控。帧格式为A5 5A 01 SEQ CMD LEN PAYLOAD CRC8，载荷不超过48字节，小端编码；CRC8多项式0x07、初值0，覆盖版本到载荷。GET_STATUS=0x01，ACK=0x80，状态=0x81；车牌控制为0x10～0x14，豆子冻结为0x20，零件采样/清除为0x21/0x22。')
para('任务ID为0车牌、1豆子、3零件，功能位图为1<<task。SET_TASK只能确认当前任务，跨任务拒绝，不改变固件。主机单一串行拥有者逐条发送，每次控制前检查身份；新豆子和零件位流通过保持总线与三拍toggle握手传递状态和命令，源时钟丢失时清除结果有效位。')
para('轮询约5 Hz，状态超过1.2秒、断线或模式不匹配即撤销当前成功结果。车牌需有效、锁定且格式正确才显示号码；豆子数量附完成批次，零件采样收到ACK后屏蔽旧分类，直到新样本号或取消结果返回。豆子/零件FPS有效位为0时显示未知，不能将保留字段0解释为实测帧率。[11][12]')

page('第三部分  完成情况及性能参数',1)
heading('3.1 整体介绍',2)
para('成果包括四套独立FPGA工程、对应位流与约束、分层测试脚本、参考数据和中文Host可执行程序。Function_0完成通用边缘处理、历史与形状功能的RTL实现；车牌完成原生1080P和镜头ROI校正；豆子完成运行时菜单、128目标标注及结果通信；零件完成筛点、有限位宽拟合与分类结果通信。下表按当前发布版本说明完成状态。')
table(['工程','当前发布入口','验证层级'],[
 ['Function_0','output/Ti60_Demo.bit','逐像素、完整尺寸及最终编译通过；最新稳定版待上板'],
 ['Function_1','output/lens_corrected/Ti60_Demo.bit','仿真、编译及2026-10-31固定图实机记录'],
 ['Function_2','output/host_web/Ti60_Demo.bit','发布校验及编译通过；新增通信版未上板'],
 ['Function_3','output/host_web/Ti60_Demo.bit','样本链回归及编译通过；新增通信版未上板'],
 ['Host','dist/Ti60PlateControl.exe','协议/HTTP、EXE与浏览器回归通过']
],[1.0,2.35,2.418])
heading('3.2 工程成果',2)
heading('3.2.1 机械成果',3)
para('实验平台按相机、开发板、显示器与PC分模块组成。当前成果重点在图像处理与交互逻辑，机械部分采用配套模块的实验连接形式；一体化外壳、光学支架和专用输送机构作为后续工程化内容。')
heading('3.2.2 电路成果',3)
para('电路设计落实为相机初始化与采集、视频流水线、DDR/AXI、HDMI、按键和串口的RTL及外围配置，包含Ti60_Demo.xml、Ti60_Demo.peri.xml、SDC、IP与位流文件。源输入和位流通过SHA256关联，便于确认报告、代码与发布物属于同一版本。')
heading('3.2.3 软件成果',3)
para('软件交付包含离线Host EXE、Python服务与协议模块、中文页面、串口诊断及回归测试。三模式页面自动跟随板端身份，按模式限制控制，并区分当前有效结果和陈旧诊断。生产服务不提供演示结果注入接口；tests中的假串口仅用于自动化回归。[11]')

page('3.3 特性成果与量化指标',2)
heading('3.3.1 Function_0 资源与时序',3)
table(['指标','最终结果','说明'],[
 ['XLR','49,047 / 60,800，80.67%','最终布局资源'],
 ['存储块','225 / 256，87.89%','片上存储余量较有限'],
 ['DSP','68 / 160，42.50%','最终编译记录'],
 ['最小setup','+0.309 ns','所有已约束关系最小值'],
 ['最小hold','+0.014 ns','所有已约束关系最小值'],
 ['HDMI 148.5 MHz setup','+0.652 ns','显示时钟关系'],
 ['输入84 MHz setup','+2.146 ns','候选相机输入时钟关系']
],[1.65,2.05,2.068])
para('数据来自Function_0最终布线与验证记录。map、interface、pnr、pgm和位流导出均通过。旧外设或未使用端点仍有约束警告，表中通过范围为报告内已约束关系；不能据此推定所有物理接口已经实机确认。[2]')
heading('3.3.2 Function_0 功能验证',3)
table(['验证项目','已记录的覆盖与结论'],[
 ['历史选峰专项','48×32与35×23各55帧，共110帧；逐像素灰度、分类、边缘、保护、历史位与标记通过'],
 ['边界和配置','算法/阈值切换、帧中改参、输入气泡、32 bit打包及非整字末尾通过'],
 ['完整尺寸流水线','960×720连续60 Hz双帧；像素数量、坐标和运行时四种空间引擎通过'],
 ['历史及交互','960宽guard/history、冻结回放、彩色切换、双键手势及顶层检查通过']
],[1.45,4.318])
para('verification中的上一版五帧96 MHz DDR并发日志已明确标记为未改动链路的历史记录；本版另跑960宽历史/保护和彩色切换检查。最新稳定版尚未加载本板，960×720/60 fps应列为配置目标及仿真工况，不列为本版实测结论。[2][3]')

page('3.3.3 Function_0 上板验收要点',3)
para('在相同自然光、相机位置和目标下，以Canny加中值、THR27作为对照工况。首先确认CAM READY、输入W0960/H0720及IN约60，再观察处理FPS、图像方向、Bayer颜色和UND/TOT。随后依次切换五算法、两种显示、冻结、八帧回放、双帧比较和形状档，检查完整帧一致性及历史切换。')
table(['观察项','验收记录内容','需区分的原因'],[
 ['弱边连续性','细线、阴影边缘和近峰位置变化','历史选峰与阈值灵敏度'],
 ['平坦区域噪点','固定背景的噪声和局部伪边','公共前端、曝光和空间滤波'],
 ['运动响应','平移、目标消失及拖影','当前支持释放、时域投票及运动保护'],
 ['帧一致性','冻结图、左右历史帧号和颜色切换','缓存发布与显示读槽'],
 ['形状稳定性','建立、类别改变和离开后的清除','3/5建立、4/5切换、8次不匹配清除'],
 ['吞吐与显示','输入/处理FPS及UND/TOT','采集、处理接纳和HDMI节拍分别记录']
],[1.05,2.65,2.068])
para('本版没有修改相机AE/AG，也没有证实消除了左灰度的整体明暗波动。历史选峰只在当前梯度与邻域支持存在时起作用；极弱单像素线、运动速度、照明闪烁和噪声水平变化均可能影响结果。验收应保留输入条件与失败现象，避免将稳定的合成图结果外推为所有场景零闪烁。')
heading('3.3.4 版本可追溯性',3)
para('Function_0的verification目录保存源码变化、SHA256哈希、专项日志和构建记录，发布位流哈希亦列于VALIDATION.md。版本对照时应先核对位流与源输入，再比较同一算法、同一阈值和同一光照下的画面，避免把参数或输入差异当作改进收益。[2]')

page('3.3.5 扩展工程与 Host 验证结果',3)
table(['对象','量化记录','适用范围'],[
 ['车牌实机','固定AUY359手机图5次均锁定；1.518/3.278/1.239/0.439/0.746秒，中位1.239秒','2026-10-31单一固定场景；存在其他失败轮次'],
 ['车牌链路','输入/处理1920×1080、30 fps，累计欠载0','解除冻结后的板端状态读回'],
 ['镜头校正','1000坐标样本；98,304输出像素逐项一致；ROI仿真约5.7～6.1 ms','校正模块测试，非整牌端到端时延'],
 ['豆子回归','128框与编号、63组CCA对象、逐像素及异步冻结/恢复通过','新Host位流尚未实机验收'],
 ['零件样本链','六张拍屏图参考输入，结果OK/OK/OK/NG/NG/NG','软件前端加扫描/筛点/数值核/分类器RTL链'],
 ['Host','28项Python测试；3模式×7种视口，无JS错误','假串口/浏览器及EXE启动验证']
],[0.85,2.85,2.068])
para('车牌镜头标定使用10张训练图和2张独立验证图，普通模型训练RMS为0.06994个320×180像素；独立验证平均RMS折算原生像素为0.36894。直线残差约下降72%描述几何一致性，不能解释为识别准确率提升；当前没有同一固定图的校正开关实机对照。[6]')
table(['当前发布版本','XLR使用量','最小setup/hold'],[
 ['车牌镜头校正版','40,676 / 60,800','0.000 / +0.026 ns'],
 ['豆子Host版','60,140 / 60,800','+0.211 / +0.026 ns'],
 ['零件Host版','57,896 / 60,800','+0.326 / +0.026 ns']
],[2.0,1.65,2.118])
para('车牌setup为报告精度边界值；豆子26组、零件24组已约束时钟关系通过，发布JSON均标记hardware_validated=false。零件六图链并非完整相机Canny实链；单张车牌重复成功也不代表道路准确率。新豆子/零件位流与旧菜单版、筛点试验版的资源数字应分别使用。[6][10][11][13]')

page('第四部分  总结',1)
heading('4.1 可扩展之处',2)
limited_text('4.1',300,'可优先补齐Function_0最新稳定版上板对照，记录曝光/增益、输入帧率、欠载和运动响应，并按场景评估历史选峰的收益与副作用。进一步可优化片上RAM和DDR访问，为更高分辨率或更多候选保留余量。车牌可增强候选定位、字符诊断与独立样本评估；豆子可研究粘连分离和不均匀照明；零件可改进数值缩放、筛点规则与缺陷覆盖。Host可增加只读诊断和结果导出。若整合为统一固件，需重新评估资源、带宽、跨域及互斥调度，并完成各模式独立验收。')
heading('4.2 心得体会',2)
limited_text('4.2',1000,'研发过程表明，FPGA视觉系统的有效结果依赖整条链路的一致性。边缘图看似只是算法输出，但像素有效信号、帧首尾、行缓存边界和跨时钟事件只要错位，就可能表现为画面断裂、历史错帧或结果滞留。因此设计中需要把数据、同步标记、配置与结果编号当作同一事务管理，并在参考模型和RTL间逐项核对。')
para('Function_0的弱轮廓稳定设计也说明，降噪与保留细节需要针对具体失效原因。单纯提高阈值会减少可见细线，减少高斯又可能放大平坦噪声；历史信息只有与当前梯度和邻域证据结合，才有机会稳定近峰而及时释放消失目标。算法切换、阈值变化与非整字帧尾等边界同样需要验证，不能只展示理想静态图。')
para('扩展到车牌、豆子和零件后，通用前端必须服从应用需求。车牌以原生分辨率保留字符信息，用ROI校正控制开销；豆子通过半分辨率连通域降低统计成本，同时保持原图标注；零件使用有限位宽数值核与冻结模型，需显式区分无效和缺陷。这些差异说明模块复用应保留任务边界，不能直接复制所有时域功能。')
para('交互与验证也是设计的一部分。命令ACK不等于参数已应用，收到采样ACK也不等于新结果已生成；身份、帧ID、批次号、样本号和过期清除把用户操作与实际处理联系起来。仿真通过、时序满足和实机有效分别回答不同问题，只有保存版本、输入条件与失败记录，后续优化才具有可复现的依据。')
summary_paras=d.paragraphs[-4:]
summary_len=sum(len(re.sub(r'\s','',p.text)) for p in summary_paras)
assert summary_len<=1000,summary_len
limited['4.2']={'limit':1000,'characters':summary_len}

page('第五部分  参考文献',1)
refs=[
 '[1] A工程960×720与Canny弱轮廓稳定版说明[R]. 2026. 项目文件：Function_0_CMP/README_960_CN.md.',
 '[2] Canny弱轮廓稳定修复验证[R]. 2026. 项目文件：Function_0_CMP/VALIDATION.md及verification中的日志、资源和哈希记录.',
 '[3] OV5640 960×720与60 Hz配置依据与验证范围[R]. 2026. 项目文件：Function_0_CMP/CAMERA_MODE.md.',
 '[4] Function_0顶层与图像处理RTL[CP]. 2026. 项目文件：Function_0_CMP/example_top.v；src/canny、src/axi/split_frame_ctrl.v、src/shape_*.v、src/video_key_control.v.',
 '[5] B中文网页控制与自动车牌识别使用说明[R]. 2026. 项目文件：Function_1_CMP/README_使用说明.md.',
 '[6] 实测镜头标定与识别前去畸变[R]. 2026-10-31. 项目文件：Function_1_CMP/docs/LENS_CALIBRATION_20261031.md.',
 '[7] K1与K2运行时调参与已计数目标标注[R]. 2026-10-30. 项目文件：Function_2_CMP/README_RUNTIME.md.',
 '[8] 1080P强去噪[R]. 2026. 项目文件：Function_2_CMP/README_DENOISE.md.',
 '[9] 相机与DDR可靠性加固说明[R]. 2026. 项目文件：Function_2_CMP/README_RELIABILITY.md及src/bean.',
 '[10] LINGJIAN拟合前筛点试验版[R]. 2026. 项目文件：Function_3/README_FIT_TRIAL.md；src/ml_num_core.v、src/ml_int13_classifier.v及verification/qq_six_trial/results.json.',
 '[11] 三模式接入与使用[R]. 2026-10-31. 项目文件：Host/MULTIMODE.md.',
 '[12] Ti60多模式视觉控制台源程序[CP]. 2026. 项目文件：Host/app.py、controller.py、protocol.py及static.',
 '[13] 豆子与零件Host版发布校验数据[DS]. 2026. 项目文件：Function_2_CMP/output/host_web/release_validation.json；Function_3/output/host_web/release_validation.json.'
]
for ref in refs:
    p=para(ref,size=10.5,indent=False);p.paragraph_format.line_spacing=1.25;p.paragraph_format.space_after=Pt(7)
    p.alignment=WD_ALIGN_PARAGRAPH.LEFT
    p.paragraph_format.keep_together=True

# Serialize authoring parts, then keep every unrelated source package member unchanged.
buf=BytesIO();d.save(buf)
with ZipFile(REF) as z0,ZipFile(buf) as z1:
    updated={n:z1.read(n) for n in ['word/document.xml','word/styles.xml']}
    originals={n:hashlib.sha256(z0.read(n)).hexdigest() for n in z0.namelist()}
    tmp=WORK/'filled.docx'
    with ZipFile(tmp,'w',ZIP_DEFLATED) as zo:
        for info in z0.infolist():zo.writestr(deepcopy(info),updated.get(info.filename,z0.read(info.filename)))
shutil.copy2(tmp,OUT)
with ZipFile(OUT) as z:
    changed=[n for n,h in originals.items() if hashlib.sha256(z.read(n)).hexdigest()!=h]
    assert set(changed)==set(updated),changed
    assert z.namelist()==list(originals)
    xml=z.read('word/document.xml').decode()
    assert '<w:drawing' not in xml and '<w:pict' not in xml
    for forbidden in ['800字内','400字内','阐述具体的设计细节','学校名称','TODO','待填写']:
        assert forbidden not in xml,forbidden
assert hashlib.sha256(REF.read_bytes()).hexdigest()==baseline
report={'reference_sha256':baseline,'output_sha256':hashlib.sha256(OUT.read_bytes()).hexdigest(),'changed_parts':changed,'limited_sections':limited,'reference_count':len(refs),'body_images_added':0,'paragraphs':len(d.paragraphs),'tables':len(d.tables)}
(WORK/'document_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(report,ensure_ascii=False,indent=2))
