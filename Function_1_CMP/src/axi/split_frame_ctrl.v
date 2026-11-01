// DDR controller for same-source split grayscale/edge and RGB/edge overlay.
// Fixed aligned row strides; COMPACT_BURSTS transfers only rounded real data
// lengths (32/64/96/112/128 beats), with matching read lengths. Trailing beats
// are zero-filled. COLOR_ENABLE requires C_BUF_SIZE >= 23 (8 MiB slots).
module split_frame_ctrl #(
    parameter HISTORY_ENABLE=0,FRAME_DEPTH=8,EDGE_LINES=636,GRAY_LINES=318,LETTERBOX_TOP=0,
    parameter FW=($clog2(FRAME_DEPTH)<1 ? 1 : $clog2(FRAME_DEPTH)),
    parameter COMPACT_BURSTS=0, COLOR_ENABLE=0, C_ID_LEN=4, C_DATA_LEN=128, C_DATA_SIZE=4, C_BUF_SIZE=22,
    parameter [31:0] C_BASE_ADDR=32'h00000000,parameter OVERLAY_SINGLE=0,
    parameter HISTORY_COMPARE_NATIVE=0, TEMPORAL_ENABLE=0,CONFIG_GUARD=0,MOTION_PROTECT=0,SINGLE_VIEW=0,NATIVE_GRAY=0
)(
    input wire axi_clk,input wire axi_reset,
    output wire [C_ID_LEN-1:0] axi_awid,output wire [31:0] axi_awaddr,
    output reg [7:0] axi_awlen,output wire [2:0] axi_awsize,
    output wire [1:0] axi_awburst,output wire axi_awlock,
    output wire [3:0] axi_awcache,output wire [2:0] axi_awprot,
    output wire [3:0] axi_awqos,output reg axi_awvalid,input wire axi_awready,
    output wire [C_DATA_LEN-1:0] axi_wdata,
    output wire [C_DATA_LEN/8-1:0] axi_wstrb,output wire axi_wlast,
    output reg axi_wvalid,input wire axi_wready,
    input wire [C_ID_LEN-1:0] axi_bid,input wire [1:0] axi_bresp,
    input wire axi_bvalid,output wire axi_bready,
    output wire [C_ID_LEN-1:0] axi_arid,output wire [31:0] axi_araddr,
    output reg [7:0] axi_arlen,output wire [2:0] axi_arsize,
    output wire [1:0] axi_arburst,output wire axi_arlock,
    output wire [3:0] axi_arcache,output wire [2:0] axi_arprot,
    output wire [3:0] axi_arqos,output reg axi_arvalid,input wire axi_arready,
    input wire [C_ID_LEN-1:0] axi_rid,input wire [C_DATA_LEN-1:0] axi_rdata,
    input wire [1:0] axi_rresp,input wire axi_rlast,input wire axi_rvalid,
    output wire axi_rready,
    input wire wframe_pclk,input wire wframe_eof,input wire wframe_sof,
    output wire capture_ready,
    input wire gray_data_en,input wire [7:0] gray_data,
    input wire edge_data_en,input wire [7:0] edge_data,
    input wire rgb_data_en,input wire [23:0] rgb_data,
    input wire left_rgb_data_en,input wire [23:0] left_rgb_data,
    input wire rframe_left,
    input wire overlay_requested,output reg display_overlay,
    input wire temporal_requested,input wire [11:0] edge_configuration,input wire edge_protect,
    input wire freeze_requested,input wire history_requested,input wire compare_requested,
    input wire [FW-1:0] replay_requested,left_requested,right_requested,
    output reg display_history,display_compare,
    output reg [FW-1:0] display_replay,display_left,display_right,
    output reg frozen,output reg [FW:0] history_count,
    output wire [23:0] rframe_rgb,
    input wire rframe_pclk,input wire rframe_vsync,input wire rframe_data_en,
    output wire [7:0] rframe_data,output wire [31:0] tp_o,
    output reg display_frame_toggle,
    output wire stream_available,output wire [31:0] display_frame_id,
    output reg [9:0] history_underflow_frame,history_underflow_total,
    output reg [9:0] display_underflow_frame,display_underflow_total
);
localparam [C_BUF_SIZE-1:0] EDGE_BASE=22'h000000,GRAY_BASE=22'h200000;
// RGB occupies 0x400000..0x67bfff in each 8 MiB frame slot.
// Each 848-pixel row is two bursts (512 + 336 real pixels); the second
// transfers 96 beats in compact mode. Left RGB is decimated to 424x318.
localparam [C_BUF_SIZE-1:0] RGB_BASE=24'h400000;
localparam [C_BUF_SIZE-1:0] LEFT_RGB_BASE=24'h300000;

localparam [7:0] EDGE_BEATS=NATIVE_GRAY ? 8'd120:8'd53,GRAY_BEATS=8'd27;
localparam [7:0] DDR_LINE_BEATS=8'd128;

