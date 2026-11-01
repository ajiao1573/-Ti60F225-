//  by CrazyBird
module axi4_ctrl #(
	parameter 	C_ID_LEN      = 8, 
			C_DATA_LEN    = 128, 
			C_DATA_SIZE   = 4, 	//	C_DATA_LEN=8:0, 16:1, 32:2, 64:3, 128:4, 256:5, 512:6, 1024:7
			
			C_BURST_LEN   = 128,
			
			C_STRB_LEN    = C_DATA_LEN / 8, 
			C_ADDR_INC    = C_BURST_LEN * C_STRB_LEN,
			
			C_BASE_ADDR   = 32'h00000000, 	//	Start at 0x00000000 by default
			C_BUF_SIZE    = 22, 			//	Allocate 2^22 bytes (4MB) by default. The module takes 4*4MB by default. 
			C_RD_END_ADDR = 1280 * 720,
			
			C_W_WIDTH     = 64, 
			C_R_WIDTH     = 8,
            C_WR_FRAME_BYTES = C_RD_END_ADDR,
            AXI_TIMEOUT_CYCLES = 9600000
)(
    input  wire                 axi_clk         ,
    input  wire                 axi_reset       ,
    
    output       [C_ID_LEN-1:0]      axi_awid        ,
    output       [31:0]      axi_awaddr      ,
    output       [ 7:0]      axi_awlen       ,
    output       [ 2:0]      axi_awsize      ,
    output       [ 1:0]      axi_awburst     ,
    output                   axi_awlock      ,
    output       [ 3:0]      axi_awcache     ,
    output       [ 2:0]      axi_awprot      ,
    output       [ 3:0]      axi_awqos       ,
    output reg                  axi_awvalid     ,
    input  wire                 axi_awready     ,
    
    output       [C_DATA_LEN-1:0]      axi_wdata       ,
    output       [C_STRB_LEN-1:0]      axi_wstrb       ,
    output                   axi_wlast       ,
    output reg                  axi_wvalid      ,
    input  wire                 axi_wready      ,
    
    input  wire     [C_ID_LEN-1:0]      axi_bid         ,
    input  wire     [ 1:0]      axi_bresp       ,
    input  wire                 axi_bvalid      ,
    output                   axi_bready      ,
    
    output       [C_ID_LEN-1:0]      axi_arid        ,
    output       [31:0]      axi_araddr      ,
    output       [ 7:0]      axi_arlen       ,
    output       [ 2:0]      axi_arsize      ,
    output       [ 1:0]      axi_arburst     ,
    output                   axi_arlock      ,
    output       [ 3:0]      axi_arcache     ,
    output       [ 2:0]      axi_arprot      ,
    output       [ 3:0]      axi_arqos       ,
    output reg                  axi_arvalid     ,
    input  wire                 axi_arready     ,
    
    input  wire     [C_ID_LEN-1:0]      axi_rid         ,
    input  wire     [C_DATA_LEN-1:0]      axi_rdata       ,
    input  wire     [ 1:0]      axi_rresp       ,
    input  wire                 axi_rlast       ,
    input  wire                 axi_rvalid      ,
    output                   axi_rready      ,
    
    input  wire                 wframe_pclk     ,
    input  wire                 wframe_vsync    ,		//	Writter VSync. Flush on falling edge. Connect to EOF. 
    input  wire                 wframe_data_en  ,
    input  wire     [C_W_WIDTH-1:0]      wframe_data     ,
    
    input wire freeze_request_i,
    output wire frozen_o,
    input  wire                 rframe_pclk     ,
    input  wire                 rframe_vsync    ,		//	Reader VSync. Flush on falling edge. Connect to ~EOF. 
    input  wire                 rframe_data_en  ,
    output wire     [C_R_WIDTH-1:0]      rframe_data     ,
    
    output wire frame_ready_o,
    output wire video_error_o,
    output reg reset_request_o,
    output reg [7:0] error_status_o,
    output reg [15:0] write_error_count_o, read_error_count_o, fifo_error_count_o,
    output 		[31:0] 	tp_o
);
	
    assign axi_awid=0, axi_awlen=C_BURST_LEN-1, axi_awsize=C_DATA_SIZE;
    assign axi_awburst=2'b01, axi_awlock=0, axi_awcache=0, axi_awprot=0, axi_awqos=0;
    assign axi_wstrb={C_STRB_LEN{1'b1}}, axi_bready=1;
    assign axi_arid=0, axi_arlen=C_BURST_LEN-1, axi_arsize=C_DATA_SIZE;
    assign axi_arburst=2'b01, axi_arlock=0, axi_arcache=0, axi_arprot=0, axi_arqos=0;
    assign axi_rready=1;
    wire [1:0] rc_wframe_index,rc_rframe_index;
    reg r_wframe_inc,r_rframe_inc;
    reg have_frame;
    video_frame_banks frame_banks(
        .clk(axi_clk),.rst_n(~axi_reset),.write_done_i(r_wframe_inc),
        .read_start_i(r_rframe_inc),.freeze_request_i(freeze_request_i),
        .write_bank_o(rc_wframe_index),.read_bank_o(rc_rframe_index),.frozen_o(frozen_o));
    wire w_wfifo_pempty,w_wfifo_empty,w_wfifo_full;
    wire [C_DATA_LEN-1:0] w_wfifo_rdata;
    wire w_wfifo_ren=axi_wvalid && axi_wready;
    reg r_w_rst;
    reg [2:0] rs_w;
    localparam W_IDLE=0,W_DATA=1,W_RESPONSE=2,W_RESET=3;
    reg [C_BUF_SIZE:0] wr_bytes;
    reg [C_BUF_SIZE-1:0] rc_w_ptr;
    reg [7:0] rc_burst;
    reg [5:0] reset_wait;
    reg write_bad,write_fault,r_weof_pending;
    (* async_reg="true" *) reg [1:0] r_wframe_sync;
    // A level latch survives the camera/AXI clock crossing. FIFO reset clears
    // it only after the complete frame has been accepted or rejected.
    reg camera_overflow;
    (* async_reg="true" *) reg overflow_meta,overflow_sync;
    always @(posedge wframe_pclk or posedge r_w_rst) begin
        if(r_w_rst) camera_overflow<=0;
        else if(wframe_data_en && w_wfifo_full) camera_overflow<=1;
    end
    always @(posedge axi_clk or posedge axi_reset) begin
        if(axi_reset) begin overflow_meta<=0;overflow_sync<=0;end
        else begin overflow_meta<=camera_overflow;overflow_sync<=overflow_meta;end
    end
    assign axi_awaddr=C_BASE_ADDR+{rc_wframe_index,rc_w_ptr};
    assign axi_wdata=w_wfifo_rdata;
    assign axi_wlast=rc_burst==C_BURST_LEN-1;
    always @(posedge axi_clk or posedge axi_reset) begin
        if(axi_reset) begin
            rs_w<=W_RESET;reset_wait<=0;r_w_rst<=1;
            rc_w_ptr<=0;wr_bytes<=0;rc_burst<=0;
            axi_awvalid<=0;axi_wvalid<=0;r_wframe_inc<=0;
            r_wframe_sync<=0;r_weof_pending<=0;write_bad<=0;write_fault<=0;have_frame<=0;
        end else begin
            r_wframe_inc<=0;
            r_wframe_sync<={r_wframe_sync[0],wframe_vsync};
            if(r_wframe_sync==2'b10) begin
                r_weof_pending<=1;
                if(r_weof_pending) begin write_bad<=1;write_fault<=1;end
            end
            if(overflow_sync) begin write_bad<=1;write_fault<=1;end
            if(write_response_bad || write_timeout) begin write_bad<=1;write_fault<=1;end
            if(axi_awvalid && axi_awready) axi_awvalid<=0;
            case(rs_w)
                W_RESET: begin
                    r_w_rst<=1;
                    if(reset_wait==63) begin
                        r_w_rst<=0;rs_w<=W_IDLE;write_bad<=0;
                        r_weof_pending<=0;rc_w_ptr<=0;wr_bytes<=0;
                    end else reset_wait<=reset_wait+1'b1;
                end
                W_IDLE: begin
                    rc_burst<=0;
                    if(!w_wfifo_pempty && wr_bytes<C_WR_FRAME_BYTES) begin
                        axi_awvalid<=1;axi_wvalid<=1;rs_w<=W_DATA;
                    end else if(r_weof_pending) begin
                        // Native RGB565 frames are an exact number of bursts.
                        // Never pad an incomplete camera frame with empty FIFO data.
                        if(!write_bad && !write_response_bad && !write_timeout &&
                           !overflow_sync && w_wfifo_empty &&
                           wr_bytes==C_WR_FRAME_BYTES) begin
                            r_wframe_inc<=1;have_frame<=1;write_fault<=0;
                        end else write_fault<=1;
                        reset_wait<=0;r_w_rst<=1;rs_w<=W_RESET;
                    end
                end
                W_DATA: if(axi_wvalid && axi_wready) begin
                    if(axi_wlast) begin axi_wvalid<=0;rs_w<=W_RESPONSE;end
                    else rc_burst<=rc_burst+1'b1;
                end
                W_RESPONSE: if(response_seen || (axi_bvalid && axi_bready)) begin
                    // The slave must respond only after AW and all W beats.
                    // AWVALID is never withdrawn under backpressure.
                    if(!axi_awvalid || axi_awready) begin
                        wr_bytes<=wr_bytes+C_ADDR_INC;
                        rc_w_ptr<=rc_w_ptr+C_ADDR_INC;rs_w<=W_IDLE;
                    end
                end
                default: rs_w<=W_RESET;
            endcase
        end
    end
    // A response can coincide with WLAST. Keep it until AW also completes.
    // BREADY is always asserted, so the writer must remember that handshake.
    reg response_seen;
    always @(posedge axi_clk or posedge axi_reset) begin
        if(axi_reset) response_seen<=0;
        else if(rs_w==W_IDLE || rs_w==W_RESET) response_seen<=0;
        else if(axi_bvalid) response_seen<=1;
    end
    assign tp_o={error_status_o,8'b0,write_error_count_o[7:0],4'b0,
                 wframe_data_en,axi_wvalid,rs_w[1:0]};

	generate
		if(C_W_WIDTH == 64) begin: Gen_FIFO_W64
			W0_FIFO_64 u_W0_FIFO_64 
			(
			    .wr_clk_i       (wframe_pclk    ),
			    .wr_en_i        (wframe_data_en),
			    .wdata          (wframe_data    ),
			    
			    .a_rst_i 	(r_w_rst), 

			    .rd_clk_i       (axi_clk        ),
			    .rd_en_i        (w_wfifo_ren     ),
			    .rdata          (w_wfifo_rdata    ),
			    .full_o(w_wfifo_full),
                .prog_empty_o	(w_wfifo_pempty),
			    .empty_o 		(w_wfifo_empty)
			);
		end else if(C_W_WIDTH == 32) begin: Gen_FIFO_W32
			W0_FIFO_32 u_W0_FIFO_32
			(
			    .wr_clk_i       (wframe_pclk    ),
			    .wr_en_i        (wframe_data_en),
			    .wdata          (wframe_data    ),
			    
			    .a_rst_i 	(r_w_rst), 

			    .rd_clk_i       (axi_clk        ),
			    .rd_en_i        (w_wfifo_ren     ),
			    .rdata          (w_wfifo_rdata    ),
			    .full_o(w_wfifo_full),
                .prog_empty_o	(w_wfifo_pempty),
			    .empty_o 		(w_wfifo_empty)
			);
		end else if(C_W_WIDTH == 16) begin: Gen_FIFO_W32
			W0_FIFO_16 u_W0_FIFO_16
			(
			    .wr_clk_i       (wframe_pclk    ),
			    .wr_en_i        (wframe_data_en),
			    .wdata          (wframe_data    ),
			    
			    .a_rst_i 	(r_w_rst), 

			    .rd_clk_i       (axi_clk        ),
			    .rd_en_i        (w_wfifo_ren     ),
			    .rdata          (w_wfifo_rdata    ),
			    .full_o(w_wfifo_full),
                .prog_empty_o	(w_wfifo_pempty),
			    .empty_o 		(w_wfifo_empty)
			);
		end else if(C_W_WIDTH == 8) begin: Gen_FIFO_W8
			W0_FIFO_8 u_W0_FIFO_8 
			(
			    .wr_clk_i       (wframe_pclk    ),
			    .wr_en_i        (wframe_data_en),
			    .wdata          (wframe_data    ),
			    
			    .a_rst_i 	(r_w_rst), 

			    .rd_clk_i       (axi_clk        ),
			    .rd_en_i        (w_wfifo_ren     ),
			    .rdata          (w_wfifo_rdata    ),
			    .full_o(w_wfifo_full),
                .prog_empty_o	(w_wfifo_pempty),
			    .empty_o 		(w_wfifo_empty)
			);
		end
	endgenerate




















    reg rframe_vsync_dly;
    reg [5:0] rfifo_cnt;
    reg rfifo_rst;
    always @(posedge rframe_pclk or posedge axi_reset) begin
        if(axi_reset) begin rframe_vsync_dly<=0;rfifo_cnt<=63;rfifo_rst<=1;end
        else begin
            rframe_vsync_dly<=rframe_vsync;
            if(rframe_vsync_dly && !rframe_vsync) rfifo_cnt<=63;
            else if(rfifo_cnt!=0) rfifo_cnt<=rfifo_cnt-1'b1;
            rfifo_rst<=rfifo_cnt!=0;
        end
    end
    wire w_rfifo_rst=axi_reset || rfifo_rst;
    reg rfifo_wenb;
    reg [C_DATA_LEN-1:0] rfifo_wdata;
    wire rfifo_wfull,rfifo_full,w_rfifo_empty,w_rfifo_aempty;
    wire [C_R_WIDTH-1:0] rfifo_data;
    assign rframe_data=read_fault_pixel ? {C_R_WIDTH{1'b0}} : rfifo_data;
generate
	if(C_R_WIDTH == 8) begin: Gen_RFIFO_8
		R0_FIFO_8 u_R0_FIFO_8
		(
			.wr_clk_i		(axi_clk),
			.wr_en_i		(rfifo_wenb),
			.wdata			(rfifo_wdata),
			.a_rst_i		(w_rfifo_rst), 
			.full_o(rfifo_full),
            .prog_full_o		(rfifo_wfull),
			
			.rd_clk_i		(rframe_pclk),
			.rd_en_i		(rframe_data_en),
			.rdata			(rfifo_data),
			.empty_o		(w_rfifo_empty),
			.almost_empty_o	(w_rfifo_aempty)
		);
	end else if(C_R_WIDTH == 16) begin: Gen_RFIFO_16	
		R0_FIFO_16 u_R0_FIFO_16
		(
			.wr_clk_i		(axi_clk),
			.wr_en_i		(rfifo_wenb),
			.wdata			(rfifo_wdata),
			.a_rst_i		(w_rfifo_rst), 
			.full_o(rfifo_full),
            .prog_full_o		(rfifo_wfull),
			
			.rd_clk_i		(rframe_pclk),
			.rd_en_i		(rframe_data_en),
			.rdata			(rfifo_data),
			.empty_o		(w_rfifo_empty),
			.almost_empty_o	(w_rfifo_aempty)
		);
	end
endgenerate
		
    (* async_reg="true" *) reg reset_meta,r_rfifo_rst;
    reg reset_prev,flush_pending,reader_started;
    reg [2:0] rd_state;
    localparam R_IDLE=0,R_ADDR=1,R_DATA=2;
    reg [8:0] read_beats;
    reg [C_BUF_SIZE:0] araddr;
    reg [1:0] read_bank;
    reg read_fault;
    (* async_reg="true" *) reg read_fault_meta,read_fault_pixel;
    reg display_underflow;
    (* async_reg="true" *) reg underflow_meta,underflow_sync;
    always @(posedge rframe_pclk or posedge axi_reset) begin
        if(axi_reset) begin read_fault_meta<=0;read_fault_pixel<=0;display_underflow<=0;end
        else begin
            read_fault_meta<=read_fault;read_fault_pixel<=read_fault_meta;
            if(rfifo_rst) display_underflow<=0;
            else if(rframe_data_en && w_rfifo_empty) display_underflow<=1;
        end
    end
    always @(posedge axi_clk or posedge axi_reset) begin
        if(axi_reset) begin
            reset_meta<=1;r_rfifo_rst<=1;reset_prev<=1;
            underflow_meta<=0;underflow_sync<=0;
        end else begin
            reset_meta<=rfifo_rst;r_rfifo_rst<=reset_meta;reset_prev<=r_rfifo_rst;
            underflow_meta<=display_underflow;underflow_sync<=underflow_meta;
        end
    end
    assign axi_araddr=C_BASE_ADDR+{read_bank,araddr[C_BUF_SIZE-1:0]};
    wire read_response_bad=axi_rvalid &&
        (axi_rresp!=0 || axi_rid!=0 || rd_state!=R_DATA ||
         axi_rlast!=(read_beats==C_BURST_LEN-1));
    wire write_response_bad=axi_bvalid &&
        (axi_bresp!=0 || axi_bid!=0 || (rs_w!=W_DATA && rs_w!=W_RESPONSE) ||
         (axi_awvalid && !axi_awready) ||
         (rs_w==W_DATA && !(axi_wvalid && axi_wready && axi_wlast)));
    // Watchdogs count lack of progress, not total frame processing time.
    // A timed-out command remains stable until the shared master/slave reset.
    reg [31:0] write_watchdog,read_watchdog;
    wire write_active=rs_w==W_DATA || rs_w==W_RESPONSE;
    wire read_active=rd_state!=R_IDLE;
    wire write_progress=(axi_awvalid && axi_awready) ||
                        (axi_wvalid && axi_wready) || axi_bvalid;
    wire read_progress=(axi_arvalid && axi_arready) || axi_rvalid;
    wire write_timeout=write_active && write_watchdog==AXI_TIMEOUT_CYCLES-1;
    wire read_timeout=read_active && read_watchdog==AXI_TIMEOUT_CYCLES-1;
    reg overflow_prev,underflow_prev;
    wire fifo_event=(overflow_sync && !overflow_prev) ||
                    (underflow_sync && !underflow_prev) || (rfifo_wenb && rfifo_full);
    always @(posedge axi_clk or posedge axi_reset) begin
        if(axi_reset) begin
            write_watchdog<=0;read_watchdog<=0;reset_request_o<=0;error_status_o<=0;
            write_error_count_o<=0;read_error_count_o<=0;fifo_error_count_o<=0;
            overflow_prev<=0;underflow_prev<=0;
        end else begin
            if(!write_active || write_progress) write_watchdog<=0;
            else if(write_watchdog<AXI_TIMEOUT_CYCLES) write_watchdog<=write_watchdog+1'b1;
            if(!read_active || read_progress) read_watchdog<=0;
            else if(read_watchdog<AXI_TIMEOUT_CYCLES) read_watchdog<=read_watchdog+1'b1;
            overflow_prev<=overflow_sync;underflow_prev<=underflow_sync;
            if(write_response_bad) begin
                error_status_o[0]<=1;
                if(write_error_count_o!=65535) write_error_count_o<=write_error_count_o+1'b1;
            end
            if(read_response_bad) begin
                error_status_o[1]<=1;
                if(read_error_count_o!=65535) read_error_count_o<=read_error_count_o+1'b1;
            end
            if(fifo_event) begin
                error_status_o[2]<=1;
                if(fifo_error_count_o!=65535) fifo_error_count_o<=fifo_error_count_o+1'b1;
            end
            if(write_timeout || read_timeout) begin
                error_status_o[3]<=1;reset_request_o<=1;
            end
            if(rd_state==R_DATA && axi_rvalid && !axi_rlast && read_beats>=C_BURST_LEN-1) begin
                // A slave which overruns ARLEN cannot be drained with a
                // bounded guarantee. Recover through the shared reset.
                error_status_o[5]<=1;reset_request_o<=1;
            end
            if(rs_w==W_IDLE && r_weof_pending &&
               (wr_bytes!=C_WR_FRAME_BYTES || !w_wfifo_empty)) error_status_o[4]<=1;
        end
    end
    assign frame_ready_o=have_frame && reader_started;
    assign video_error_o=write_fault || read_fault || reset_request_o;
    always @(posedge axi_clk or posedge axi_reset) begin
        if(axi_reset) begin
            rd_state<=R_IDLE;axi_arvalid<=0;araddr<=0;read_beats<=0;read_bank<=2;
            flush_pending<=1;reader_started<=0;read_fault<=0;r_rframe_inc<=0;rfifo_wenb<=0;rfifo_wdata<=0;
        end else begin
            r_rframe_inc<=0;rfifo_wenb<=0;
            if(r_rfifo_rst && !reset_prev) begin
                r_rframe_inc<=1;flush_pending<=1;reader_started<=have_frame;
            end
            if(read_response_bad || read_timeout || underflow_sync ||
               (rfifo_wenb && rfifo_full)) read_fault<=1;
            if(axi_arvalid && axi_arready) begin
                axi_arvalid<=0;rd_state<=R_DATA;read_beats<=0;
            end
            if(rd_state==R_DATA && axi_rvalid) begin
                if(!read_fault && !read_response_bad && !r_rfifo_rst &&
                   !flush_pending && !rfifo_full) begin
                    rfifo_wenb<=1;rfifo_wdata<=axi_rdata;
                end
                read_beats<=read_beats+1'b1;
                if(axi_rlast) begin rd_state<=R_IDLE;araddr<=araddr+C_ADDR_INC;end
            end
            if(rd_state==R_IDLE) begin
                if(flush_pending && !r_rfifo_rst) begin
                    // Retire the old burst before selecting the new bank. This
                    // also protects ARADDR when VSync arrives during an AR stall.
                    flush_pending<=0;araddr<=0;read_bank<=rc_rframe_index;read_fault<=0;
                end else if(!flush_pending && !r_rfifo_rst && !read_fault &&
                            reader_started && have_frame && !rfifo_wfull && araddr<C_RD_END_ADDR) begin
                    axi_arvalid<=1;rd_state<=R_ADDR;
                end
            end
        end
    end
endmodule
