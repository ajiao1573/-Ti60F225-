`include "src/camera_rgb_denoise.v"
`include "src/camera_rgb_smooth.v"
`include "src/video_thumbnail2.v"
`include "src/raw8_rgb_frame.v"
`include "src/camera_full_view.v"
`include "src/video_scale_3_2.v"
`include "src/camera_status_osd.v"
`include "src/video_status_osd.v"
`timescale 1ns/1ps
// Keep the Canny implementation reachable even when an already-open Efinity
// GUI saves an older project source list. Paths are relative to project root.
`include "src/canny/canny_rtl.vh"
`include "src/edge_display_width2.v"
`include "src/video_key_control.v"
`include "src/shape_detect.v"
`include "src/shape_stabilizer.v"
`include "src/shape_osd.v"

//`include "ddr3_controller.vh"


module example_top #(
 parameter ENABLE_MEDIAN=1,ENABLE_CANNY=1,ENABLE_COLOR_OVERLAY=1,
 parameter ENABLE_DDR_FRAME=1,ENABLE_2FRAME_COMP=1,FRAME_DEPTH=8,
 parameter SOBEL_MAX_ENABLE=1,EDGE_DISPLAY_THICK=0
)( 
	////////////////////////////////////////////////////////////////
	//	External Clock & Reset
	//input 			nrst, 			//	Button K2
	input 			clk_24m,			//	24MHz Crystal
	input 			clk_25m,			//	25MHz Crystal 
	input 	[1:0]	key_data,			//	Board keys, active low
	
	
	////////////////////////////////////////////////////////////////
	//	System Clock
	output 			sys_pll_rstn_o, 		
	
	input 			clk_sys,			//	Sys PLL 96MHz 
	input 			clk_pixel,			//	Sys PLL 74.25MHz
	input 			clk_pixel_2x,		//	Sys PLL 148.5MHz
	input 			clk_pixel_10x,		//	Sys PLL 742.5MHz
	
	input 			sys_pll_lock,		//	Sys PLL Lock
	
	////////////////////////////////////////////////////////////////
	//	MIPI-DSI Clock & Reset
	output 			dsi_pll_rstn_o,
	
	input 			dsi_refclk_i,		//	48MHz Reference Clock (for DSI PLL)
	input 			dsi_byteclk_i,		//	DSI Byte Clock (1X)
	input 			dsi_serclk_i,		//	DSI Serial Clock (4X 45)
	input 			dsi_txcclk_i,		//	DSI Serial Clock (4X 135)
	
	input 			dsi_pll_lock,
	
	////////////////////////////////////////////////////////////////
	//	DDR Clock
	output 			ddr_pll_rstn_o, 
	
	input 			tdqss_clk,			
	input 			core_clk,			//	DDR PLL 200MHz
	input 			tac_clk,			
	input 			twd_clk,			
	
	input 			ddr_pll_lock,		//	DDR PLL Lock
	
	////////////////////////////////////////////////////////////////
	//	DDR PLL Phase Shift Interface
	output 	[2:0] 	shift,
	output 	[4:0] 	shift_sel,
	output 			shift_ena,
	
	
	
	////////////////////////////////////////////////////////////////
	//	LVDS Clock
	output 			lvds_pll_rstn_o, 
	
	input 			clk_lvds_1x, 
	input 			clk_lvds_7x, 
	input 			clk_27m, 			// Legacy port name: video PLL feedback, now 99 MHz
	input 			clk_54m, 			// Legacy port name: video PLL reference, now 99 MHz
	
	input 			lvds_pll_lock, 
	
	
	
	////////////////////////////////////////////////////////////////
	//	DDR Interface Ports
	output 	[15:0] 	addr,
	output 	[2:0] 	ba,
	output 			we,
	output 			reset,
	output 			ras,
	output 			cas,
	output 			odt,
	output 			cke,
	output 			cs,
	
	//	DQ I/O
	input 	[15:0] 	i_dq_hi,
	input 	[15:0] 	i_dq_lo,
	
	output 	[15:0] 	o_dq_hi,
	output 	[15:0] 	o_dq_lo,
	output 	[15:0] 	o_dq_oe,
	
	//	DM O
	output 	[1:0] 	o_dm_hi,
	output 	[1:0] 	o_dm_lo,
	
	//	DQS I/O
	input 	[1:0] 	i_dqs_hi,
	input 	[1:0] 	i_dqs_lo,
	
	input 	[1:0] 	i_dqs_n_hi,
	input 	[1:0] 	i_dqs_n_lo,
	
	output 	[1:0] 	o_dqs_hi,
	output 	[1:0] 	o_dqs_lo,
	
	output 	[1:0] 	o_dqs_n_hi,
	output 	[1:0] 	o_dqs_n_lo,
	
	output 	[1:0] 	o_dqs_oe,
	output 	[1:0] 	o_dqs_n_oe,
	
	//	CK
	output 			clk_p_hi, 
	output 			clk_p_lo, 
	output 			clk_n_hi, 
	output 			clk_n_lo, 
	
	
	
	////////////////////////////////////////////////////////////////
	//	MIPI-CSI Ctl / I2C
	output 			csi_ctl0_o,
	output 			csi_ctl0_oe,
	input 			csi_ctl0_i,
	
	output 			csi_ctl1_o,
	output 			csi_ctl1_oe,
	input 			csi_ctl1_i,
	
	output 			csi_scl_o,
	output 			csi_scl_oe,
	input 			csi_scl_i,
	
	output 			csi_sda_o,
	output 			csi_sda_oe,
	input 			csi_sda_i,
	
	//	MIPI-CSI RXC 
	input 			csi_rxc_lp_p_i,
	input 			csi_rxc_lp_n_i,
	output 			csi_rxc_hs_en_o,
	output 			csi_rxc_hs_term_en_o,
	input 			csi_rxc_i,
	
	//	MIPI-CSI RXD0
	output 			csi_rxd0_rst_o,
	output 			csi_rxd0_hs_en_o,
	output 			csi_rxd0_hs_term_en_o,
	
	input 			csi_rxd0_lp_p_i,
	input 			csi_rxd0_lp_n_i,
	input 	[7:0] 	csi_rxd0_hs_i,
	
	//	MIPI-CSI RXD1
	output 			csi_rxd1_rst_o,
	output 			csi_rxd1_hs_en_o,
	output 			csi_rxd1_hs_term_en_o,
	
	input 			csi_rxd1_lp_n_i,
	input 			csi_rxd1_lp_p_i,
	input 	[7:0] 	csi_rxd1_hs_i,
	
	//	MIPI-CSI RXD2
	output 			csi_rxd2_rst_o,
	output 			csi_rxd2_hs_en_o,
	output 			csi_rxd2_hs_term_en_o,
	
	input 			csi_rxd2_lp_p_i,
	input 			csi_rxd2_lp_n_i,
	input 	[7:0] 	csi_rxd2_hs_i,
	
	//	MIPI-CSI RXD3
	output 			csi_rxd3_rst_o,
	output 			csi_rxd3_hs_en_o,
	output 			csi_rxd3_hs_term_en_o,
	
	input 			csi_rxd3_lp_p_i,
	input 			csi_rxd3_lp_n_i,
	input 	[7:0] 	csi_rxd3_hs_i,
	
	//output 			csi_rxd0_fifo_rd_o, 
	//input 			csi_rxd0_fifo_empty_i, 
	//output 			csi_rxd1_fifo_rd_o, 
	//input 			csi_rxd1_fifo_empty_i, 
	//output 			csi_rxd2_fifo_rd_o, 
	//input 			csi_rxd2_fifo_empty_i, 
	//output 			csi_rxd3_fifo_rd_o, 
	//input 			csi_rxd3_fifo_empty_i, 
	
	
	
	////////////////////////////////////////////////////////////////
	//	DSI PWM & Reset Control 
	output 			dsi_pwm_o,			//	MIPI-DSI LCD PWM
	output 			dsi_resetn_o,		//	MIPI-DSI LCD Reset
	
	//	MIPI-DSI TXC / TXD
	output 			dsi_txc_rst_o,
	output 			dsi_txc_lp_p_oe,
	output 			dsi_txc_lp_p_o,
	output 			dsi_txc_lp_n_oe,
	output 			dsi_txc_lp_n_o,
	output 			dsi_txc_hs_oe,
	output 	[7:0] 	dsi_txc_hs_o,
	
	output 			dsi_txd0_rst_o,
	output 			dsi_txd0_hs_oe,
	output 	[7:0] 	dsi_txd0_hs_o,
	output 			dsi_txd0_lp_p_oe,
	output 			dsi_txd0_lp_p_o,
	output 			dsi_txd0_lp_n_oe,
	output 			dsi_txd0_lp_n_o,
	
	output 			dsi_txd1_rst_o,
	output 			dsi_txd1_lp_p_oe,
	output 			dsi_txd1_lp_p_o,
	output 			dsi_txd1_lp_n_oe,
	output 			dsi_txd1_lp_n_o,
	output 			dsi_txd1_hs_oe,
	output 	[7:0] 	dsi_txd1_hs_o,
	
	output 			dsi_txd2_rst_o,
	output 			dsi_txd2_lp_p_oe,
	output 			dsi_txd2_lp_p_o,
	output 			dsi_txd2_lp_n_oe,
	output 			dsi_txd2_lp_n_o,
	output 			dsi_txd2_hs_oe,
	output 	[7:0] 	dsi_txd2_hs_o,
	
	output 			dsi_txd3_rst_o,
	output 			dsi_txd3_lp_p_oe,
	output 			dsi_txd3_lp_p_o,
	output 			dsi_txd3_lp_n_oe,
	output 			dsi_txd3_lp_n_o,
	output 			dsi_txd3_hs_oe,
	output 	[7:0] 	dsi_txd3_hs_o,
	
	input 			dsi_txd0_lp_p_i,
	input 			dsi_txd0_lp_n_i,
	input 			dsi_txd1_lp_p_i,
	input 			dsi_txd1_lp_n_i,
	input 			dsi_txd2_lp_p_i,
	input 			dsi_txd2_lp_n_i,
	input 			dsi_txd3_lp_p_i,
	input 			dsi_txd3_lp_n_i,
	
	
	////////////////////////////////////////////////////////////////
	//	UART Interface
	input 		 	uart_rx_i,			//	Support 460800-8-N-1. 
	output 		 	uart_tx_o, 
	
	
	output 	[5:0] 	led_o,			//	
	
	
	////////////////////////////////////////////////////////////////
	//	CMOS Sensor
	output 			cmos_sclk,
	input 			cmos_sdat_IN,
	output 			cmos_sdat_OUT,
	output 			cmos_sdat_OE,
	
	//	CMOS Interface
	input 			cmos_pclk,
	input 			cmos_vsync,
	input 			cmos_href,
	input 	[7:0] 	cmos_data,
	// Board control ports: exact interface and idle values from the supplied
    // 02-1_Ti60_OV5640_LCD-HDMI_1080P60 reference. They are not named RESET/PWDN.
    output cmos_ctl1_o, output cmos_ctl1_oe, input cmos_ctl1_i,
    output cmos_ctl2_o, output cmos_ctl2_oe, input cmos_ctl2_i,
    output cmos_ctl3_o, output cmos_ctl3_oe, input cmos_ctl3_i,
	// output 			cmos_ctl2,
	// output 			cmos_ctl3,
	
	
	////////////////////////////////////////////////////////////////
	//	HDMI Interface
	output 			hdmi_txc_oe,
	output 			hdmi_txd0_oe,
	output 			hdmi_txd1_oe,
	output 			hdmi_txd2_oe,
	
	output 			hdmi_txc_rst_o,
	output 			hdmi_txd0_rst_o,
	output 			hdmi_txd1_rst_o,
	output 			hdmi_txd2_rst_o,
	
	output 	[9:0] 	hdmi_txc_o,
	output 	[9:0] 	hdmi_txd0_o,
	output 	[9:0] 	hdmi_txd1_o,
	output 	[9:0] 	hdmi_txd2_o,
	
	
	////////////////////////////////////////////////////////////////
	//	LVDS Interface
	output 			lvds_txc_oe,
	output 	[6:0] 	lvds_txc_o,
	output 			lvds_txc_rst_o,
	
	output 			lvds_txd0_oe,
	output 	[6:0] 	lvds_txd0_o,
	output 			lvds_txd0_rst_o,
	
	output 			lvds_txd1_oe,
	output 	[6:0] 	lvds_txd1_o,
	output 			lvds_txd1_rst_o,
	
	output 			lvds_txd2_oe,
	output 	[6:0] 	lvds_txd2_o,
	output 			lvds_txd2_rst_o,
	
	output 			lvds_txd3_oe,
	output 	[6:0] 	lvds_txd3_o,
	output 			lvds_txd3_rst_o,
	
	
	////////////////////////////////////////////////////////////////
	//	RGB LCD 5Inch 800x480
	output 			lcd_tp_sda_o,		//	TP SDA
	output 			lcd_tp_sda_oe,
	input 			lcd_tp_sda_i,
	
	output 			lcd_tp_scl_o,		//	TP SCL
	output 			lcd_tp_scl_oe,
	input 			lcd_tp_scl_i,
	
	output 			lcd_tp_int_o,		//	TP INT
	output 			lcd_tp_int_oe,
	input 			lcd_tp_int_i,
	
	output 			lcd_tp_rst_o,		//	TP RST
	
	output 			lcd_pwm_o,			//	Backlight
	output 			lcd_blen_o,
	
	//output 			lcd_pclk_o,			//	PCLK & SCK Mux
	output 			lcd_vs_o,			//	VS & SSN Mux. Fixed to 1. Use DE-Only mode. 
	output 			lcd_hs_o,			//	HS. Fixed to 1. Use DE-Only mode. 
	// LCD_DE/LCD_PCLK pins are reused by the two on-board keys in this HDMI build.

	output 	[7:0] 	lcd_b7_0_o,			//	B7:B0. 
	output 	[7:0] 	lcd_g7_0_o,			//	G7:G0. Must output 8'hFF when access SPI. 
	output 	[7:0] 	lcd_r7_0_o,			//	R7:R0. 
	
	output 	[7:0] 	lcd_b7_0_oe,		//	B7:B0. 
	output 	[7:0] 	lcd_g7_0_oe,		//	G7:G0. Must output 8'hFF when access SPI. 
	output 	[7:0] 	lcd_r7_0_oe,		//	R7:R0. 

	input 	[7:0] 	lcd_b7_0_i,			//	B7:B0. 
	input 	[7:0] 	lcd_g7_0_i,			//	G7:G0. Must output 8'hFF when access SPI. 
	input 	[7:0] 	lcd_r7_0_i,			//	R7:R0. 
	
	//	SPI Pins
	output 			spi_sck_o, 
	output 			spi_ssn_o 			
);
	
	wire 			csi_rxd0_fifo_rd_o; 
	wire 			csi_rxd0_fifo_empty_i = 0;  
	wire 			csi_rxd1_fifo_rd_o;  
	wire 			csi_rxd1_fifo_empty_i = 0;  
	wire 			csi_rxd2_fifo_rd_o;  
	wire 			csi_rxd2_fifo_empty_i = 0;  
	wire 			csi_rxd3_fifo_rd_o;  
	wire 			csi_rxd3_fifo_empty_i = 0;  
	
	
	parameter 	SIM_DATA 	= 0; 
	
	//	Hardware Configuration
	assign clk_p_hi = 1'b0;	//	DDR3 Clock requires 180 degree shifted. 
	assign clk_p_lo = 1'b1;
	assign clk_n_hi = 1'b1;
	assign clk_n_lo = 1'b0; 
	
	// Reference board control wiring: all three outputs enabled and held low.
    // Sensor initialization uses SCCB software reset; no guessed RESETB/PWDN pins.
    assign cmos_ctl1_o=1'b0, cmos_ctl1_oe=1'b1;
    assign cmos_ctl2_o=1'b0, cmos_ctl2_oe=1'b1;
    assign cmos_ctl3_o=1'b0, cmos_ctl3_oe=1'b1;

    //	System Clock Tree Control
	assign sys_pll_rstn_o = 1'b1; 	//	nrst; 	//	Reset whole system when nrst (K2) is pressed. 
	
	assign dsi_pll_rstn_o = sys_pll_lock; 
	assign ddr_pll_rstn_o = sys_pll_lock; 
	assign lvds_pll_rstn_o = sys_pll_lock; 
	
	// Release each clock domain from reset only after its own PLL chain locks.
	// HDMI uses lvds_pll (99 MHz reference); camera XCLK uses dsi_pll CLKOUT4.
	wire 			w_sys_ddr_lock = sys_pll_lock && ddr_pll_lock;
	wire 			w_dsi_lock = sys_pll_lock && dsi_pll_lock;
	wire 			w_lvds_lock = sys_pll_lock && lvds_pll_lock;
	
	//	Synchronize System Resets. 
	reg 			rstn_sys = 0, rstn_pixel = 0; 
	wire 			rst_sys = ~rstn_sys, rst_pixel = ~rstn_pixel; 
	
	reg 			rstn_dsi_refclk = 0, rstn_dsi_byteclk = 0; 
	wire 			rst_dsi_refclk = ~rstn_dsi_refclk, rst_dsi_byteclk = ~rstn_dsi_byteclk; 
	
	reg 			rstn_lvds_1x = 0; 
	wire 			rst_lvds_1x = ~rstn_lvds_1x; 
	
	reg 			rstn_27m = 0, rstn_54m = 0; 
	wire 			rst_27m = ~rstn_27m, rst_54m = ~rstn_54m; 
	
	//	Clock Gen
	always @(posedge clk_27m or negedge w_lvds_lock) begin if(~w_lvds_lock) rstn_27m <= 0; else rstn_27m <= 1; end
	always @(posedge clk_54m or negedge w_lvds_lock) begin if(~w_lvds_lock) rstn_54m <= 0; else rstn_54m <= 1; end
	always @(posedge clk_sys or negedge w_sys_ddr_lock) begin if(~w_sys_ddr_lock) rstn_sys <= 0; else rstn_sys <= 1; end
	always @(posedge clk_pixel or negedge w_lvds_lock) begin if(~w_lvds_lock) rstn_pixel <= 0; else rstn_pixel <= 1; end
	always @(posedge dsi_refclk_i or negedge w_dsi_lock) begin if(~w_dsi_lock) rstn_dsi_refclk <= 0; else rstn_dsi_refclk <= 1; end
	always @(posedge dsi_byteclk_i or negedge w_dsi_lock) begin if(~w_dsi_lock) rstn_dsi_byteclk <= 0; else rstn_dsi_byteclk <= 1; end
	always @(posedge clk_lvds_1x or negedge w_lvds_lock) begin if(~w_lvds_lock) rstn_lvds_1x <= 0; else rstn_lvds_1x <= 1; end
	
	
	localparam 	CLOCK_MAIN 	= 96000000; 	//	System clock using 96MHz. 
	
	
	
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	//	Flash Burner Control
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	wire 			w_ustick, w_mstick; 
	
	wire  [7:0] 	w_dev_index_o;  
	wire  [7:0] 	w_dev_cmd_o;  
	wire  [31:0] 	w_dev_wdata_o;  
	wire  		w_dev_wvalid_o;  
	wire  		w_dev_rvalid_o;  
	wire 	[31:0] 	w_dev_rdata_i;  
	
	wire 			w_spi_ssn_o, w_spi_sck_o; 
	wire 	[3:0] 	w_spi_data_o, w_spi_data_oe; 
	wire 	[3:0] 	w_spi_data_i; 
	
	//	Flash Control
	reg 			r_flash_en = 0; 		//	0x00:0x00 Enable Flash
	
	always @(posedge clk_sys) begin
		r_flash_en <= (w_dev_wvalid_o && (w_dev_index_o == 8'h00) && (w_dev_cmd_o == 8'h00)) ? w_dev_wdata_o : r_flash_en; 
	end
	
	
	
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	//	LCD Data Mux
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	wire 	[7:0] 	w_lcd_b_o, w_lcd_g_o, w_lcd_r_o; 
	
	assign lcd_b7_0_o = r_flash_en ? {4'b0, w_spi_data_o[3:2], 2'b0} : w_lcd_b_o; 
	assign lcd_g7_0_o = r_flash_en ? {6'h0, w_spi_data_o[1:0]} : w_lcd_g_o; 
	assign lcd_r7_0_o = r_flash_en ? {8'h00} : w_lcd_r_o; 
	
	assign lcd_b7_0_oe = r_flash_en ? {4'b0, w_spi_data_oe[3:2], 2'b0} : 8'hFF; 
	assign lcd_g7_0_oe = r_flash_en ? {6'h0, w_spi_data_oe[1:0]} : 8'hFF; 
	assign lcd_r7_0_oe = r_flash_en ? {8'h00} : 8'hFF; 
	
	assign spi_sck_o = w_spi_sck_o; 
	assign spi_ssn_o = w_spi_ssn_o; 
	assign w_spi_data_i = {lcd_b7_0_i[3:2], lcd_g7_0_i[1:0]}; 
	
	
	
	
	
	
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	//	DDR3 Controller
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	wire			w_ddr3_ui_clk = clk_sys;
	wire			w_ddr3_ui_rst = rst_sys;
	wire			w_ddr3_ui_areset = rst_sys;
	wire			w_ddr3_ui_aresetn = rstn_sys;
	

	//	General AXI Interface 
	wire	[3:0] 	w_ddr3_awid;
	wire	[31:0]	w_ddr3_awaddr;
	wire	[7:0]		w_ddr3_awlen;
	wire			w_ddr3_awvalid;
	wire			w_ddr3_awready;
	
	wire 	[3:0]  	w_ddr3_wid;
	wire 	[127:0] 	w_ddr3_wdata;
	wire 	[15:0]	w_ddr3_wstrb;
	wire			w_ddr3_wlast;
	wire			w_ddr3_wvalid;
	wire			w_ddr3_wready;
	
	wire 	[3:0] 	w_ddr3_bid;
	wire 	[1:0] 	w_ddr3_bresp;
	wire			w_ddr3_bvalid;
	wire			w_ddr3_bready;
	
	wire	[3:0] 	w_ddr3_arid;
	wire	[31:0]	w_ddr3_araddr;
	wire	[7:0]		w_ddr3_arlen;
	wire			w_ddr3_arvalid;
	wire			w_ddr3_arready;
	
	wire 	[3:0] 	w_ddr3_rid;
	wire 	[127:0] 	w_ddr3_rdata;
	wire			w_ddr3_rlast;
	wire			w_ddr3_rvalid;
	wire			w_ddr3_rready;
	wire 	[1:0] 	w_ddr3_rresp;
	
	
	//	AXI Interface Request
	wire 	[3:0] 	w_ddr3_aid;
	wire 	[31:0] 	w_ddr3_aaddr;
	wire 	[7:0]  	w_ddr3_alen;
	wire 	[2:0]  	w_ddr3_asize;
	wire 	[1:0]  	w_ddr3_aburst;
	wire 	[1:0]  	w_ddr3_alock;
	wire			w_ddr3_avalid;
	wire			w_ddr3_aready;
	wire			w_ddr3_atype;
	
	wire 			w_ddr3_cal_done, w_ddr3_cal_pass; 
	
	//	Do not issue DDR read / write when ~cal_done. 
	reg 			r_ddr_unlock = 0; 
	always @(posedge w_ddr3_ui_clk or negedge w_ddr3_ui_aresetn) begin
		if(~w_ddr3_ui_aresetn)
			r_ddr_unlock <= 0; 
		else
			r_ddr_unlock <= w_ddr3_cal_done; 
	end
	
	DdrCtrl ddr3_ctl_axi (	
		.core_clk		(core_clk),
		.tac_clk		(tac_clk),
		.twd_clk		(twd_clk),	
		.tdqss_clk		(tdqss_clk),
		
		.reset		(reset),
		.cs			(cs),
		.ras			(ras),
		.cas			(cas),
		.we			(we),
		.cke			(cke),    
		.addr			(addr),
		.ba			(ba),
		.odt			(odt),
		
		.o_dm_hi		(o_dm_hi),
		.o_dm_lo		(o_dm_lo),
		
		.i_dq_hi		(i_dq_hi),
		.i_dq_lo		(i_dq_lo),
		.o_dq_hi		(o_dq_hi),
		.o_dq_lo		(o_dq_lo),
		.o_dq_oe		(o_dq_oe),
		
		.i_dqs_hi		(i_dqs_hi),
		.i_dqs_lo		(i_dqs_lo),
		.i_dqs_n_hi		(i_dqs_n_hi),
		.i_dqs_n_lo		(i_dqs_n_lo),
		.o_dqs_hi		(o_dqs_hi),
		.o_dqs_lo		(o_dqs_lo),
		.o_dqs_n_hi		(o_dqs_n_hi),
		.o_dqs_n_lo		(o_dqs_n_lo),
		.o_dqs_oe		(o_dqs_oe),
		.o_dqs_n_oe		(o_dqs_n_oe),
		
		.clk			(w_ddr3_ui_clk),
		.reset_n		(w_ddr3_ui_aresetn),
		
		.axi_avalid		(w_ddr3_avalid && r_ddr_unlock),	//	Enable command only when unlocked. 
		.axi_aready		(w_ddr3_aready),
		.axi_aaddr		(w_ddr3_aaddr),
		.axi_aid		(w_ddr3_aid),
		.axi_alen		(w_ddr3_alen),
		.axi_asize		(w_ddr3_asize),
		.axi_aburst		(w_ddr3_aburst),
		.axi_alock		(w_ddr3_alock),
		.axi_atype		(w_ddr3_atype),
		
		.axi_wid		(w_ddr3_wid),
		.axi_wvalid		(w_ddr3_wvalid),
		.axi_wready		(w_ddr3_wready),
		.axi_wdata		(w_ddr3_wdata),
		.axi_wstrb		(w_ddr3_wstrb),
		.axi_wlast		(w_ddr3_wlast),
		
		.axi_bvalid		(w_ddr3_bvalid),
		.axi_bready		(w_ddr3_bready),
		.axi_bid		(w_ddr3_bid),
		.axi_bresp		(w_ddr3_bresp),
		
		.axi_rvalid		(w_ddr3_rvalid),
		.axi_rready		(w_ddr3_rready),
		.axi_rdata		(w_ddr3_rdata),
		.axi_rid		(w_ddr3_rid),
		.axi_rresp		(w_ddr3_rresp),
		.axi_rlast		(w_ddr3_rlast),
		
		.shift		(shift),
		.shift_sel		(),
		.shift_ena		(shift_ena),
		
		.cal_ena		(1'b1),
		.cal_done		(w_ddr3_cal_done),
		.cal_pass		(w_ddr3_cal_pass)
	);
	
	assign w_ddr3_bready = 1'b1; 
	assign shift_sel = 5'b00100; 		//	ddr_tac_clk always use PLLOUT[2]. 
	
	
	AXI4_AWARMux #(.AID_LEN(4), .AADDR_LEN(32)) axi4_awar_mux (
		.aclk_i			(w_ddr3_ui_clk), 
		.arst_i			(w_ddr3_ui_rst), 
		
		.awid_i			(w_ddr3_awid),
		.awaddr_i			(w_ddr3_awaddr),
		.awlen_i			(w_ddr3_awlen),
		.awvalid_i			(w_ddr3_awvalid),
		.awready_o			(w_ddr3_awready),
		
		.arid_i			(w_ddr3_arid),
		.araddr_i			(w_ddr3_araddr),
		.arlen_i			(w_ddr3_arlen),
		.arvalid_i			(w_ddr3_arvalid),
		.arready_o			(w_ddr3_arready),
		
		.aid_o			(w_ddr3_aid),
		.aaddr_o			(w_ddr3_aaddr),
		.alen_o			(w_ddr3_alen),
		.atype_o			(w_ddr3_atype),
		.avalid_o			(w_ddr3_avalid),
		.aready_i			(w_ddr3_aready)
	);
	
	assign w_ddr3_asize = 4; 		//	Fixed 128 bits (16 bytes, size = 4)
	assign w_ddr3_aburst = 1; 
	assign w_ddr3_alock = 0; 
	
	//assign led_o[1:0] = {w_ddr3_cal_pass, w_ddr3_cal_done}; 
	
	
	
	
	
	
	
	
	
	// ////////////////////////////////////////////////////////////////
	// //	I2C Config (SC130GS)
	
	// //  i2c timing controller module of 16Bit
	// wire            [ 7:0]          sc130_i2c_config_index;
	// wire            [23:0]          sc130_i2c_config_data;
	// wire            [ 7:0]          sc130_i2c_config_size;
	// wire                            sc130_i2c_config_done;
	
	// i2c_timing_ctrl_16bit
	// #(
	//     .CLK_FREQ           (CLOCK_MAIN),                              //  100 MHz
	//     .I2C_FREQ           (50_000    )                               //  10 KHz(<= 400KHz)
	// ) u_i2c_timing_ctrl_16bit (
	//     //  global clock
	//     .clk                (clk_sys                 ),                          //  96MHz
	//     .rst_n              (rstn_sys                ),                          //  system reset

	//     //  i2c interface
	//     .i2c_sclk           (csi_scl_o               ),                          //  i2c clock
	//     .i2c_sdat_IN        (csi_sda_i               ),
	//     .i2c_sdat_OUT       (csi_sda_o               ),
	//     .i2c_sdat_OE        (csi_sda_oe              ),

	//     //  i2c config data
	//     .i2c_config_index   (sc130_i2c_config_index        ),                          //  i2c config reg index, read 2 reg and write xx reg
	//     .i2c_config_data    ({8'h60, sc130_i2c_config_data}),                     //  i2c config data
	//     .i2c_config_size    (sc130_i2c_config_size         ),                          //  i2c config data counte
	//     .i2c_config_done    (sc130_i2c_config_done         )                          //  i2c config timing complete
	// );
	// assign csi_scl_oe = 1; 

	// //  I2C Configure Data of SC130GS
	// I2C_SC130GS_12801024_4Lanes_Config u_I2C_SC130GS_12801024_4Lanes_Config 
	// (
	//     .LUT_INDEX  (sc130_i2c_config_index   ),
	//     .LUT_DATA   (sc130_i2c_config_data    ),
	//     .LUT_SIZE   (sc130_i2c_config_size    )
	// );
	
// OV5640: 24 MHz reference, 960x720 RAW8 nominal60, 50 kHz SCCB.
// The init sequencer retains startup waits; external controls follow the board
// reference constants above. Hardware RESETB/PWDN outputs are intentionally open.
    wire i2c_config_done,ov5640_config_failed;
    wire camera_ae_locked,camera_ae_failed;
    wire [15:0] ov5640_chip_id;
    wire [8:0] ov5640_config_index;
    // Wait for the 24 MHz camera reference; assert reset asynchronously,
    // release it through two system-clock stages.
    wire camera_clock_ready = rstn_sys && dsi_pll_lock;
    reg [1:0] camera_reset_sync=0;
    always @(posedge clk_sys or negedge camera_clock_ready)
     if(!camera_clock_ready) camera_reset_sync<=0;
     else camera_reset_sync<={camera_reset_sync[0],1'b1};
    ov5640_init #(.CLOCK_HZ(CLOCK_MAIN),.BUS_HZ(50000),.LOCK_EXPOSURE(0)) u_ov5640_init(
     .clk(clk_sys),.rst_n(camera_reset_sync[1]),.sda_i(cmos_sdat_IN),
     .scl(cmos_sclk),.sda_o(cmos_sdat_OUT),.sda_oe(cmos_sdat_OE),
     .pwdn(),.resetb(),.configured(i2c_config_done),
     .failed(ov5640_config_failed),.chip_id(ov5640_chip_id),.config_index(ov5640_config_index),
     .exposure_locked(camera_ae_locked),.exposure_lock_failed(camera_ae_failed));
	// ////////////////////////////////////////////////////////////////
	// //	I2C Config (AR0135)
	
	// //  i2c timing controller module of 16Bit
	// wire            [ 7:0]          ar0135_i2c_config_index;
	// wire            [31:0]          ar0135_i2c_config_data;
	// wire            [ 7:0]          ar0135_i2c_config_size;
	// wire                            ar0135_i2c_config_done;
	// wire            [15:0]          ar0135_i2c_rdata;                              //  i2c register data

	// i2c_timing_ctrl_reg16_dat16
	// #(
	//     .SIMU_EN            (0              ),
	//     .I2C_READ_EN        (1              ),                              //  Enable I2C Register read
	//     .CLK_FREQ           (CLOCK_MAIN     ),                              //  120 MHz
	//     .I2C_FREQ           (50_000         )                               //  10 KHz(<= 400KHz)
	// )
	// u_i2c_timing_ctrl_16reg_16bit
	// (
	//     //global clock
	//     .clk                (clk_sys                 ),                          //  96MHz
	//     .rst_n              (rstn_sys                ),                          //  system reset

	//     //i2c interface
	//     .i2c_sclk           (cmos_sclk                  ),                  //  i2c clock
	// 	.i2c_sdat_o 	(cmos_sdat_OUT), 
	// 	.i2c_sdat_oe	(cmos_sdat_OE), 
	// 	.i2c_sdat_i 	(cmos_sdat_IN), 
		
	//     //i2c config data
	//     .i2c_config_index   (ar0135_i2c_config_index           ),                  //  i2c config reg index, read 2 reg and write xx reg
	//     .i2c_config_data    ({8'h20, ar0135_i2c_config_data}   ),                  //  i2c config data
	//     .i2c_config_size    (ar0135_i2c_config_size            ),                  //  i2c config data counte
	//     .i2c_config_done    (ar0135_i2c_config_done            ),                  //  i2c config timing complete
	//     .i2c_rdata          (ar0135_i2c_rdata                  )                   //  i2c register data while read i2c slave
	// );
	
	// //----------------------------------------------------------------------
	// //  I2C Configure Data of AR0135
	// I2C_AR0135_1280720_Config u_I2C_AR0135_1280720_Config
	// (
	//     .LUT_INDEX  (ar0135_i2c_config_index   ),
	//     .LUT_DATA   (ar0135_i2c_config_data    ),
	//     .LUT_SIZE   (ar0135_i2c_config_size    )
	// );
	
	
		
	//	CMOS Interface
	//input 			cmos_pclk,
	//input 			cmos_vsync,
	//input 			cmos_href,
	//input 	[7:0] 	cmos_data,
	//input 			cmos_ctl1,
	//output 			cmos_ctl2,
	//output 			cmos_ctl3,

	
	//	Output LED
	reg 	[3:0]		r_cmos_fv_o = 0; 
	reg 	[1:0] 	r_cmos_rx_vsync0_in = 0; 
	always @(posedge cmos_pclk) begin
		r_cmos_rx_vsync0_in <= {r_cmos_rx_vsync0_in, cmos_vsync}; 
		r_cmos_fv_o <= r_cmos_fv_o + ((r_cmos_rx_vsync0_in == 2'b01) ? 1 : 0); 
	end
	assign led_o[5] = r_cmos_fv_o[3]; 
	
	
	
	
	
	
	
	
	////////////////////////////////////////////////////////////////
	//	System Control. Can be removed for public. 
	
	localparam 	CLK_FREQ 	= 96_000_000; 	//	clk_sys is 96MHz. 
	localparam 	BAUD_RATE 	= 460_800; 		//	Use 460800-8-N-1. 
	
	
	//	SFR I/O Interface
	wire 	[7:0] 	w_sfr_addr_o; 	//	SFR Address (0xFF00 ~ 0xFFFF). 00:Power; 40~5F:Stream0; 60~7F:Stream1. 
	wire 	[7:0] 	w_sfr_wdata_o; 	//	SFR Write Data. 
	wire 			w_sfr_we_o; 		//	SFR WE. 
	reg 	[7:0] 	w_sfr_rdata_i; 	//	Must be valid after sfr_rd_o. 
	wire 			w_sfr_rd_o; 		//	SFR RD. 
	
	
	//	System Control Registers
	reg 			r_dsi_tx_rstn = 0; 	//	DSI TX Reset
	reg 	[7:0] 	r_dsi_pwm = 64; 		//	[6:0]PWM, [7]Pol
	reg 			r_dsi_resetn_o = 0; 	//	DSI Panel Reset
	reg 			r_dsi_data_rstn = 0; 	//	DSI TX Reset
	
	reg 	[3:0] 	r_dsi_lp_p_ovr = 0; 	
	reg 	[3:0] 	r_dsi_lp_n_ovr = 0; 	
	
	
	
	//	AXI-Lite Interface Bridge
	localparam 	CSI_AXILITE_ID 	= 0; 				//	Select DSI_TX when r_axi_sel = DSI_AXILITE_ID. 
	localparam 	DSI_AXILITE_ID 	= 1; 				//	Select DSI_TX when r_axi_sel = DSI_AXILITE_ID. 
	
	reg 	[7:0] 	r_axi_addr = 8'h18; 		//	0xE0 (RW)
	reg 	[31:0] 	r_axi_wdata = 32'h0000000A; 	//	0xE1~0xE4 (RW)
	wire 	[31:0] 	w_axi_rdata; 			//	0xE5~0xE8 (RO)
	reg 	[0:0] 	r_axi_sel = 1; 			//	0xE9[7:2] (RW)
	reg 			r_axi_r1w0 = 0; 			//	0xE9[1] (RW)
	reg 			r_axi_req = 0; 			//	0xE9[0] (WO, Single Cycle)
	reg 			r_axi_req_o = 0; 			//	Delayed of r_axi_req. 
	
	
	//	Buffered AXI Read Data
	reg 	[31:0] 	r_axi_rdata = 0; 		//	Use state machine
	reg 			r_axi_idle = 0; 		//	AXI Idle 
	
	reg 	[3:0] 	rs_axilite = 0; 		//	AXI Access
	wire 	[3:0] 	ws_axilite_idle = 0; 		
	wire 	[3:0] 	ws_axilite_write = 1; 
	wire 	[3:0] 	ws_axilite_read = 2; 
	wire 	[3:0] 	ws_axilite_endread = 3; 
	
	reg 			r_axi_awvalid = 0, r_axi_wvalid = 0, r_axi_arvalid = 0; 
	wire 			w_axi_awready, w_axi_wready, w_axi_arready, w_axi_rvalid; 
	
	
	reg 	[3:0] 	rc_axi_init = 0; 

	always @(posedge clk_sys or posedge rst_sys) begin
		if(rst_sys) begin
			r_dsi_tx_rstn <= 0; 
			r_dsi_pwm <= 64; 
			r_axi_req <= 0; 
			r_dsi_resetn_o <= 0; 
			r_dsi_data_rstn <= 0; 
			
			rs_axilite <= 0; 
			r_axi_awvalid <= 0; 
			r_axi_wvalid <= 0;
			r_axi_arvalid <= 0; 
			
			r_dsi_lp_p_ovr <= 0; 
			r_dsi_lp_n_ovr <= 0; 
			
			rc_axi_init <= 0; 
			r_axi_idle <= 0; 
			
		end else begin
			r_dsi_tx_rstn <= 1; 
			r_dsi_resetn_o <= 1; 
			r_dsi_data_rstn <= 1; 
			
		end
	end
	
	assign dsi_resetn_o = r_dsi_resetn_o; 
	
	assign csi_ctl0_oe = 0; 
	assign csi_ctl1_oe = 0; 
	
	
	PWMLite dsi_pwm (		//	#(.ENABLE_TICK(0), .PWM_BITS(7)) 
		.clk_i			(clk_sys),
		.rst_i			(rst_sys),
		.pwm_i			(r_dsi_pwm[6:0]),
		.pol_i			(r_dsi_pwm[7]), 
		.pwm_o			(dsi_pwm_o)
	);






	////////////////////////////////////////////////////////////////
	//	MIPI CSI RX
	
	//	The CSI RXC shall not be inverted. Data can be inverted with swapped LP data and flipped HS data. 
	localparam 	CSI_RXD_INV 	= 4'b1111; 
	localparam 	CSI_DATA_WIDTH 	= 8; 			
	localparam 	CSI_STRB_WIDTH 	= CSI_DATA_WIDTH / 8; 

	
	////////////////////////////////////////////////////////////////
	//	MIPI-CSI Crop
	
	wire			XYCrop_frame_vsync; 
	wire			XYCrop_frame_href;
	wire			XYCrop_frame_de;
	wire	[7:0]	XYCrop_frame_Gray;

    wire ov_frame_valid,ov_pixel_valid,ov_size_error;
    wire [7:0] ov_raw;
    wire [11:0] ov_line_width,ov_frame_height;
    ov5640_dvp #(.WIDTH(960),.HEIGHT(720)) u_ov5640_dvp(
     .pclk(cmos_pclk),.rst_n(rstn_sys),.configured(i2c_config_done),
     .vsync(cmos_vsync),.href(cmos_href),.data(cmos_data),
     .frame_valid(ov_frame_valid),.pixel_valid(ov_pixel_valid),.pixel(ov_raw),
     .size_error(ov_size_error),.last_width(ov_line_width),.last_height(ov_frame_height));
	Sensor_Image_XYCrop
	#(
		.IMAGE_HSIZE_SOURCE (960),
		.IMAGE_VSIZE_SOURCE (720),
		.IMAGE_HSIZE_TARGET (960 / CSI_STRB_WIDTH),
		.IMAGE_YSIZE_TARGET (720 	 ),
		.PIXEL_DATA_WIDTH	(CSI_DATA_WIDTH) 		//	32		 )
	)
	u_Sensor_Image_XYCrop
	(
		//	globel clock
		.clk			(cmos_pclk),			//	image pixel clock
		.rst_n		(rstn_sys),			//	system reset
		
		//CMOS Sensor interface
		.image_in_vsync (ov_frame_valid),			//H : Data Valid; L : Frame Sync(Set it by register)
		.image_in_href	(ov_pixel_valid),			//H : Data vaild, L : Line Sync
		.image_in_de	(ov_pixel_valid), 			//H : Data Enable, L : Line Sync
		.image_in_data	(ov_raw),			//8 bits cmos data input
		
		.image_out_vsync(XYCrop_frame_vsync ),			//H : Data Valid; L : Frame Sync(Set it by register)
		.image_out_href (XYCrop_frame_href	),			//H : Data vaild, L : Line Sync
		.image_out_de	(XYCrop_frame_de	), 			//H : Data Enable, L : Line Sync
		.image_out_data (XYCrop_frame_Gray	)			//8 bits cmos data input	
	);

    
	// RAW8 Bayer 先去马赛克，再转灰度。
	// 直接对 Bayer 相邻像素做 Sobel 会把 R/G/B 通道亮度差误判为大量边缘。
	wire        gray_sop, gray_valid, gray_eop;
	wire [7:0]  gray_data;
	wire        pre_rgb_vsync, pre_rgb_href, pre_rgb_hsync;
	wire [7:0]  pre_rgb_r, pre_rgb_g, pre_rgb_b;

	raw8_rgb_frame #(
		.IMG_HDISP(960),
		.IMG_VDISP(720)
	) u_pre_canny_bayer2rgb (
		.clk             (cmos_pclk),
		.rst_n           (rstn_sys),
		// Use the reference project's unmirrored sensor/Bayer configuration.
		.mirror          (2'b00),
		.per_frame_vsync (XYCrop_frame_vsync),
		.per_frame_href  (XYCrop_frame_href),
		.per_frame_hsync (XYCrop_frame_href),
		.per_img_RAW     (XYCrop_frame_Gray),
		.post_frame_vsync(pre_rgb_vsync),
		.post_frame_href (pre_rgb_href),
		.post_frame_hsync(pre_rgb_hsync),
		.post_img_red    (pre_rgb_r),
		.post_img_green  (pre_rgb_g),
		.post_img_blue   (pre_rgb_b)
	);

    // Common anti-alias filtering is before resizing and all five algorithms.
    wire smooth_rgb_frame,smooth_rgb_valid;wire [23:0] smooth_rgb;
    camera_rgb_denoise #(.WIDTH(960),.HEIGHT(720)) u_camera_rgb_smooth(
     .clk(cmos_pclk),.rst_n(rstn_sys && i2c_config_done),
     .in_frame(pre_rgb_vsync),.in_valid(pre_rgb_href),.in_rgb({pre_rgb_r,pre_rgb_g,pre_rgb_b}),
     .out_frame(smooth_rgb_frame),.out_valid(smooth_rgb_valid),.out_rgb(smooth_rgb));
    // Preserve the full camera field before resizing RGB, never subsample Bayer.
    wire [23:0] camera_rgb;
    wire [10:0] full_view_x,full_view_y;
    wire full_view_overflow;
wire canny_capture_ready;
wire shape_busy;
reg [7:0] status_meta,status_sync,status_display;
    camera_full_view #(.IN_W(960),.IN_H(720),.WIDTH(960),.HEIGHT(720),.IMAGE_H(720),.FIFO_BITS(6),.LINE_GAP(12)) u_camera_full_view(
     .clk(cmos_pclk),.rst_n(rstn_sys && i2c_config_done),
     .enable(canny_capture_ready && !shape_busy),
     .in_frame(smooth_rgb_frame),.in_valid(smooth_rgb_valid),
     .in_rgb(smooth_rgb),
     .out_valid(gray_valid),.out_sop(gray_sop),.out_eop(gray_eop),
     .out_rgb(camera_rgb),.out_x(full_view_x),.out_y(full_view_y),
     .overflow(full_view_overflow));

	// Y ≈ (R + 2G + B)/4, from the same resized RGB pixel stored in DDR.
	wire [9:0] pre_gray_sum = {2'b0,camera_rgb[23:16]} +
	                           {1'b0,camera_rgb[15:8],1'b0} +
	                           {2'b0,camera_rgb[7:0]};
	assign gray_data = pre_gray_sum[9:2];

    // Five gears; gestures are resolved on release (key1 +, key0 -).
    localparam [9:0] CANNY_THRESHOLD_INIT=10'd72;
    localparam FW=($clog2(FRAME_DEPTH)<1 ? 1 : $clog2(FRAME_DEPTH));
    wire [9:0] canny_threshold;
    wire [2:0] main_gear;
    wire [2:0] algorithm_requested;
    wire [1:0] display_mode_requested;
    wire temporal_requested=algorithm_requested==3'd4;
    wire [1:0] spatial_algorithm=temporal_requested ? 2'd3 : algorithm_requested[1:0];
    wire shape_requested=main_gear==4;
    // Slightly lower edge threshold in recognition gear; OSD shows this value.
    wire [9:0] processing_threshold=shape_requested ?
        (canny_threshold>10 ? canny_threshold-10'd10 : 10'd0) : canny_threshold;
    wire freeze_requested,compare_requested;
    wire [FW-1:0] replay_requested,left_requested,right_requested;
    wire display_overlay,display_history,display_compare,history_frozen;
    wire [FW-1:0] display_replay,display_left,display_right;
    wire [FW:0] history_count;
    wire [9:0] history_underflow_frame,history_underflow_total;
    wire [9:0] display_underflow_frame,display_underflow_total;
    // Gear 4 freezes the live stream after the accepted frame commits; replay
    // and comparison read the frames already in the history ring. Entering
    // comparison no longer captures a fresh batch. The history display only
    // appears once the stored frames are stable (frozen).
    wire history_requested=ENABLE_DDR_FRAME && main_gear==3 && history_frozen &&
        (compare_requested || freeze_requested);
    wire compare_capture_mode=ENABLE_DDR_FRAME && ENABLE_2FRAME_COMP && main_gear==3 && compare_requested;
    // Comparison always settles on stored frames: hold capture stopped while
    // it is active, even when the freeze toggle is in the continue state.
    wire history_freeze_request=freeze_requested || compare_capture_mode;
    wire overlay_requested=ENABLE_COLOR_OVERLAY && main_gear!=3 && display_mode_requested==1;
    video_key_control #(.CLOCK_HZ(84000000),.DEBOUNCE(840000),.DEFAULT_TEMPORAL(1),.ENABLE_MEDIAN(ENABLE_MEDIAN),.ENABLE_CANNY(ENABLE_CANNY),
     .ENABLE_COLOR_OVERLAY(ENABLE_COLOR_OVERLAY),.ENABLE_DDR_FRAME(ENABLE_DDR_FRAME),
     .ENABLE_2FRAME_COMP(ENABLE_2FRAME_COMP),.FRAME_DEPTH(FRAME_DEPTH)) u_video_keys(
     .clk(cmos_pclk),.rst_n(rstn_sys),.keys(key_data),.gear(main_gear),
     .algorithm(algorithm_requested),.display_mode(display_mode_requested),.threshold(canny_threshold),
     .freeze_requested(freeze_requested),.compare_mode(compare_requested),
     .replay_frame(replay_requested),.left_frame(left_requested),.right_frame(right_requested));

	// Retain the existing ROI coordinate convention for DDR thumbnail packing.
	// Offset includes the former 79 top black rows; preserve thumbnail sampling phase.
	wire [10:0] roi_x=full_view_x+11'd216;
	wire [9:0] roi_y=full_view_y+10'd121;
	wire roi_valid=gray_valid;
	wire roi_sop=gray_sop;
	wire roi_eop=gray_eop;
	wire canny_sop,canny_eop,canny_valid,canny_busy,canny_frame_start,canny_edge_protect;
	wire canny_gray_valid,canny_gray_sop,canny_gray_eop;
	wire [7:0] canny_data,canny_gray_data;
	
	
	wire canny_display_frame_toggle;
	canny_frame #(.WIDTH(960),.HEIGHT(720),.MEDIAN_ENABLE(ENABLE_MEDIAN),.CANNY_ENABLE(ENABLE_CANNY),.RUNTIME_MODES(1),.SOBEL_MAX_ENABLE(SOBEL_MAX_ENABLE),.ROBUST_NMS(1),.LOW_TIGHTEN(1),.BORDER_REFLECT(1),.NMS_TOLERANCE(4),.PROTECT_ENABLE(1),.COHERENT_PROTECT(1),.TEMPORAL_NMS(1)) u_canny_frame (
	 .clk(cmos_pclk),.rst_n(rstn_sys),.capture_ready(canny_capture_ready && !shape_busy),
	 .in_valid(roi_valid),.in_sop(roi_sop),.in_eop(roi_eop),.in_data(gray_data),
	 .threshold(processing_threshold),.algorithm(spatial_algorithm),.frame_start(canny_frame_start),.busy(canny_busy),
	 .gray_valid(canny_gray_valid),.gray_sop(canny_gray_sop),.gray_eop(canny_gray_eop),.gray_data(canny_gray_data),
	 .edge_valid(canny_valid),.edge_sop(canny_sop),.edge_eop(canny_eop),.edge_data(canny_data),.edge_protect(canny_edge_protect),
	 .sweep_count()
	);

    wire [1:0] shape_raw_result,shape_result;
    wire shape_raw_valid,shape_result_valid;
    reg shape_result_toggle;
    shape_detect #(.WIDTH(960),.HEIGHT(720)) u_shape_detect(
     .clk(cmos_pclk),.rst_n(rstn_sys),.enable(shape_requested),
     .in_valid(canny_valid),.in_sop(canny_sop),.in_eop(canny_eop),
     .edge_pixel(canny_data!=0),.shape(shape_raw_result),.result_valid(shape_raw_valid),.busy(shape_busy));
    // Publish confirmed labels only. Brief misses and competing classes do
    // not replace the displayed target on every analysed camera frame.
    shape_stabilizer u_shape_stabilizer(
     .clk(cmos_pclk),.rst_n(rstn_sys),.enable(shape_requested),
     .raw_valid(shape_raw_valid),.raw_shape(shape_raw_result),
     .shape(shape_result),.result_valid(shape_result_valid));
    always @(posedge cmos_pclk or negedge rstn_sys) begin
     if(!rstn_sys) shape_result_toggle<=0;
     else if(shape_result_valid) shape_result_toggle<=~shape_result_toggle;
    end
	// Gray stream is emitted during classification; edges follow two line windows.
	// Capture RGB only for the same ROI accepted by Canny, including its SOP.
	reg rgb_accepting;
	always @(posedge cmos_pclk or negedge rstn_sys) begin
	 if(!rstn_sys) rgb_accepting<=0;
	 else begin
	  if(canny_frame_start) rgb_accepting<=1;
	  if(roi_valid && roi_eop && rgb_accepting) rgb_accepting<=0;
	 end
	end
	wire rgb_store_en=roi_valid && (canny_frame_start || rgb_accepting);
	wire edge_store_en=canny_valid;
    // Full-size original luma, independent of the selected edge algorithm.
    wire gray_store_en=rgb_store_en;
    wire [7:0] gray_store_data=gray_data;
	wire split_store_eof=canny_valid && canny_eop;

    
    
	reg			r_XYCrop_frame_vsync = 0; 
	reg			r_XYCrop_frame_href = 0;
	reg			r_XYCrop_frame_de = 0;
	reg	[7:0]	r_XYCrop_frame_Gray = 0;
	
	always @(posedge cmos_pclk) begin
		r_XYCrop_frame_vsync <= XYCrop_frame_vsync; 
		r_XYCrop_frame_href <= XYCrop_frame_href;
		r_XYCrop_frame_de <= XYCrop_frame_de;
		r_XYCrop_frame_Gray <= XYCrop_frame_Gray;
	end
	
	//	Data Write Assignment
	wire			cmos_frame_vsync = r_XYCrop_frame_vsync;                     //  cmos frame data vsync valid signal
	wire			cmos_frame_href = r_XYCrop_frame_href && r_XYCrop_frame_de;	 //  cmos frame data href vaild  signal
	wire	[7:0]	cmos_frame_Gray = r_XYCrop_frame_Gray; 
	wire 			cmos_vsync_end;

	












	////////////////////////////////////////////////////////////////
	//	DDR R/W Control
	

	wire                            lcd_de;
	wire                            lcd_hs;      
	wire                            lcd_vs;
	wire 					  lcd_request; 
	wire            [11:0]          lcd_xpos;
	wire            [11:0]          lcd_ypos;
	wire            [7:0]           lcd_red, lcd_red2;
	wire            [7:0]           lcd_green, lcd_green2;
	wire            [7:0]           lcd_blue, lcd_blue2;
	wire            [7:0]           lcd_data;


	assign w_ddr3_awid = 0; 
	assign w_ddr3_wid = 0; 
	
	wire 			w_wframe_vsync; 
	wire 	[31:0] 	w_axi_tp; 
	
	// DDR中分平面保存同源灰度/边缘图，读出时按720p坐标重组。
	// 左图: x=0..423,y=201..518; 右图: x=432..1279,y=42..677。
    // Native pixels: two 960x720 panes, with 180-line status margins.
    wire view_active=lcd_xpos<1920 && lcd_ypos<1080;
    wire [11:0] view_x=lcd_xpos,view_y=lcd_ypos;
    wire view_request=lcd_request;
    wire [23:0] display_rgb;
    wire [23:0] scaled_image_rgb=display_rgb;
    wire split_overlap_row=view_y>=180 && view_y<900;
    wire split_stream_request=view_request && split_overlap_row && view_x<1920;
    wire [23:0] lcd_overlay_rgb;
    wire overlay_left_pixel=split_overlap_row && view_x<960;
    wire overlay_pixel=split_overlap_row && view_x>=960 && view_x<1920;
    wire history_play_pixel=split_overlap_row && view_x>=480 && view_x<1440;
    wire history_compare_pixel=split_overlap_row && view_x<1920;
    wire display_stream_request=view_active && (display_history ?
      (view_request && (display_compare ? history_compare_pixel : history_play_pixel)) : split_stream_request);

	split_frame_ctrl #(.EDGE_LINES(720),.GRAY_LINES(720),.LETTERBOX_TOP(0),.HISTORY_ENABLE(ENABLE_DDR_FRAME),.FRAME_DEPTH(FRAME_DEPTH),.COMPACT_BURSTS(1),.COLOR_ENABLE(ENABLE_COLOR_OVERLAY),.C_BUF_SIZE(23),.C_ID_LEN(4),.OVERLAY_SINGLE(0),.HISTORY_COMPARE_NATIVE(0),.TEMPORAL_ENABLE(ENABLE_DDR_FRAME && FRAME_DEPTH>=3),.CONFIG_GUARD(1),.MOTION_PROTECT(1)) u_split_frame_ctrl (

		.axi_clk        (w_ddr3_ui_clk            ),
		.axi_reset      (w_ddr3_ui_rst            ),

		.axi_awaddr     (w_ddr3_awaddr       ),
		.axi_awlen      (w_ddr3_awlen        ),
		.axi_awvalid    (w_ddr3_awvalid      ),
		.axi_awready    (w_ddr3_awready      ),

		.axi_wdata      (w_ddr3_wdata        ),
		.axi_wstrb      (w_ddr3_wstrb        ),
		.axi_wlast      (w_ddr3_wlast        ),
		.axi_wvalid     (w_ddr3_wvalid       ),
		.axi_wready     (w_ddr3_wready       ),

		.axi_bid        (4'b0000    ),
		.axi_bresp      (w_ddr3_bresp),
		.axi_bvalid     (w_ddr3_bvalid),

		.axi_arid       (w_ddr3_arid         ),
		.axi_araddr     (w_ddr3_araddr       ),
		.axi_arlen      (w_ddr3_arlen        ),
		.axi_arvalid    (w_ddr3_arvalid      ),
		.axi_arready    (w_ddr3_arready      ),

		.axi_rid        (w_ddr3_rid          ),
		.axi_rdata      (w_ddr3_rdata        ),
		.axi_rresp      (2'b00      ),
		.axi_rlast      (w_ddr3_rlast        ),
		.axi_rvalid     (w_ddr3_rvalid       ),
		.axi_rready     (w_ddr3_rready       ),

		.wframe_pclk    (cmos_pclk            ),
		.wframe_eof     (split_store_eof       ),
		.wframe_sof     (canny_frame_start     ),
		.capture_ready  (canny_capture_ready   ),
		.display_frame_toggle(canny_display_frame_toggle),
		.gray_data_en   (gray_store_en         ),
		.gray_data      (gray_store_data       ),
		.edge_data_en   (edge_store_en         ),
		.edge_data      (canny_data            ),
        .rgb_data_en    (rgb_store_en),
        .rgb_data       (camera_rgb),
        .left_rgb_data_en(1'b0),
        .left_rgb_data(24'd0),
        .rframe_left(overlay_left_pixel),
        .overlay_requested(overlay_requested),
        .temporal_requested(temporal_requested),.edge_configuration({spatial_algorithm,processing_threshold}),.edge_protect(canny_edge_protect),
        .freeze_requested(history_freeze_request),.history_requested(history_requested),
        .compare_requested(ENABLE_2FRAME_COMP && (main_gear==3 ? compare_requested : 1'b1)),
        .replay_requested(replay_requested),.left_requested(left_requested),.right_requested(right_requested),
        .display_history(display_history),.display_compare(display_compare),
        .display_replay(display_replay),.display_left(display_left),.display_right(display_right),
        .frozen(history_frozen),.history_count(history_count),
        .history_underflow_frame(history_underflow_frame),.history_underflow_total(history_underflow_total),
        .display_underflow_frame(display_underflow_frame),.display_underflow_total(display_underflow_total),
        .display_overlay(display_overlay),
        .rframe_rgb     (lcd_overlay_rgb),
		
		.rframe_pclk    (clk_pixel            ),
		.rframe_vsync   (~lcd_vs             ),		//	Reader VSync. Flush on rising edge. Connect to ~EOF. 
		.rframe_data_en (display_stream_request    ),
		.rframe_data    (lcd_data           ),
		
		.tp_o 		(w_axi_tp)
	);
	assign led_o[3:0] = w_axi_tp[3:0]; 
	
	
	
	
	////////////////////////////////////////////////////////////////
	//  LCD Timing Driver

    wire split_left_pixel=overlay_left_pixel;
    wire split_right_pixel=overlay_pixel;
    wire display_edge_wide;
    wire display_edge_pixel=EDGE_DISPLAY_THICK ? display_edge_wide:(lcd_data!=0);
    edge_display_width2 #(.WIDTH(960)) u_edge_display_width2 (
        .clk(clk_pixel),.rst_n(rstn_pixel),
        .valid(view_request && !display_history && (display_overlay ? overlay_pixel : split_right_pixel)),
        .x(view_x-12'd960),.y(view_y-12'd180),
        .edge_in(lcd_data!=8'd0),.edge_out(display_edge_wide)
    );
	// 坐标在lcd_driver中已与lcd_request同拍对齐，每个重叠行恰好消耗1280字节：
	// 424字节灰度 + 8字节黑色间隔 + 848字节边缘。
	wire [7:0] lcd_split_data = split_right_pixel ?
                                (display_edge_pixel ? 8'hff : 8'h00) :
                                (split_left_pixel ? lcd_data : 8'h00);

	// 阈值状态从摄像头域同步到 HDMI 像素域。按键事件之间该总线保持
	// 稳定，双级寄存器既隔离亚稳态，也让屏显数值与实际阈值一致。
	reg [9:0] canny_threshold_pixel_meta;
	reg [9:0] canny_threshold_pixel;
	always @(posedge clk_pixel or negedge rstn_pixel) begin
		if(!rstn_pixel) begin
			canny_threshold_pixel_meta <= CANNY_THRESHOLD_INIT;
			canny_threshold_pixel      <= CANNY_THRESHOLD_INIT;
		end else begin
			canny_threshold_pixel_meta <= processing_threshold;
			canny_threshold_pixel      <= canny_threshold_pixel_meta;
		end
	end

	// 在画面左上角叠加当前阈值，现场演示时可直接观察“阈值/边缘量”。
	wire [7:0] lcd_split_data_with_osd;
	wire osd_active;
	wire [9:0] canny_fps_measured;
	reg [9:0] canny_fps_osd;
	reg fps_vsync_d;
	frame_rate_meter #(.CLOCK_HZ(148500000)) u_canny_fps (
	 .clk(clk_pixel),.rst_n(rstn_pixel),.frame_toggle(canny_display_frame_toggle),.fps(canny_fps_measured));
	// Change displayed digits only during vertical blanking.
	always @(posedge clk_pixel or negedge rstn_pixel) begin
	 if(!rstn_pixel) begin canny_fps_osd<=0;fps_vsync_d<=0;end
	 else begin
	  fps_vsync_d<=lcd_vs;
	  if(fps_vsync_d && !lcd_vs) canny_fps_osd<=canny_fps_measured;
	 end
	end
    // Independent input activity monitor: works before configuration and ISP.
    reg [16:0] cam_pclk_div=0;
    reg cam_vs_d=0,cam_frame_toggle=0;
    always @(posedge cmos_pclk or negedge rstn_sys) begin
     if(!rstn_sys) begin cam_pclk_div<=0;cam_vs_d<=0;cam_frame_toggle<=0;end
     else begin
      cam_pclk_div<=cam_pclk_div+1'b1;cam_vs_d<=cmos_vsync;
      if(cmos_vsync && !cam_vs_d) cam_frame_toggle<=!cam_frame_toggle;
     end
    end
    wire [9:0] camera_input_fps;
    frame_rate_meter #(.CLOCK_HZ(148500000)) u_camera_input_fps(
     .clk(clk_pixel),.rst_n(rstn_pixel),.frame_toggle(cam_frame_toggle),.fps(camera_input_fps));
    reg [2:0] cam_pclk_sync;
    reg [23:0] cam_idle;
    reg cam_clock_seen;
    reg [51:0] camera_meta,camera_sync,camera_display;
    reg [9:0] camera_fps_display;
    reg camera_clock_display;
    always @(posedge clk_pixel or negedge rstn_pixel) begin
     if(!rstn_pixel) begin
      cam_pclk_sync<=0;cam_idle<=14850000;cam_clock_seen<=0;
      camera_meta<=0;camera_sync<=0;camera_display<=0;camera_fps_display<=0;camera_clock_display<=0;
     end else begin
      cam_pclk_sync<={cam_pclk_sync[1:0],cam_pclk_div[16]};
      if(cam_pclk_sync[2]!=cam_pclk_sync[1]) begin cam_idle<=0;cam_clock_seen<=1;end
      else if(cam_idle<14850000) cam_idle<=cam_idle+1'b1;
      camera_meta<={i2c_config_done,ov5640_config_failed,ov_size_error,ov5640_chip_id,
                    ov5640_config_index,ov_line_width,ov_frame_height};
      camera_sync<=camera_meta;
      if(fps_vsync_d && !lcd_vs) begin
       camera_display<=camera_sync;camera_fps_display<=camera_input_fps;
       camera_clock_display<=cam_clock_seen && cam_idle<14850000;
      end
     end
    end
    wire [23:0] camera_osd_rgb;wire camera_osd_active;
    camera_status_osd u_camera_status_osd(
     .x_pos(lcd_xpos),.y_pos(lcd_ypos),.ready(camera_display[51]),.failed(camera_display[50]),
     .size_error(camera_display[49]),.pclk_alive(camera_clock_display),.chip_id(camera_display[48:33]),
     .config_index(camera_display[32:24]),.input_fps(camera_fps_display),
     .width(camera_display[23:12]),.height(camera_display[11:0]),.pixel(camera_osd_rgb),.active(camera_osd_active));
	threshold_osd #(
		.X_START(12'd32),
		.Y_START(12'd24)
	) u_threshold_osd (
		.x_pos     (lcd_xpos),
		.y_pos     (lcd_ypos),
		.threshold (canny_threshold_pixel),
		.fps       (canny_fps_osd),
		.pixel_in  (lcd_split_data),
		.pixel_out (lcd_split_data_with_osd),
        .osd_active(osd_active)
	);
	
	wire [7:0] history_pixel=(display_compare ? history_compare_pixel : history_play_pixel) ? lcd_data : 0;
    assign display_rgb=display_history ? {3{history_pixel}} : display_overlay ?
                               (overlay_left_pixel ? lcd_overlay_rgb :
                                overlay_pixel ? (display_edge_pixel ? 24'hff0000 : lcd_overlay_rgb) :
                                24'd0) : {3{lcd_split_data}};
	
    always @(posedge clk_pixel or negedge rstn_pixel) begin
     if(!rstn_pixel) begin status_meta<={3'd3,5'b0};status_sync<={3'd3,5'b0};status_display<={3'd3,5'b0};end
     else begin
      status_meta<={algorithm_requested,history_frozen,1'b0,main_gear};status_sync<=status_meta;
      if(fps_vsync_d && !lcd_vs) status_display<=status_sync;
     end
    end
    wire [23:0] status_rgb;wire status_active;
    wire [7:0] frame_pixel;wire frame_active;
    wire [7:0] underflow_pixel;wire underflow_active;
    wire [23:0] freeze_rgb;wire freeze_active;
    wire [11:0] status_x=lcd_xpos;
    wire [11:0] status_y=lcd_ypos;
    video_status_osd #(.X_START(32),.Y_START(80),.FW(FW)) u_status_osd(
     .x_pos(status_x),.y_pos(status_y),.gear(status_display[2:0]),.algorithm(status_display[7:5]),
     .overlay(display_overlay),.history(display_history),.compare(display_compare),
     .replay(display_replay),.left_frame(display_left),.right_frame(display_right),
     .pixel(status_rgb),.active(status_active));
    threshold_osd #(.X_START(1040),.Y_START(24),.LABEL_KIND(2)) u_frame_osd(
     .x_pos(lcd_xpos),.y_pos(lcd_ypos),.threshold({{(10-FW){1'b0}},display_left}),
     .fps({{(10-FW){1'b0}},display_right}),.pixel_in(8'd0),.pixel_out(frame_pixel),.osd_active(frame_active));
    // Last-frame and cumulative missing display pixels, saturated at 999.
    // Missing display pixels in all five modes.
    threshold_osd #(.X_START(1200),.Y_START(24),.LABEL_KIND(4)) u_underflow_osd(
     .x_pos(lcd_xpos),.y_pos(lcd_ypos),.threshold(display_underflow_frame),
     .fps(display_underflow_total),.pixel_in(8'd0),.pixel_out(underflow_pixel),.osd_active(underflow_active));
    reg [FW:0] count_pixel_meta,count_pixel_sync,count_pixel_display;
    always @(posedge clk_pixel or negedge rstn_pixel) begin
     if(!rstn_pixel) begin count_pixel_meta<=0;count_pixel_sync<=0;count_pixel_display<=0;end
     else begin count_pixel_meta<=history_count;count_pixel_sync<=count_pixel_meta;
      if(fps_vsync_d && !lcd_vs) count_pixel_display<=count_pixel_sync;
     end
    end
    video_status_osd #(.X_START(608),.Y_START(24),.FW(FW),.STATE_ONLY(1)) u_freeze_osd(
     .x_pos(lcd_xpos),.y_pos(lcd_ypos),.gear(3'd3),.algorithm(3'd0),
     .overlay(1'b0),.history(1'b1),.compare(1'b0),.replay(display_replay),
     .left_frame(display_left),.right_frame(display_right),.frozen(status_display[4]),
     .frame_count(count_pixel_display),.pixel(freeze_rgb),.active(freeze_active));
    // Bundled result is stable between frame completions. The extra toggle
    // register ensures both bus synchronizers settle before pending is sampled.
    reg shape_toggle_meta,shape_toggle_sync,shape_toggle_seen;
    reg [1:0] shape_meta,shape_sync,shape_pending,shape_display;
    always @(posedge clk_pixel or negedge rstn_pixel) begin
     if(!rstn_pixel) begin
      shape_toggle_meta<=0;shape_toggle_sync<=0;shape_toggle_seen<=0;
      shape_meta<=0;shape_sync<=0;shape_pending<=0;shape_display<=0;
     end else begin
      shape_toggle_meta<=shape_result_toggle;shape_toggle_sync<=shape_toggle_meta;
      shape_meta<=shape_result;shape_sync<=shape_meta;
      shape_toggle_seen<=shape_toggle_sync;
      if(shape_toggle_sync!=shape_toggle_seen) shape_pending<=shape_sync;
      if(fps_vsync_d && !lcd_vs) shape_display<=shape_pending;
     end
    end
    wire [23:0] shape_rgb;wire shape_active;
    shape_osd #(.X_START(848),.Y_START(1020)) u_shape_osd(.x_pos(lcd_xpos),.y_pos(lcd_ypos),.shape(shape_display),
                         .pixel(shape_rgb),.active(shape_active));
    wire [23:0] display_rgb_osd=camera_osd_active ? camera_osd_rgb :
       status_display[2:0]==4 && shape_active ? shape_rgb :
       osd_active ? {3{lcd_split_data_with_osd}} :
       status_active ? status_rgb : display_history && display_compare && frame_active ? {3{frame_pixel}} :
       underflow_active ? {3{underflow_pixel}} :
       display_history && freeze_active ? freeze_rgb : scaled_image_rgb;
	lcd_driver u_lcd_driver
	(
	    //  global clock
	    .clk        (clk_pixel),
	    .rst_n      (rstn_pixel), 
	    
	    //  lcd interface
	    .lcd_dclk   (               ),
	    .lcd_blank  (               ),
	    .lcd_sync   (               ),
	    .lcd_request(lcd_request    ), 	//	Request data 1 cycle ahead. 
	    .lcd_hs     (lcd_hs         ),
	    .lcd_vs     (lcd_vs         ),
	    .lcd_en     (lcd_de         ),
	    .lcd_rgb    ({lcd_red2,lcd_green2,lcd_blue2, lcd_red,lcd_green,lcd_blue}),
	    .lcd_xpos   (lcd_xpos       ),
	    .lcd_ypos   (lcd_ypos       ),
	    
	    //  user interface
	    // Legacy interface carries two RGB888 pixels; duplicate the composed pixel.
	    .lcd_data   ({2{display_rgb_osd}})
	);
	
    
    
	// =========================================================================================================================================
// bayer 2 rgb
// ========================================================================================================================================= 
	
	wire 			w_rgb_vsync, w_rgb_href; 
	wire 	[7:0] 	w_rgb_pre_r, w_rgb_pre_g, w_rgb_pre_b; 
	
    VIP_RAW8_RGB888 #(.IMG_HDISP(1280), .IMG_VDISP(720)) bayer2rgb (
    .clk                               (clk_pixel                ),//74.25MHz HDMI pixel clock (720p60)
    .rst_n                             (rstn_pixel               ),//global reset
	    
    .mirror                            (2'b00                     ),
		
		    //CMOS YCbCr444 data output
    .per_frame_vsync                   (lcd_vs                    ),//	Prepared Image data vsync valid signal. Reset on falling edge. 
    .per_frame_href                    (lcd_de                    ),//	Prepared Image data href vaild  signal
    .per_frame_hsync                   (lcd_hs                    ),
    .per_img_RAW                       (lcd_blue[7:0]             ),//	Input data from AXI reader directly. Latency is 1T. Matches with VS / HS / DE signals. 
		
    .post_frame_vsync                  (w_rgb_vsync               ),//Processed Image data vsync valid signal
    .post_frame_href                   (w_rgb_href                ),//Processed Image data href vaild  signal
    .post_frame_hsync                  (w_rgb_hsync               ),//Processed Image data href vaild  signal
    .post_img_red                      (w_rgb_pre_r               ),//Prepared Image green data to be processed 
    .post_img_green                    (w_rgb_pre_g               ),//Prepared Image green data to be processed
    .post_img_blue                     (w_rgb_pre_b               ) //Prepared Image blue data to be processed
    );
// =========================================================================================================================================
// manual awb
// ========================================================================================================================================= 
//手动白平衡算法
wire [7:0] w_rgb_r;
wire [7:0] w_rgb_g;
wire [7:0] w_rgb_b;
wire     [17:0]     w_rgb_r_mult = w_rgb_pre_r * 409; 
wire     [17:0]     w_rgb_b_mult = w_rgb_pre_b * 384; 
assign w_rgb_r = w_rgb_r_mult[17:16] ? 8'hFF : w_rgb_r_mult[15: 8]; 
assign w_rgb_g = w_rgb_pre_g; 
assign w_rgb_b = w_rgb_b_mult[17:16] ? 8'hFF : w_rgb_b_mult[15: 8]; 


wire                                    boundcrop_vs               ;
wire                                    boundcrop_hs               ;
wire                                    boundcrop_de               ;
wire                   [  23:0]         boundcrop_data             ;
FrameBoundCrop #(.SKIP_ROWS(2),.SKIP_COLS(2),.TOTAL_ROWS(720),.TOTAL_COLS(1280)) inst2_FrameCrop(
    .clk_i                             (clk_pixel                 ),
    .rst_i                             (~rstn_pixel               ),
	
    .vs_i                              (w_rgb_vsync               ),
    .hs_i                              (w_rgb_hsync               ),
    .de_i                              (w_rgb_href                ),
    .data_i                            ({w_rgb_r, w_rgb_g, w_rgb_b}),
	
    .vs_o                              (boundcrop_vs              ),
    .hs_o                              (boundcrop_hs              ),
    .de_o                              (boundcrop_de              ),
    .data_o                            (boundcrop_data            ) 
);



	assign hdmi_txd0_rst_o = rst_pixel; 
	assign hdmi_txd1_rst_o = rst_pixel; 
	assign hdmi_txd2_rst_o = rst_pixel; 
	assign hdmi_txc_rst_o = rst_pixel; 
	
	assign hdmi_txd0_oe = 1'b1; 
	assign hdmi_txd1_oe = 1'b1; 
	assign hdmi_txd2_oe = 1'b1; 
	assign hdmi_txc_oe = 1'b1; 
	

    rgb2dvi #(.ENABLE_OSERDES(0)) u_rgb2dvi
    (
	    .oe_i                              (1'b1                      ),//	Always enable output
    .bitflip_i                         (4'b0000                   ),//	Reverse clock & data lanes. 
		
    .aRst                              (1'b0                      ),
    .aRst_n                            (1'b1                      ),
		
    .PixelClk                          (clk_pixel                 ),//pixel clk =148.5MHz (1080p60)
    .SerialClk                         (                          ),//pixel clk *5 = 371.25M
		
	    .vid_pVSync                        (~lcd_vs                    ),
	    .vid_pHSync                        (~lcd_hs                    ),
	    .vid_pVDE                          (lcd_de                    ),
	    .vid_pData                         ({lcd_red, lcd_green, lcd_blue}),
		
    .txc_o                             (hdmi_txc_o                ),
    .txd0_o                            (hdmi_txd0_o               ),
    .txd1_o                            (hdmi_txd1_o               ),
    .txd2_o                            (hdmi_txd2_o               ) 
    );
		
	






	
	
endmodule