assign axi_awid=0; assign axi_awsize=C_DATA_SIZE; assign axi_awburst=2'b01;
assign axi_awlock=0; assign axi_awcache=0; assign axi_awprot=0; assign axi_awqos=0;
assign axi_wstrb={C_DATA_LEN/8{1'b1}}; assign axi_bready=1'b1;
assign axi_arid=0; assign axi_arsize=C_DATA_SIZE; assign axi_arburst=2'b01;
assign axi_arlock=0; assign axi_arcache=0; assign axi_arprot=0; assign axi_arqos=0;
// Packed history responses are expanded through the existing display FIFO.


// Safe camera-to-AXI end-of-frame event transfer.
reg eof_toggle;
always @(posedge wframe_pclk or posedge axi_reset)
    if(axi_reset) eof_toggle<=0; else if(wframe_eof) eof_toggle<=~eof_toggle;
reg [2:0] eof_sync;
always @(posedge axi_clk or posedge axi_reset)
    if(axi_reset) eof_sync<=0; else eof_sync<={eof_sync[1:0],eof_toggle};
wire eof_event=eof_sync[2]^eof_sync[1];

// One complete image transaction: gray and locally linked edges overlap. Do not
// accept another camera frame until the final DDR write response is received.
reg commit_toggle;
reg [2:0] commit_sync;
reg capture_pending;
reg [4:0] capture_warmup;
always @(posedge wframe_pclk or posedge axi_reset) begin
 if(axi_reset) begin commit_sync<=0;capture_pending<=0;capture_warmup<=0;end
 else begin
  commit_sync<={commit_sync[1:0],commit_toggle};
  if(capture_warmup!=31) capture_warmup<=capture_warmup+1'b1;
  if(commit_sync[2]^commit_sync[1]) begin capture_pending<=0;capture_warmup<=0;end
  if(wframe_sof) capture_pending<=1;
 end
end
reg [1:0] history_camera;
wire history_reader_active;
always @(posedge wframe_pclk or posedge axi_reset)
 if(axi_reset) history_camera<=0;
 else history_camera<={history_camera[0],history_reader_active};
// Freeze stops new captures as soon as it is requested: the ring continuously
// tracks the newest frames during live display, so no refill pass is needed.
assign capture_ready=!capture_pending && capture_warmup==31 && (!HISTORY_ENABLE || !freeze_requested) && (!HISTORY_ENABLE || freeze_requested || !history_camera[1]);

reg wfifo_rst;
wire [127:0] edge_fifo_data,gray_fifo_data;
wire edge_fifo_pempty,edge_fifo_empty,gray_fifo_pempty,gray_fifo_empty;
wire edge_fifo_read,gray_fifo_read;
wire [9:0] edge_fifo_count,gray_fifo_count;
W0_FIFO_8 u_edge_write_fifo(
 .wr_clk_i(wframe_pclk),.wr_en_i(edge_data_en),.wdata(MOTION_PROTECT ? {edge_protect && (edge_data!=0),6'd0,edge_data!=0}:edge_data),.a_rst_i(wfifo_rst),
 .rd_clk_i(axi_clk),.rd_en_i(edge_fifo_read),.rdata(edge_fifo_data),
 .rd_datacount_o(edge_fifo_count),.prog_empty_o(edge_fifo_pempty),.empty_o(edge_fifo_empty));
W0_FIFO_8 u_gray_write_fifo(
 .wr_clk_i(wframe_pclk),.wr_en_i(gray_data_en),.wdata(gray_data),.a_rst_i(wfifo_rst),
 .rd_clk_i(axi_clk),.rd_en_i(gray_fifo_read),.rdata(gray_fifo_data),
 .rd_datacount_o(gray_fifo_count),.prog_empty_o(gray_fifo_pempty),.empty_o(gray_fifo_empty));

wire [127:0] rgb_fifo_data;
wire rgb_fifo_empty,rgb_fifo_read;
wire [9:0] rgb_fifo_count,left_fifo_count;
wire [127:0] left_fifo_data;
wire left_fifo_read;
generate if(COLOR_ENABLE) begin: rgb_capture
 W0_FIFO_32 u_rgb_write_fifo(
  .wr_clk_i(wframe_pclk),.wr_en_i(rgb_data_en),.wdata({8'd0,rgb_data}),
  .a_rst_i(wfifo_rst),.rd_clk_i(axi_clk),.rd_en_i(rgb_fifo_read),
  .rdata(rgb_fifo_data),.empty_o(rgb_fifo_empty),.rd_datacount_o(rgb_fifo_count));
 W0_FIFO_32 u_left_write_fifo(
  .wr_clk_i(wframe_pclk),.wr_en_i(left_rgb_data_en),.wdata({8'd0,left_rgb_data}),
  .a_rst_i(wfifo_rst),.rd_clk_i(axi_clk),.rd_en_i(left_fifo_read),
  .rdata(left_fifo_data),.rd_datacount_o(left_fifo_count));
end else begin: no_rgb_capture
 assign left_fifo_data=0;assign left_fifo_count=0;assign rgb_fifo_data=0;assign rgb_fifo_empty=1;assign rgb_fifo_count=0;
end endgenerate

reg [1:0] write_frame_index,latest_frame_index,read_frame_index;
wire [1:0] write_index_p1=write_frame_index+1'b1;
wire [1:0] next_write_index=(write_index_p1==read_frame_index)?
                            write_frame_index+2'd2:write_index_p1;
localparam W_RESET=4'd0,W_IDLE=4'd1,W_ADDR=4'd2,W_DATA=4'd3,W_RESP=4'd4,W_ERROR=4'd5,
 W_HADDR=4'd6,W_HDATA=4'd7,W_HRESP=4'd8,W_CADDR=4'd9,W_CDATA=4'd10,W_CRESP=4'd11,
 W_TWAIT=5'd12,W_TADDR=5'd13,W_TDATA=5'd14,W_TRESP=5'd15,W_PACK=5'd16;
reg [4:0] wstate;
reg [7:0] write_beat;
localparam [31:0] HISTORY_BASE=32'h02000000; // after four 8 MiB live slots
// Comparison thumbnails: eight 1 MiB slots, 424-byte rows at 512-byte stride.
// Pixels are the complete edge frame reduced exactly 2:1 by 2x2 block OR.
// Full-frame binary thumbnails: exact 2:1 reduction (848x636 -> 424x318).
// Each stored pixel is the OR of its 2x2 source block, so one-pixel edges
// survive; no interpolation, gray levels or aspect change. Eight 1 MiB
// slots, 424-byte rows (27 beats, last beat half padding) at 512 stride.
localparam [31:0] COMPARE_BASE=32'h02100000;
// Preserve the original canvas placement and 2x2 pooling phase without
// processing or storing its black rows. Odd final unpaired rows are retained.
localparam EDGE_DISPLAY_TOP=42+LETTERBOX_TOP;
localparam GRAY_DISPLAY_TOP=201+(LETTERBOX_TOP+1)/2;
localparam COMPARE_LINES=(EDGE_LINES+1+(LETTERBOX_TOP%2))/2;
reg [FW-1:0] history_write_index;
// A flat register bank avoids mixed word/subword writes to inferred RAM.
// Efinity 2026.1 can crash while flattening that RAM with binary edge inputs.
reg [895:0] history_row; // 112 bytes, binary AFTER edge detection
wire [15:0] packed_edge,packed_protect;
wire [127:0] decoded_edge_data;
genvar hb;
generate for(hb=0;hb<16;hb=hb+1) begin:pack_binary
 assign packed_edge[hb]=MOTION_PROTECT ? edge_fifo_data[hb*8]:(edge_fifo_data[hb*8+:8]!=0);
 assign packed_protect[hb]=MOTION_PROTECT && edge_fifo_data[hb*8+7] && edge_fifo_data[hb*8];
 assign decoded_edge_data[hb*8+:8]=MOTION_PROTECT ? {8{edge_fifo_data[hb*8]}}:edge_fifo_data[hb*8+:8];
end endgenerate
always @(posedge axi_clk) begin
 if(HISTORY_ENABLE && !NATIVE_GRAY && edge_fifo_read)
  history_row[write_beat*16+:16]<=packed_edge;
end
// Keep raw binary history as the voting source; never feed filtered output back.
// Camera configuration is fixed at accepted SOP, then held until frame commit.
reg temporal_camera;
reg [1:0] temporal_sync;
reg [11:0] previous_configuration;reg [1:0] compatible_frames;
 always @(posedge wframe_pclk or posedge axi_reset)
 if(axi_reset) begin temporal_camera<=0;previous_configuration<=0;compatible_frames<=0;end
 else if(wframe_sof) begin
  // Capture is serialized through DDR commit, so previous SOPs here are
  // completed frames. An AXI failure stops capture and cannot enter history.
  temporal_camera<=TEMPORAL_ENABLE && HISTORY_ENABLE && FRAME_DEPTH>=3 && temporal_requested &&
    (!CONFIG_GUARD || (edge_configuration==previous_configuration && compatible_frames>=2));
  previous_configuration<=edge_configuration;
  if(compatible_frames==0 || edge_configuration!=previous_configuration) compatible_frames<=1;
  else if(compatible_frames<2) compatible_frames<=compatible_frames+1'b1;
 end
always @(posedge axi_clk or posedge axi_reset)
 if(axi_reset) temporal_sync<=0;
 else temporal_sync<={temporal_sync[0],temporal_camera};
reg [895:0] temporal_previous,temporal_row;
reg temporal_done,temporal_error;
reg temporal_phase,temporal_disagree;
wire temporal_active=TEMPORAL_ENABLE && temporal_sync[1] && history_count>=2;
// The raw row is stable from HADDR through TWAIT. Read the older slots
// concurrently with its history write, keeping completion until consumed.
wire temporal_read_request=temporal_active &&
 (wstate==W_HADDR || wstate==W_HDATA || wstate==W_HRESP || wstate==W_TWAIT);
wire writing_temporal=wstate==W_TADDR || wstate==W_TDATA || wstate==W_TRESP;
wire [127:0] temporal_write_data;
genvar tv;
generate for(tv=0;tv<16;tv=tv+1) begin:expand_temporal_write
 wire [10:0] index=write_beat*16+tv;
 assign temporal_write_data[tv*8+:8]={8{index<848 && temporal_row[index]}};
end endgenerate
reg [2:0] freeze_sync,pending_sync;

reg frame_available;
reg [31:0] completed_generation;
reg write_gray,write_rgb,write_left,last_write_gray,eof_pending;
reg [8:0] left_write_line;
reg [C_BUF_SIZE-1:0] left_write_addr;
reg [9:0] rgb_write_line;
reg rgb_write_half;
reg [C_BUF_SIZE-1:0] rgb_write_addr;

reg [10:0] edge_write_line;
reg [8:0] gray_write_line;
reg [C_BUF_SIZE-1:0] edge_write_addr,gray_write_addr;
wire edge_ready=(edge_write_line<EDGE_LINES)&&
                (COMPACT_BURSTS ? edge_fifo_count>=EDGE_BEATS : ((!edge_fifo_pempty)||(eof_pending&&!edge_fifo_empty)));
wire gray_ready=(gray_write_line<GRAY_LINES)&&
                (COMPACT_BURSTS ? gray_fifo_count>=GRAY_BEATS : ((!gray_fifo_pempty)||(eof_pending&&!gray_fifo_empty)));
wire rgb_ready=COLOR_ENABLE && rgb_write_line<EDGE_LINES &&
               rgb_fifo_count >= (rgb_write_half ? 10'd84 : 10'd128);
wire left_ready=COLOR_ENABLE && left_write_line<GRAY_LINES && left_fifo_count>=106;
always @(posedge axi_clk or posedge axi_reset) begin
 if(axi_reset) begin freeze_sync<=0;pending_sync<=0;frozen<=0;end
 else begin
  freeze_sync<={freeze_sync[1:0],HISTORY_ENABLE && freeze_requested};
  pending_sync<={pending_sync[1:0],capture_pending};
// Freeze completes once the accepted camera frame is fully committed, even
// when the ring is not full yet (e.g. gear 4 entered right after reset).
   frozen<=freeze_sync[2] && !pending_sync[2] && (wstate==W_IDLE || wstate==W_RESET) && edge_write_line==0 && gray_write_line==0;
 end
end
wire choose_gray=gray_ready&&(!edge_ready||!last_write_gray);
wire [7:0] selected_write_beats=COMPACT_BURSTS ?
 (rgb_ready ? (rgb_write_half ? 8'd96 : 8'd128) : left_ready ? 8'd112 :
  choose_gray ? 8'd32 : NATIVE_GRAY ? 8'd128 : 8'd64) : DDR_LINE_BEATS;
wire writing_history=wstate==W_HADDR || wstate==W_HDATA || wstate==W_HRESP;
wire writing_compare=wstate==W_CADDR || wstate==W_CDATA || wstate==W_CRESP;
// Horizontal pair-OR of the current source row, combined with the held
// previous row to form one thumbnail output row (2x2 block OR).
wire [423:0] thumb_hrow;
genvar tb;
generate for(tb=0;tb<424;tb=tb+1) begin:thumb_horizontal
 assign thumb_hrow[tb]=history_row[2*tb] | history_row[2*tb+1];
end endgenerate
reg [423:0] thumb_prev;
wire thumb_wait=(edge_write_line[0] ^ (LETTERBOX_TOP%2!=0)) && edge_write_line!=EDGE_LINES;
wire thumb_single=(edge_write_line==1 && LETTERBOX_TOP%2!=0) ||
                  (edge_write_line==EDGE_LINES && (edge_write_line[0] ^ (LETTERBOX_TOP%2!=0)));
wire [423:0] thumb_out=thumb_hrow | (thumb_single ? 424'd0 : thumb_prev);
wire [127:0] compare_write_data;
genvar cp;
generate for(cp=0;cp<16;cp=cp+1) begin:expand_native_write
 wire [9:0] thumb_index=write_beat*16+cp;
 assign compare_write_data[cp*8+:8]={8{thumb_index<424 && thumb_out[thumb_index]}};
end endgenerate
assign axi_awaddr=writing_temporal ? C_BASE_ADDR+{write_frame_index,EDGE_BASE}+((edge_write_line-1)<<11) : writing_compare ? COMPARE_BASE+(history_write_index<<20)+(((edge_write_line-1+(LETTERBOX_TOP%2))>>1)<<9) : writing_history ? HISTORY_BASE+(history_write_index<<17)+((edge_write_line-1)<<7) : C_BASE_ADDR+{write_frame_index,
                    (write_left?left_write_addr:(write_rgb?rgb_write_addr:(write_gray?gray_write_addr:edge_write_addr)))};
wire write_real_data=write_left ? write_beat<106 : write_rgb ? (write_beat<(rgb_write_half ? 84 : 128)) : write_gray?(write_beat<GRAY_BEATS):(write_beat<EDGE_BEATS);
assign axi_wdata=writing_temporal ? temporal_write_data : writing_compare ? compare_write_data : writing_history ? (write_beat==6 ? {48'd0,history_row[768+:80]} : history_row[write_beat*128+:128]) : write_real_data?(write_left?left_fifo_data:(write_rgb?rgb_fifo_data:(write_gray?gray_fifo_data:decoded_edge_data))):128'd0;
assign axi_wlast=(write_beat==axi_awlen);
assign edge_fifo_read=(wstate==W_PACK && !edge_fifo_empty) || !writing_temporal&&!writing_history&&!writing_compare&&axi_wvalid&&axi_wready&&!write_left&&!write_rgb&&!write_gray&&write_real_data;
assign gray_fifo_read=!writing_temporal&&!writing_history&&!writing_compare&&axi_wvalid&&axi_wready&&!write_left&&!write_rgb&&write_gray&&write_real_data;
assign left_fifo_read=!writing_temporal&&!writing_history&&!writing_compare&&axi_wvalid&&axi_wready&&write_left&&write_real_data;
assign rgb_fifo_read=!writing_temporal&&!writing_history&&!writing_compare&&axi_wvalid&&axi_wready&&!write_left&&write_rgb&&write_real_data;

always @(posedge axi_clk or posedge axi_reset) begin
 if(axi_reset) begin
  wstate<=W_RESET; wfifo_rst<=1; axi_awvalid<=0; axi_wvalid<=0; axi_awlen<=0;
  write_left<=0;left_write_line<=0;left_write_addr<=LEFT_RGB_BASE;
  write_rgb<=0;rgb_write_line<=0;rgb_write_half<=0;rgb_write_addr<=RGB_BASE;
  write_gray<=0; last_write_gray<=0; write_beat<=0; edge_write_line<=0;
  gray_write_line<=0; edge_write_addr<=EDGE_BASE; gray_write_addr<=GRAY_BASE;
   eof_pending<=0; write_frame_index<=0; latest_frame_index<=0;
   commit_toggle<=0;frame_available<=0;completed_generation<=0;history_write_index<=0;history_count<=0;
  end else begin
   if(eof_event) eof_pending<=1;
  if(axi_awvalid&&axi_awready) axi_awvalid<=0;
  case(wstate)
   W_RESET: begin wfifo_rst<=0; wstate<=W_IDLE; end
    W_IDLE: begin
     write_beat<=0;
     if(rgb_ready||left_ready||edge_ready||gray_ready) begin
     write_left<=!rgb_ready && left_ready;write_rgb<=rgb_ready;write_gray<=choose_gray; last_write_gray<=choose_gray;
     if(temporal_active && !rgb_ready && !left_ready && !choose_gray) begin
      // Pack the raw row directly from its FIFO. Only the final voted row
      // needs an 8-bit live DDR write; retain raw 1-bit history for voting.
      wstate<=W_PACK;
     end else begin
      axi_awlen<=selected_write_beats-1'b1;
      axi_awvalid<=1; wstate<=W_ADDR;
     end
    end else if(eof_pending&&(edge_write_line==EDGE_LINES)&&
                            (gray_write_line==GRAY_LINES)&&(!COLOR_ENABLE || rgb_write_line==EDGE_LINES && left_write_line==GRAY_LINES)) begin
     latest_frame_index<=write_frame_index; write_frame_index<=next_write_index;
     edge_write_line<=0; gray_write_line<=0; edge_write_addr<=EDGE_BASE;
     gray_write_addr<=GRAY_BASE;rgb_write_line<=0;rgb_write_half<=0;rgb_write_addr<=RGB_BASE;left_write_line<=0;left_write_addr<=LEFT_RGB_BASE; eof_pending<=0; wfifo_rst<=1; wstate<=W_RESET;
     commit_toggle<=~commit_toggle;frame_available<=1;
     completed_generation<=completed_generation+1'b1;
      if(HISTORY_ENABLE) begin
       history_write_index<=history_write_index==FRAME_DEPTH-1 ? 0 : history_write_index+1'b1;
       if(history_count<FRAME_DEPTH) history_count<=history_count+1'b1;
      end
    end
   end
   W_PACK:if(edge_fifo_read) begin
    if(write_beat==EDGE_BEATS-1) begin
     edge_write_line<=edge_write_line+1'b1;edge_write_addr<=edge_write_addr+22'd2048;
     write_beat<=0;axi_awlen<=6;axi_awvalid<=1;wstate<=W_HADDR;
    end else write_beat<=write_beat+1'b1;
   end
   W_ADDR:if(axi_awready) begin axi_wvalid<=1;wstate<=W_DATA;end
   W_DATA: if(axi_wvalid&&axi_wready) begin
    if(axi_wlast) begin
     axi_wvalid<=0;
     if(write_left) begin left_write_line<=left_write_line+1'b1;left_write_addr<=left_write_addr+2048;end
     else if(write_rgb) begin
      rgb_write_half<=~rgb_write_half;
      if(rgb_write_half) rgb_write_line<=rgb_write_line+1'b1;
      rgb_write_addr<=rgb_write_addr+2048;
     end else if(write_gray) begin gray_write_line<=gray_write_line+1'b1;
                          gray_write_addr<=gray_write_addr+22'd2048; end
     else begin edge_write_line<=edge_write_line+1'b1;
                edge_write_addr<=edge_write_addr+22'd2048; end
     wstate<=W_RESP;
    end else write_beat<=write_beat+1'b1;
   end
   W_RESP:if(axi_bvalid) begin
    if(axi_bresp==2'b00) begin
     if(HISTORY_ENABLE && !NATIVE_GRAY && !write_left && !write_rgb && !write_gray) begin
      write_beat<=0;axi_awlen<=6;axi_awvalid<=1;wstate<=W_HADDR;
     end else wstate<=W_IDLE;
    end
    else wstate<=W_ERROR; // Never publish a partial/failed frame; reset recovers.
   end
   W_HADDR:if(axi_awready) begin axi_wvalid<=1;wstate<=W_HDATA;end
   W_HDATA:if(axi_wvalid && axi_wready) begin
    if(axi_wlast) begin axi_wvalid<=0;wstate<=W_HRESP;end
    else write_beat<=write_beat+1'b1;
   end
    W_HRESP:if(axi_bvalid) begin
     if(axi_bresp==0) begin
      if(temporal_active) begin
       // Older-slot reads may already be complete. Keep the current row
       // and ring pointer stable until the voted live row is committed.
       wstate<=W_TWAIT;
      end else if(HISTORY_COMPARE_NATIVE && thumb_wait) begin
       // Even source row: hold its horizontal pair-OR for the next row.
       thumb_prev<=thumb_hrow;wstate<=W_IDLE;
      end else if(HISTORY_COMPARE_NATIVE) begin
       write_beat<=0;axi_awlen<=26;axi_awvalid<=1;wstate<=W_CADDR;
      end else wstate<=W_IDLE;
     end else wstate<=W_ERROR;
    end
   W_TWAIT:if(temporal_done) begin
    if(temporal_error) wstate<=W_ERROR;
    else begin write_beat<=0;axi_awlen<=COMPACT_BURSTS ? 63 : 127;axi_awvalid<=1;wstate<=W_TADDR;end
   end
   W_TADDR:if(axi_awready) begin axi_wvalid<=1;wstate<=W_TDATA;end
   W_TDATA:if(axi_wvalid && axi_wready) begin
    if(axi_wlast) begin axi_wvalid<=0;wstate<=W_TRESP;end
    else write_beat<=write_beat+1'b1;
   end
   W_TRESP:if(axi_bvalid) begin
    if(axi_bresp!=0) wstate<=W_ERROR;
    else if(HISTORY_COMPARE_NATIVE && thumb_wait) begin thumb_prev<=thumb_hrow;wstate<=W_IDLE;end
    else if(HISTORY_COMPARE_NATIVE) begin write_beat<=0;axi_awlen<=26;axi_awvalid<=1;wstate<=W_CADDR;end
    else wstate<=W_IDLE;
   end
   W_CADDR:if(axi_awready) begin axi_wvalid<=1;wstate<=W_CDATA;end
   W_CDATA:if(axi_wvalid && axi_wready) begin
    if(axi_wlast) begin axi_wvalid<=0;wstate<=W_CRESP;end
    else write_beat<=write_beat+1'b1;
   end
   W_CRESP:if(axi_bvalid) begin
    if(axi_bresp==0) wstate<=W_IDLE;else wstate<=W_ERROR;
   end
   W_ERROR:wstate<=W_ERROR;
   default:wstate<=W_RESET;
  endcase
 end
end

// HDMI frame boundary resets the display FIFO, just as in the original controller.
reg rvs_d;
reg overlay_meta,overlay_sync;
localparam REQUEST_WIDTH=3+3*FW;
reg [REQUEST_WIDTH-1:0] history_meta,history_sync;
wire [REQUEST_WIDTH-1:0] history_request={HISTORY_ENABLE && history_requested,
 compare_requested,replay_requested,left_requested,right_requested,1'b0};
always @(posedge rframe_pclk or posedge axi_reset) begin
 if(axi_reset) begin
  overlay_meta<=0;overlay_sync<=0;display_overlay<=0;history_meta<=0;history_sync<=0;
  display_history<=0;display_compare<=0;display_replay<=0;display_left<=0;display_right<=0;
 end
 else begin
  overlay_meta<=COLOR_ENABLE && overlay_requested;overlay_sync<=overlay_meta;
  history_meta<=history_request;history_sync<=history_meta;
  if(rvs_d&&!rframe_vsync) begin
   display_overlay<=overlay_sync && !history_sync[REQUEST_WIDTH-1];
   {display_history,display_compare,display_replay,display_left,display_right}<=history_sync[REQUEST_WIDTH-1:1];
  end
 end
end
reg [4:0] rfifo_reset_count;
reg rfifo_rst;
always @(posedge rframe_pclk or posedge axi_reset) begin
 if(axi_reset) begin rvs_d<=0;rfifo_reset_count<=5'h1f;rfifo_rst<=1; end
 else begin
  rvs_d<=rframe_vsync;
  if(rvs_d&&!rframe_vsync) rfifo_reset_count<=5'h1f;
  else if(rfifo_reset_count!=0) rfifo_reset_count<=rfifo_reset_count-1'b1;
  rfifo_rst<=(rfifo_reset_count!=0);
 end
end
wire rfifo_reset=axi_reset||rfifo_rst;
wire rfifo_full,rfifo_empty;
assign stream_available=!rfifo_empty && !rfifo_reset;
// Count missing visible history pixels, independently of the protected FIFO
// read enable. Publish the last completed frame at vertical blank; saturate.
reg [9:0] history_underflow_current;
always @(posedge rframe_pclk or posedge axi_reset) begin
 if(axi_reset) begin
  history_underflow_current<=0;history_underflow_frame<=0;history_underflow_total<=0;
 end else if(rvs_d&&!rframe_vsync) begin
  history_underflow_frame<=history_underflow_current;history_underflow_current<=0;
 end else if(display_history && rframe_data_en && !rfifo_reset && rfifo_empty) begin
  if(history_underflow_current<999) history_underflow_current<=history_underflow_current+1'b1;
  if(history_underflow_total<999) history_underflow_total<=history_underflow_total+1'b1;
 end
end
reg rfifo_write;
reg [127:0] rfifo_write_data;
wire [7:0] display_fifo_data;
wire rgb_display_full,rgb_display_empty;
wire [31:0] rgb_display_data;
reg rgb_rfifo_write;
wire display_take=rframe_data_en && !(display_overlay && rframe_left) && !rfifo_empty &&
                  (!display_overlay || !rgb_display_empty);
wire rgb_display_take=rframe_data_en && display_overlay && !rgb_display_empty &&
                      (rframe_left || !rfifo_empty);
assign rframe_data=rfifo_empty ? 8'd0 : display_fifo_data;
assign rframe_rgb=(!display_overlay || (!rframe_left && rfifo_empty) || rgb_display_empty) ? 24'd0 :
                  (!rframe_left && display_fifo_data!=0 ? 24'hff0000 : rgb_display_data[23:0]);
generate if(COLOR_ENABLE) begin: rgb_display
 R0_FIFO_32 u_rgb_read_fifo(
  .wr_clk_i(axi_clk),.wr_en_i(rgb_rfifo_write),.wdata(rfifo_write_data),
  .a_rst_i(rfifo_reset),.prog_full_o(rgb_display_full),.rd_clk_i(rframe_pclk),
  .rd_en_i(rgb_display_take),.rdata(rgb_display_data),.empty_o(rgb_display_empty));
end else begin: no_rgb_display
 assign rgb_display_data=0;assign rgb_display_full=0;assign rgb_display_empty=1;
end endgenerate
R0_FIFO_8 u_display_read_fifo(
 .wr_clk_i(axi_clk),.wr_en_i(rfifo_write),.wdata(rfifo_write_data),
 .a_rst_i(rfifo_reset),.prog_full_o(rfifo_full),.rd_clk_i(rframe_pclk),
 .rd_en_i(display_take),.rdata(display_fifo_data),.empty_o(rfifo_empty),.almost_empty_o());

reg [2:0] rrst_sync;
always @(posedge axi_clk or posedge axi_reset)
 if(axi_reset) rrst_sync<=3'b111; else rrst_sync<={rrst_sync[1:0],rfifo_reset};
wire read_frame_start=rrst_sync[2]&&!rrst_sync[1];
localparam R_IDLE=3'd0,R_ADDR=3'd1,R_DATA=3'd2,R_TADDR=3'd3,R_TDATA=3'd4;
reg [2:0] rstate;
reg read_pending;
reg [7:0] read_beat;
wire reading_temporal=rstate==R_TADDR || rstate==R_TDATA;
// Pack confidence into seven full words. A small synchronous RAM avoids
// mixed 16/128-bit writes and the large per-bit muxes they require.
wire [127:0] confidence_word;
generate if(MOTION_PROTECT) begin:confidence_cache
 reg [127:0] words[0:7];
 reg [127:0] pack;
 reg [127:0] word_q;
 wire save=edge_fifo_read && temporal_active;
 wire last_word=write_beat==52;
 wire word_end=write_beat[2:0]==7 || last_word;
 wire [127:0] packed_word=last_word ? {48'd0,packed_protect,pack[127:64]}:
                                                   {packed_protect,pack[127:16]};
 // Prefetch the following protection word as each first-phase AXI beat
 // is accepted. The first word is already present before AR is launched.
 wire advance=reading_temporal && !temporal_phase && axi_rvalid && axi_rready && read_pending;
 wire [2:0] address=advance ? read_beat[2:0]+1'b1:read_beat[2:0];
 always @(posedge axi_clk) begin
  if(save && word_end) words[write_beat[5:3]]<=packed_word;
  word_q<=words[address];
 end
 always @(posedge axi_clk or posedge axi_reset)
 if(axi_reset) pack<=0;
 else if(save) pack<=word_end ? 128'd0:{packed_protect,pack[127:16]};
 assign confidence_word=word_q;
end else begin:no_confidence_cache
 assign confidence_word=0;
end endgenerate
wire [127:0] previous_vote=axi_rdata | confidence_word;
reg temporal_resume_addr;
function [FW-1:0] preceding_slot;
 input [FW-1:0] current;input second;integer n;
 begin n=current-(second ? 2 : 1);
 if(n<0) n=n+FRAME_DEPTH;preceding_slot=n;end
endfunction
reg [10:0] output_row,edge_read_line;
reg [8:0] gray_read_line;
reg read_gray,read_rgb,read_left,read_rgb_half,read_overlay,restart_pending;
reg [1:0] overlay_axi_sync;
reg [REQUEST_WIDTH-2:0] selection_meta,selection_sync;
always @(posedge axi_clk or posedge axi_reset)
 if(axi_reset) begin selection_meta<=0;selection_sync<=0;end
 else begin
  selection_meta<={display_history,display_compare,display_replay,display_left,display_right};
  selection_sync<=selection_meta;
 end
reg read_history,read_compare,history_side;
reg [FW-1:0] history_read_left,history_read_right;
reg [127:0] history_word;
reg history_word_valid;
reg [3:0] history_group;
reg [2:0] history_beat;
reg [9:0] history_line;
// Comparison reads byte-wide binary thumbnails directly. The display only
// switches to history after freeze, so the stored frames are stable.
reg [8:0] history_output_line;
wire native_compare=HISTORY_COMPARE_NATIVE && read_history && read_compare;
function [FW-1:0] history_slot;
 input [FW-1:0] logical_frame;
 integer base,n;
 begin
  base=history_count==FRAME_DEPTH ? history_write_index : 0;
  n=base+(logical_frame>=history_count ? (history_count==0 ? 0 : history_count-1) : logical_frame);
  if(n>=FRAME_DEPTH) n=n-FRAME_DEPTH;
  history_slot=n;
 end
endfunction
wire [127:0] expanded_history;
wire [8:0] history_bit_base=read_compare ? {history_group,5'b0} : {1'b0,history_group,4'b0};
genvar px;
generate for(px=0;px<16;px=px+1) begin:expand_binary
 wire [9:0] bit_index=history_bit_base+(read_compare ? 2*px : px);
 wire on=(history_beat<6 || bit_index<80) &&
          history_word[bit_index];
 assign expanded_history[px*8+:8]={8{on}};
end endgenerate
always @(posedge axi_clk or posedge axi_reset)
 if(axi_reset) overlay_axi_sync<=0;else overlay_axi_sync<={overlay_axi_sync[0],display_overlay};
reg display_started;
reg [31:0] displayed_generation;
assign display_frame_id=displayed_generation;

wire row_has_gray=!SINGLE_VIEW && (output_row>=GRAY_DISPLAY_TOP)&&(output_row<GRAY_DISPLAY_TOP+GRAY_LINES);
wire [C_BUF_SIZE-1:0] edge_read_addr=EDGE_BASE+{edge_read_line,11'd0};
wire [C_BUF_SIZE-1:0] gray_read_addr=GRAY_BASE+{gray_read_line,11'd0};
wire [C_BUF_SIZE-1:0] rgb_read_addr=read_left ? LEFT_RGB_BASE+{gray_read_line,11'd0} : RGB_BASE+{edge_read_line,12'd0}+
                                                 (read_rgb_half ? 2048 : 0);
wire [7:0] selected_read_beats=COMPACT_BURSTS ?
 (read_left ? 8'd112 : read_rgb ? (read_rgb_half ? 8'd96 : 8'd128) :
  read_gray ? 8'd32 : NATIVE_GRAY ? 8'd128 : 8'd64) : DDR_LINE_BEATS;
assign axi_araddr=reading_temporal ? HISTORY_BASE+(preceding_slot(history_write_index,temporal_phase)<<17)+((edge_write_line-1)<<7) : native_compare ?
 COMPARE_BASE+((history_side ? history_read_right : history_read_left)<<20)+(history_output_line<<9) :
 read_history ? HISTORY_BASE+((history_side ? history_read_right : history_read_left)<<17)+(history_line<<7) :
 C_BASE_ADDR+{read_frame_index,(read_rgb?rgb_read_addr:(read_gray?gray_read_addr:edge_read_addr))};

// Never cancel an accepted AXI burst at a display frame boundary. Drain the
// old response, discard its pixels, then start a fresh display frame.
always @(posedge axi_clk or posedge axi_reset) begin
 if(axi_reset) begin
  rstate<=R_IDLE;axi_arvalid<=0;axi_arlen<=DDR_LINE_BEATS-1'b1;read_pending<=0;
  output_row<=EDGE_DISPLAY_TOP;edge_read_line<=0;gray_read_line<=0;read_gray<=0;
  read_left<=0;read_rgb<=0;read_rgb_half<=0;read_overlay<=0;rgb_rfifo_write<=0;
  read_frame_index<=0;rfifo_write<=0;rfifo_write_data<=0;read_beat<=0;
  restart_pending<=1;read_history<=0;read_compare<=0;history_side<=0;history_read_left<=0;history_read_right<=0;history_line<=0;history_word<=0;history_word_valid<=0;history_group<=0;history_beat<=0;
   history_output_line<=0;
  display_frame_toggle<=0;displayed_generation<=0;display_started<=0;
  temporal_done<=0;temporal_error<=0;temporal_phase<=0;temporal_disagree<=0;temporal_resume_addr<=0;
 end else begin
  rfifo_write<=0;rgb_rfifo_write<=0;
  if(!temporal_read_request) temporal_done<=0;
  if(read_frame_start || rrst_sync[2]) restart_pending<=1;
  if(axi_arvalid && axi_arready) begin axi_arvalid<=0;read_pending<=1;end
  if(restart_pending || read_frame_start || rrst_sync[2]) history_word_valid<=0;
  else if(history_word_valid && !rfifo_full) begin
   rfifo_write<=1;rfifo_write_data<=expanded_history;
   if(history_group==(history_beat==6 ? (read_compare ? 2 : 4) : (read_compare ? 3 : 7))) begin
    history_word_valid<=0;history_group<=0;history_beat<=history_beat+1'b1;
   end else history_group<=history_group+1'b1;
  end
  if(axi_rvalid && axi_rready && read_pending) begin
   if(reading_temporal) begin
    if(axi_rresp!=0) temporal_error<=1;
    if(!temporal_phase) begin
     temporal_previous[read_beat*128+:128]<=previous_vote;
     temporal_row[read_beat*128+:128]<=history_row[read_beat*128+:128];
     // If the current and previous rows agree, they already supply two
     // votes at every valid pixel. The older row cannot change the result.
     // Ignore the 48 padding bits in the final packed word.
     if(read_beat==6 ? history_row[768+:80]!=previous_vote[79:0] :
        history_row[read_beat*128+:128]!=previous_vote) temporal_disagree<=1;
    end
    else temporal_row[read_beat*128+:128]<=
     ((history_row[read_beat*128+:128] & temporal_previous[read_beat*128+:128]) |
     (history_row[read_beat*128+:128] & axi_rdata) |
     (temporal_previous[read_beat*128+:128] & axi_rdata)) &
     (MOTION_PROTECT ? history_row[read_beat*128+:128]:{128{1'b1}});
   end else if(!restart_pending && !read_frame_start && !rrst_sync[2] &&
      (read_left ? read_beat<106 : read_rgb ? read_beat<(read_rgb_half ? 84 : 128) : (read_gray ? read_beat<GRAY_BEATS : read_beat<EDGE_BEATS))) begin
    if(read_history) begin
     if(native_compare) begin rfifo_write<=1;rfifo_write_data<=axi_rdata;end
     else begin history_word<=axi_rdata;history_word_valid<=1;history_group<=0;end
    end
    else begin rfifo_write<=!read_rgb;rgb_rfifo_write<=read_rgb;rfifo_write_data<=axi_rdata;end
   end
   read_beat<=read_beat+1'b1;
   if(axi_rlast) read_pending<=0;
  end
  case(rstate)
   R_IDLE:begin
    // Arbitrate only between complete bursts. Display restarts may discard
    // display pixels, but must never cancel a temporal row transaction.
    if(temporal_read_request && !temporal_done && !history_word_valid) begin
     temporal_phase<=0;temporal_disagree<=0;temporal_error<=0;temporal_resume_addr<=0;read_beat<=0;rstate<=R_TADDR;
    end else if(restart_pending) begin
     if(!rrst_sync[2] && !read_frame_start) begin
      read_frame_index<=latest_frame_index;output_row<=EDGE_DISPLAY_TOP;
      {read_history,read_compare}<=selection_sync[REQUEST_WIDTH-2:REQUEST_WIDTH-3];
      history_read_left<=history_slot(selection_sync[REQUEST_WIDTH-3] ? selection_sync[2*FW-1:FW] : selection_sync[3*FW-1:2*FW]);
      history_read_right<=history_slot(selection_sync[FW-1:0]);
      history_side<=0;history_line<=0;history_beat<=0;history_word_valid<=0;history_group<=0;
       history_output_line<=0;
       edge_read_line<=0;
       gray_read_line<=0;read_gray<=0;read_left<=0;read_rgb<=0;read_rgb_half<=0;read_overlay<=overlay_axi_sync[1];read_beat<=0;
      restart_pending<=0;
      // Count each completed image only when selected for a display frame.
      // Repeated HDMI refreshes of the same image do not count as new FPS.
      if(frame_available) begin
       display_started<=1;
       if(!display_started || displayed_generation!=completed_generation) begin
        display_frame_toggle<=~display_frame_toggle;
        displayed_generation<=completed_generation;
       end
      end
     end
     end else if(!rrst_sync[2] && !read_frame_start && display_started &&
                 (read_history ? (native_compare ? history_output_line<COMPARE_LINES : history_line<EDGE_LINES) : edge_read_line<EDGE_LINES) && (!read_history || history_count!=0) && !rfifo_full && (!read_overlay || !rgb_display_full)) begin
     read_gray<=!read_overlay && row_has_gray;read_rgb<=read_overlay;read_left<=read_overlay && row_has_gray && !OVERLAY_SINGLE;read_rgb_half<=0;read_beat<=0;rstate<=R_ADDR;
    end
   end
   R_ADDR:begin
    // A color row spans multiple bursts. Service voting between any two,
    // then resume the pending display burst with its plane/row unchanged.
    if(temporal_read_request && !temporal_done && !history_word_valid) begin
     temporal_phase<=0;temporal_disagree<=0;temporal_error<=0;temporal_resume_addr<=1;read_beat<=0;rstate<=R_TADDR;
    end else begin
     axi_arlen<=native_compare ? 8'd26 : read_history ? 8'd6 : selected_read_beats-1'b1;
     axi_arvalid<=1;rstate<=R_DATA;
    end
   end
   R_DATA:if(!axi_arvalid && !read_pending && !history_word_valid) begin
    if(restart_pending || read_frame_start || rrst_sync[2]) rstate<=R_IDLE;
    else if(read_history) begin
     history_beat<=0;read_beat<=0;
      if(native_compare) begin
       if(!history_side) begin history_side<=1;rstate<=R_ADDR;end
       else begin
        history_side<=0;history_output_line<=history_output_line+1'b1;
        rstate<=R_IDLE;
       end
      end else begin
      if(read_compare && !history_side) begin history_side<=1;rstate<=R_ADDR;end
      else begin
       history_side<=0;
       history_line<=history_line+(read_compare ? 2 : 1);
       rstate<=R_IDLE;
      end
     end
    end else if(read_left) begin
     gray_read_line<=gray_read_line+1'b1;read_left<=0;read_rgb<=1;read_rgb_half<=0;read_beat<=0;rstate<=R_ADDR;
    end else if(read_rgb) begin
     read_beat<=0;
     if(!read_rgb_half) read_rgb_half<=1;
     else begin read_left<=0;read_rgb<=0;read_rgb_half<=0;end
     rstate<=R_ADDR;
    end else if(read_gray) begin
     gray_read_line<=gray_read_line+1'b1;read_gray<=0;read_beat<=0;rstate<=R_ADDR;
    end else begin
     edge_read_line<=edge_read_line+1'b1;output_row<=output_row+1'b1;rstate<=R_IDLE;
    end
   end
   R_TADDR:begin axi_arlen<=6;axi_arvalid<=1;rstate<=R_TDATA;end
   R_TDATA:if(!axi_arvalid && !read_pending) begin
    read_beat<=0;
    if(!temporal_phase && temporal_disagree) begin temporal_phase<=1;rstate<=R_TADDR;end
    else begin
     temporal_done<=1;
     rstate<=temporal_resume_addr && !restart_pending && !read_frame_start && !rrst_sync[2] ? R_ADDR : R_IDLE;
    end
   end
   default:rstate<=R_IDLE;
  endcase
 end
end
assign axi_rready=reading_temporal || !read_history || (!history_word_valid && !rfifo_full) || restart_pending || rrst_sync[2];
assign history_reader_active=read_history;
assign tp_o={27'd0,rfifo_empty,edge_data_en,gray_data_en,axi_arvalid,axi_wvalid};
// Monitor actual missing live/history pixels as well as legacy history-only
// counters. Synchronize the one-time display-start flag into the pixel clock.
reg [1:0] started_pixel;
reg [9:0] display_missing_current;
always @(posedge rframe_pclk or posedge axi_reset) begin
 if(axi_reset) begin
  started_pixel<=0;display_missing_current<=0;display_underflow_frame<=0;display_underflow_total<=0;
 end else begin
  started_pixel<={started_pixel[0],display_started};
  if(rvs_d&&!rframe_vsync) begin display_underflow_frame<=display_missing_current;display_missing_current<=0;end
  else if(started_pixel[1] && rframe_data_en && !rfifo_reset &&
    ((rfifo_empty && !(display_overlay && rframe_left)) || (display_overlay && rgb_display_empty))) begin
   if(display_missing_current<999) display_missing_current<=display_missing_current+1'b1;
   if(display_underflow_total<999) display_underflow_total<=display_underflow_total+1'b1;
  end
 end
end
endmodule


