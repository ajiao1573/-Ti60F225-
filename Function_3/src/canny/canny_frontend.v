`ifndef TI60_CANNY_FRONTEND_V
`define TI60_CANNY_FRONTEND_V
// Canny stages 1..4. Optional reference Sobel four-direction maximum.
// Default L1 mode remains available for historical bit-exact comparisons.
// Direction quantization uses tan(22.5 deg) ~= 106/256; image y points down.
// Thresholds are stable for the complete frame (latched by canny_frame).
module canny_frontend #(parameter WIDTH=848,HEIGHT=636,MEDIAN_ENABLE=1,GAUSSIAN_PASSES=2,RUNTIME_MODES=0,CANNY_ENABLE=1,SOBEL_MAX_ENABLE=0,ROBUST_NMS=0,BORDER_REFLECT=0,NMS_TOLERANCE=0,PROTECT_ENABLE=0,COHERENT_PROTECT=0,TEMPORAL_NMS=0)(
 input clk,input rst_n,input in_valid,input in_sop,input in_eop,
 input [7:0] in_data,input [1:0] runtime_mode,input [10:0] low_threshold,high_threshold,
 output reg out_valid,output reg out_sop,output reg out_eop,
 output reg [1:0] out_class,output reg [7:0] out_gray,output reg out_protect
);
 // Use the same gradient scale and user threshold in every runtime mode.
 // Brightness must not mask user threshold changes.
 wire noise_reject=SOBEL_MAX_ENABLE;
 wire use_median=!RUNTIME_MODES || runtime_mode[0];
 wire use_canny=CANNY_ENABLE && (!RUNTIME_MODES || runtime_mode[1]);
 wire median_v,median_s,median_e;wire [7:0] median_d;
 wire mv,ms,me;
 wire [7:0] md;
 generate if(MEDIAN_ENABLE) begin:denoise
  canny_median3 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.BORDER_REFLECT(BORDER_REFLECT)) median_filter(
   .clk(clk),.rst_n(rst_n),.in_valid(in_valid && use_median),.in_sop(in_sop && use_median),.in_eop(in_eop && use_median),.in_data(in_data),
   .out_valid(median_v),.out_sop(median_s),.out_eop(median_e),.out_data(median_d));
 end else begin:bypass_median
  assign median_v=in_valid;assign median_s=in_sop;assign median_e=in_eop;assign median_d=in_data;
 end endgenerate
 assign mv=use_median ? median_v : in_valid;
 assign ms=use_median ? median_s : in_sop;
 assign me=use_median ? median_e : in_eop;
 assign md=use_median ? median_d : in_data;
 // Two binomial passes have 5x5 spatial support and suppress random noise
 // more strongly; each stage rounds to 8 bits and keeps the frame boundary.
 wire [7:0] blur_data[0:GAUSSIAN_PASSES];
 wire [2:0] blur_ctrl[0:GAUSSIAN_PASSES];
 assign blur_data[0]=md;assign blur_ctrl[0]={ms && use_canny,me && use_canny,mv && use_canny};
 genvar blur;
 generate for(blur=0;blur<(CANNY_ENABLE ? GAUSSIAN_PASSES : 0);blur=blur+1) begin:gaussian_stages
  canny_gaussian3 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.BORDER_REFLECT(BORDER_REFLECT)) smoother(
   .clk(clk),.rst_n(rst_n),.in_valid(blur_ctrl[blur][0]),.in_sop(blur_ctrl[blur][2]),
   .in_eop(blur_ctrl[blur][1]),.in_data(blur_data[blur]),
   .out_valid(blur_ctrl[blur+1][0]),.out_sop(blur_ctrl[blur+1][2]),.out_eop(blur_ctrl[blur+1][1]),
   .out_data(blur_data[blur+1]));
 end endgenerate
 wire [7:0] gaussian=use_canny ? blur_data[CANNY_ENABLE ? GAUSSIAN_PASSES : 0] : md;
 wire [2:0] gv=use_canny ? blur_ctrl[CANNY_ENABLE ? GAUSSIAN_PASSES : 0] : {ms,me,mv};
 wire bv,bs,be,bb;
 wire [7:0] b11,b12,b13,b21,b22,b23,b31,b32,b33;
 canny_window #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.DW(8)) gradient_window(
  .clk(clk),.rst_n(rst_n),.in_valid(gv[0]),.in_sop(gv[2]),.in_eop(gv[1]),.in_data(gaussian),
  .out_valid(bv),.out_sop(bs),.out_eop(be),.border(bb),
  .p11(b11),.p12(b12),.p13(b13),.p21(b21),.p22(b22),.p23(b23),.p31(b31),.p32(b32),.p33(b33));
 wire [10:0] right_sum={3'b0,b13}+{2'b0,b23,1'b0}+{3'b0,b33};
 wire [10:0] left_sum ={3'b0,b11}+{2'b0,b21,1'b0}+{3'b0,b31};
 wire [10:0] bottom_sum={3'b0,b31}+{2'b0,b32,1'b0}+{3'b0,b33};
 wire [10:0] top_sum={3'b0,b11}+{2'b0,b12,1'b0}+{3'b0,b13};
 // Reference kernels: 45 degrees = p23+2*p33+p32 - p12-2*p11-p21;
 // 135 degrees = p12+2*p13+p23 - p21-2*p31-p32.
 wire [10:0] diag45_p={3'b0,b23}+{2'b0,b33,1'b0}+{3'b0,b32};
 wire [10:0] diag45_n={3'b0,b12}+{2'b0,b11,1'b0}+{3'b0,b21};
 wire [10:0] diag135_p={3'b0,b12}+{2'b0,b13,1'b0}+{3'b0,b23};
 wire [10:0] diag135_n={3'b0,b21}+{2'b0,b31,1'b0}+{3'b0,b32};
 reg signed [10:0] gx,gy,g45,g135;
 reg [10:0] a45,a135;
 reg [10:0] ax,ay;
 wire [10:0] max_axis=ax>ay ? ax : ay;
 wire [10:0] max_diag=a45>a135 ? a45 : a135;
 wire [10:0] max_gradient=max_axis>max_diag ? max_axis : max_diag;
 reg [7:0] gray1,gray2,gray3;
 reg [3:0] ctrl1,ctrl2,ctrl3;
 reg opposite,sign_x,sign_y,polarity;
 reg [10:0] magnitude;
 reg [1:0] direction;
 wire [18:0] ax106=({8'b0,ax}<<6)+({8'b0,ax}<<5)+({8'b0,ax}<<3)+({8'b0,ax}<<1);
 wire [18:0] ay106=({8'b0,ay}<<6)+({8'b0,ay}<<5)+({8'b0,ay}<<3)+({8'b0,ay}<<1);
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   gx<=0;gy<=0;g45<=0;g135<=0;a45<=0;a135<=0;ax<=0;ay<=0;opposite<=0;sign_x<=0;sign_y<=0;polarity<=0;magnitude<=0;direction<=0;
   gray1<=0;gray2<=0;gray3<=0;ctrl1<=0;ctrl2<=0;ctrl3<=0;
  end else begin
   gx<=$signed(right_sum)-$signed(left_sum); gy<=$signed(bottom_sum)-$signed(top_sum);
   g45<=$signed(diag45_p)-$signed(diag45_n);
   g135<=$signed(diag135_p)-$signed(diag135_n);
   a45<=g45[10] ? -g45 : g45;
   a135<=g135[10] ? -g135 : g135;
   gray1<=b22;ctrl1<={bb,bs,be,bv};
   ax<=gx[10] ? -gx : gx; ay<=gy[10] ? -gy : gy; opposite<=gx[10]^gy[10];sign_x<=gx[10];sign_y<=gy[10];
   gray2<=gray1;ctrl2<=ctrl1;
   magnitude<=ctrl2[3] ? 11'd0 : (noise_reject ? max_gradient : ax+ay);
   if({ay,8'b0}<=ax106) direction<=0; // horizontal gradient
   else if({ax,8'b0}<=ay106) direction<=2; // vertical gradient
   else direction<=opposite ? 3 : 1;
   polarity<=({ay,8'b0}>ax106 && {ax,8'b0}<=ay106) ? sign_y:sign_x;
   gray3<=gray2;ctrl3<=ctrl2;
  end
 end
 wire [10:0] sobel_threshold=high_threshold;
 generate if(CANNY_ENABLE) begin:nms_enabled
 wire nv,ns,ne,nb;
 localparam BW=(COHERENT_PROTECT || TEMPORAL_NMS) ? 22:21;
 localparam NW=BW+(TEMPORAL_NMS ? 1:0);
 wire [BW-1:0] gradient_pixel={polarity,direction,magnitude,gray3};
 wire [NW-1:0] nms_input;wire iv,is,ie;
 if(TEMPORAL_NMS) begin:stable_history
  canny_peak_history #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.DW(BW)) history(
   .clk(clk),.rst_n(rst_n),.invalidate(!use_canny),
   .in_valid(ctrl3[0] && use_canny),.in_sop(ctrl3[2]),.in_eop(ctrl3[1]),.in_data(gradient_pixel),
   .configuration({runtime_mode,high_threshold}),
   .feedback_valid(out_valid && use_canny),.feedback_sop(out_sop),.feedback_eop(out_eop),.feedback_seed(out_class==2),
   .out_valid(iv),.out_sop(is),.out_eop(ie),.out_data(nms_input));
 end else begin:no_stable_history
  assign nms_input=gradient_pixel;assign iv=ctrl3[0] && use_canny;
  assign is=ctrl3[2] && use_canny;assign ie=ctrl3[1] && use_canny;
 end
 wire [NW-1:0] n11,n12,n13,n21,n22,n23,n31,n32,n33;
 canny_window #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.DW(NW)) nms_window(
  .clk(clk),.rst_n(rst_n),.in_valid(iv),.in_sop(is),.in_eop(ie),
  .in_data(nms_input),
  .out_valid(nv),.out_sop(ns),.out_eop(ne),.border(nb),
  .p11(n11),.p12(n12),.p13(n13),.p21(n21),.p22(n22),.p23(n23),.p31(n31),.p32(n32),.p33(n33));
 reg [NW-1:0] normal_a,normal_c;
 wire [10:0] na=normal_a[18:8],nc=normal_c[18:8];
 wire [10:0] mag=n22[18:8];
 wire [10:0] local_high=high_threshold;
 wire [10:0] local_low=low_threshold;
 always @* begin
  case(n22[20:19])
   0:begin normal_a=n21;normal_c=n23;end
   1:begin normal_a=n11;normal_c=n33;end
   2:begin normal_a=n12;normal_c=n32;end
   default:begin normal_a=n13;normal_c=n31;end
  endcase
 end
 // Keep the normal-direction peak comparison unchanged. Reject isolated
 // seeds using support on the two sides of the edge tangent, from the same
 // 3x3 magnitude/direction window: no added buffers or frame latency.
 function tangent_support;
  input [20:0] pixel;
  input [10:0] limit;
  input [1:0] center_direction;
  begin
   tangent_support=pixel[18:8]!=0 && pixel[18:8]>=limit &&
                   pixel[20:19]!=(center_direction ^ 2'd2);
  end
 endfunction
 wire [10:0] half_peak={1'b0,mag[10:1]};
 wire [10:0] weak_support_limit=half_peak>local_low ? half_peak : local_low;
 wire [10:0] strong_support_limit=half_peak>local_high ? half_peak : local_high;
 wire [7:0] weak_support,strong_support;
 // Bit positions clockwise: NW,N,NE,E,SE,S,SW,W.
 assign weak_support={tangent_support(n21,weak_support_limit,n22[20:19]),
  tangent_support(n31,weak_support_limit,n22[20:19]),tangent_support(n32,weak_support_limit,n22[20:19]),
  tangent_support(n33,weak_support_limit,n22[20:19]),tangent_support(n23,weak_support_limit,n22[20:19]),
  tangent_support(n13,weak_support_limit,n22[20:19]),tangent_support(n12,weak_support_limit,n22[20:19]),
  tangent_support(n11,weak_support_limit,n22[20:19])};
 assign strong_support={tangent_support(n21,strong_support_limit,n22[20:19]),
  tangent_support(n31,strong_support_limit,n22[20:19]),tangent_support(n32,strong_support_limit,n22[20:19]),
  tangent_support(n33,strong_support_limit,n22[20:19]),tangent_support(n23,strong_support_limit,n22[20:19]),
  tangent_support(n13,strong_support_limit,n22[20:19]),tangent_support(n12,strong_support_limit,n22[20:19]),
  tangent_support(n11,strong_support_limit,n22[20:19])};
 reg [7:0] tangent_a,tangent_b;
 always @* begin
  case(n22[20:19])
   0:begin tangent_a=8'b00000111;tangent_b=8'b01110000;end // top / bottom
   1:begin tangent_a=8'b00001110;tangent_b=8'b11100000;end // NE / SW
   2:begin tangent_a=8'b11000001;tangent_b=8'b00011100;end // left / right
   default:begin tangent_a=8'b10000011;tangent_b=8'b00111000;end // NW / SE
  endcase
 end
 wire weak_supported=!ROBUST_NMS || |(weak_support & (tangent_a | tangent_b));
 wire strong_supported=!ROBUST_NMS ||
      ((|(strong_support & tangent_a)) && (|(strong_support & tangent_b)));
 // Asymmetric tie break thins equal-gradient plateaus. Zero never seeds.
 // Use tolerance only beside a pronounced flank. On a broad soft edge,
 // retain exact NMS; tolerance there could create peaks down its slope.
 wire [11:0] min_neighbor={1'b0,(na<nc ? na:nc)};
 wire [11:0] effective_tolerance={1'b0,mag}>min_neighbor+4*NMS_TOLERANCE ? NMS_TOLERANCE:0;
 wire [11:0] mag_tolerance={1'b0,mag}+effective_tolerance;
 wire [11:0] nc_tolerance={1'b0,nc}+effective_tolerance;
 // Treat small peak differences on sharp plateaus deterministically.
 wire peak=!nb && mag!=0 && mag_tolerance>={1'b0,na} && {1'b0,mag}>nc_tolerance;
 wire held_peak,competing_history;
 if(TEMPORAL_NMS) begin:stable_peak_logic
  // Keep an already established peak through a small (3 gradient units)
  // amplitude fluctuation or a <=2-unit normal-direction peak tie.
  // Current bilateral support remains mandatory; a disappeared edge releases
  // immediately. The user's high threshold still controls every new seed.
  wire [10:0] falling=local_high>3 ? local_high-11'd3:11'd0;
  wire [10:0] hold_limit=falling>local_low ? falling:local_low;
  wire bilateral=|(weak_support & tangent_a) && |(weak_support & tangent_b);
  assign held_peak=!nb && n22[NW-1] && mag!=0 && mag>=hold_limit && bilateral &&
                   {1'b0,mag}+12'd2>={1'b0,na} && {1'b0,mag}+12'd2>={1'b0,nc};
  function competing;
   input [NW-1:0] p;
   input [10:0] center_mag,limit;
   input [1:0] center_direction;
   input center_sign;
   begin competing=p[NW-1] && p[18:8]!=0 && p[18:8]>=limit &&
    {1'b0,p[18:8]}+12'd2>={1'b0,center_mag} && p[20:19]==center_direction && p[21]==center_sign;end
  endfunction
  assign competing_history=competing(normal_a,mag,hold_limit,n22[20:19],n22[21]) ||
                           competing(normal_c,mag,hold_limit,n22[20:19],n22[21]);
 end else begin:original_peak_logic
  assign held_peak=0;assign competing_history=0;
 end
 wire selected_peak=held_peak || (peak && !competing_history);
 wire [11:0] protect_threshold={local_high,1'b0};
 wire coherent_guard;
 if(COHERENT_PROTECT) begin:coherent_motion
  // A noise peak is insufficient: both sides must carry the same direction,
  // gradient sign and >=3/4 of its magnitude. No hidden user threshold floor.
  wire [10:0] relative_limit=mag-{2'b0,mag[10:2]};
  wire [10:0] limit=relative_limit>local_high ? relative_limit:local_high;
  function supports_motion;
   input [21:0] p;input [10:0] threshold;input [1:0] d;input sign_bit;
   begin supports_motion=p[18:8]!=0 && p[18:8]>=threshold &&
     p[20:19]==d && p[21]==sign_bit;end
  endfunction
  wire [7:0] supports={supports_motion(n21,limit,n22[20:19],n22[21]),supports_motion(n31,limit,n22[20:19],n22[21]),supports_motion(n32,limit,n22[20:19],n22[21]),supports_motion(n33,limit,n22[20:19],n22[21]),
                      supports_motion(n23,limit,n22[20:19],n22[21]),supports_motion(n13,limit,n22[20:19],n22[21]),supports_motion(n12,limit,n22[20:19],n22[21]),supports_motion(n11,limit,n22[20:19],n22[21])};
  assign coherent_guard=|(supports & tangent_a) && |(supports & tangent_b);
 end else begin:original_motion
  assign coherent_guard=1'b1;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin out_valid<=0;out_sop<=0;out_eop<=0;out_class<=0;out_gray<=0;out_protect<=0;end
  else begin
   out_valid<=use_canny ? nv : ctrl3[0];
   out_sop<=use_canny ? ns : ctrl3[2];out_eop<=use_canny ? ne : ctrl3[1];
   out_gray<=use_canny ? n22[7:0] : gray3;
   out_protect<=PROTECT_ENABLE && use_canny && peak && strong_supported &&
                {1'b0,mag}>=protect_threshold && coherent_guard;
   out_class<=use_canny ? (!selected_peak || mag<local_low || !weak_supported ? 2'd0 : held_peak || (mag>=local_high && strong_supported) ? 2'd2 : 2'd1) :
     (magnitude!=0 && magnitude>=sobel_threshold ? 2'd2 : 2'd0);
  end
 end
 end else begin:sobel_only
 always @(posedge clk or negedge rst_n)
  if(!rst_n) begin out_valid<=0;out_sop<=0;out_eop<=0;out_gray<=0;out_class<=0;end
  else begin
   out_valid<=ctrl3[0];out_sop<=ctrl3[2];out_eop<=ctrl3[1];out_gray<=gray3;out_protect<=0;
   out_class<=magnitude!=0 && magnitude>=sobel_threshold ? 2'd2 : 2'd0;
  end
 end endgenerate
endmodule

`endif
