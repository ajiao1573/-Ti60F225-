`include "src/native_gray_capture.v"
`include "src/calibration_capture.v"
`include "src/camera_rgb_denoise.v"
`include "src/autoplate_core.v"
`include "src/host_uart.v"
`include "src/app_control_bridge.v"
`include "src/single_gray_view.v"
`include "src/video_thumbnail2.v"
`include "src/raw8_rgb_frame.v"
`include "src/plate_segmenter.v"
`include "src/nz_plate_osd.v"
`include "src/camera_full_view.v"
`include "src/video_scale_3_2.v"
`include "src/camera_status_osd.v"
`timescale 1ns/1ps
// Standalone plate capture and controls. Paths are relative to project root.
`include "src/plate_frame_gate.v"
`include "src/plate_key_control.v"

//`include "ddr3_controller.vh"


module example_top #(parameter CALIBRATION_CAPTURE=0,LENS_CORRECTION=1)(
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
	
// OV5640: 24 MHz reference, 1080p30 RAW8, 50 kHz SCCB as board reference.
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
    ov5640_dvp u_ov5640_dvp(
     .pclk(cmos_pclk),.rst_n(rstn_sys),.configured(i2c_config_done),
     .vsync(cmos_vsync),.href(cmos_href),.data(cmos_data),
     .frame_valid(ov_frame_valid),.pixel_valid(ov_pixel_valid),.pixel(ov_raw),
     .size_error(ov_size_error),.last_width(ov_line_width),.last_height(ov_frame_height));
	Sensor_Image_XYCrop
	#(
		.IMAGE_HSIZE_SOURCE (1920),
		.IMAGE_VSIZE_SOURCE (1080),
		.IMAGE_HSIZE_TARGET (1920 / CSI_STRB_WIDTH),
		.IMAGE_YSIZE_TARGET (1080 	 ),
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
		.IMG_HDISP(1920),
		.IMG_VDISP(1080)
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
    camera_rgb_denoise #(.WIDTH(1920),.HEIGHT(1080)) u_camera_rgb_smooth(
     .clk(cmos_pclk),.rst_n(rstn_sys && i2c_config_done),
     .in_frame(pre_rgb_vsync),.in_valid(pre_rgb_href),.in_rgb({pre_rgb_r,pre_rgb_g,pre_rgb_b}),
     .out_frame(smooth_rgb_frame),.out_valid(smooth_rgb_valid),.out_rgb(smooth_rgb));
    // Preserve the full camera field before resizing RGB, never subsample Bayer.
    wire [23:0] camera_rgb;
    wire [10:0] full_view_x,full_view_y;
    wire full_view_overflow;
    wire canny_capture_ready,canny_busy;
    wire lcd_vs;
    reg rearm_pending,plate_rearm;
    reg [9:0] edge_threshold;
    reg [7:0] applied_adjust;
    reg run_enable;
    assign camera_rgb=smooth_rgb;
    assign gray_valid=native_take;assign gray_sop=native_start;assign gray_eop=native_last;
    assign gray_data=native_gray;



    // Shared control inputs: local keys and UART apply to the same registers.
    localparam FRAME_DEPTH=8,FW=3;
    wire [7:0] plate_adjust;
    wire freeze_requested,remote_load,remote_rescan,requested_run_enable;
    wire [7:0] remote_adjust;
    wire [9:0] requested_edge_threshold;
    reg pre_rgb_frame_d;
    always @(posedge cmos_pclk or negedge rstn_sys)
     if(!rstn_sys) pre_rgb_frame_d<=0;else pre_rgb_frame_d<=pre_rgb_vsync;
    wire sensor_frame_boundary=pre_rgb_vsync && !pre_rgb_frame_d;
    reg previous_rescan;reg [7:0] previous_adjust;
    always @(posedge cmos_pclk or negedge rstn_sys)
     if(!rstn_sys) begin previous_rescan<=0;previous_adjust<=128;end
     else begin previous_rescan<=freeze_requested;previous_adjust<=plate_adjust;end
    wire key_or_remote_change=(previous_rescan!=freeze_requested)||(previous_adjust!=plate_adjust);
    // Key releases can occur mid-frame. Never reset Canny during an accepted
    // frame: preserve its final DDR EOF, then atomically apply the new settings.
    always @(posedge cmos_pclk or negedge rstn_sys)
     if(!rstn_sys) begin
      rearm_pending<=0;plate_rearm<=0;edge_threshold<=27;applied_adjust<=128;run_enable<=1;
     end else begin
      plate_rearm<=0;
      if(key_or_remote_change) rearm_pending<=1;
      if(rearm_pending && !canny_busy && !gray_valid) begin
       edge_threshold<=requested_edge_threshold;applied_adjust<=plate_adjust;run_enable<=requested_run_enable;
       rearm_pending<=0;plate_rearm<=1;
      end
     end
    plate_key_control #(.CLOCK_HZ(84000000),.DEBOUNCE(840000),.REMOTE_ENABLE(1)) u_plate_keys(
     .clk(cmos_pclk),.rst_n(rstn_sys),.keys(key_data),.adjust(plate_adjust),.rescan_toggle(freeze_requested),
     .remote_load(remote_load),.remote_adjust(remote_adjust),.remote_rescan(remote_rescan));
    wire command_valid,command_ready;wire [7:0] command_code;wire [15:0] command_value;
    wire [383:0] status_payload;reg [383:0] camera_status;
    wire image_arm,image_read,image_ready;wire [15:0] image_address;wire [7:0] image_data;
    host_uart #(.CLOCK_HZ(96000000),.BAUD(115200),.CALIBRATION_ENABLE(CALIBRATION_CAPTURE)) u_host_uart(
     .clk(clk_sys),.rst_n(rstn_sys),.rx(uart_rx_i),.tx(uart_tx_o),.status_payload(status_payload),
     .command_ready(command_ready),.command_valid(command_valid),.command_code(command_code),.command_value(command_value),
     .image_arm(image_arm),.image_read(image_read),.image_address(image_address),.image_ready(image_ready),.image_data(image_data));
    app_control_bridge u_app_control(
     .sys_clk(clk_sys),.sys_rst_n(rstn_sys),.cam_clk(cmos_pclk),.cam_rst_n(rstn_sys),.frame_boundary(sensor_frame_boundary),
     .command_valid(command_valid),.command_code(command_code),.command_value(command_value),.command_ready(command_ready),
     .camera_status(camera_status),.status_payload(status_payload),.edge_threshold(requested_edge_threshold),.run_enable(requested_run_enable),
     .remote_load(remote_load),.remote_adjust(remote_adjust),.remote_rescan(remote_rescan));

    wire plate_capture_hold,history_frozen,canny_frame_start,canny_frame_done;
    wire [7:0] core_state;wire [5:0] plate_state;
    wire plate_locked,plate_valid,plate_low,plate_overflow;
    wire [47:0] plate_ascii;wire [3:0] plate_count;wire [7:0] plate_threshold;
    wire [2:0] plate_reject;wire [1:0] locator_diagnostic;
    wire core_box_valid;wire [10:0] core_box_x,core_box_w;wire [10:0] core_box_y,core_box_h;
    wire [31:0] core_box_frame,captured_frame_id;
    wire edge_frame_toggle;
    wire [52:0] display_meta_cam;
    wire snapshot_ready=display_meta_cam[20] && display_meta_cam[52:21]==captured_frame_id;
    wire [10:0] roi_x=full_view_x;wire [10:0] roi_y=full_view_y;
    wire roi_valid=gray_valid,roi_sop=gray_sop,roi_eop=gray_eop;
    wire rgb_store_en,edge_store_en;wire [7:0] canny_data;
    // HDMI and recognition capture share all 1920x1080 source pixels.
    // Calibrated correction runs on the captured OCR ROI after admission.
    wire native_take,native_start,native_last;wire [7:0] native_gray;
    native_gray_capture u_native_preview(
     .clk(cmos_pclk),.rst_n(rstn_sys),
     .enable(canny_capture_ready && !canny_busy && !rearm_pending && !plate_rearm),
     .in_frame(smooth_rgb_frame),.in_valid(smooth_rgb_valid),.in_rgb(smooth_rgb),
     .take(native_take),.start(native_start),.last(native_last),.gray(native_gray),.source_x(full_view_x),.source_y(full_view_y));
    generate if(CALIBRATION_CAPTURE)begin:calibration_diagnostics
    calibration_capture u_calibration_capture(
     .cam_clk(cmos_pclk),.sys_clk(clk_sys),.rst_n(rstn_sys),.arm(image_arm),
     .in_valid(smooth_rgb_valid),.in_sop(full_view_x==0&&full_view_y==0),.in_eop(full_view_x==1919&&full_view_y==1079),
     .x(full_view_x),.y(full_view_y),.gray(native_gray),.read_enable(image_read),.read_address(image_address),.read_data(image_data),.ready(image_ready));
    end else begin:no_calibration_diagnostics
     assign image_ready=0;assign image_data=0;
    end endgenerate
    autoplate_core #(.WIDTH(1920),.HEIGHT(1080),.TEMPORAL_HISTORY(0),.LENS_CORRECTION(LENS_CORRECTION)) u_autoplate(
     .clk(cmos_pclk),.rst_n(rstn_sys),.run_enable(run_enable),.rearm(plate_rearm),
     .edge_threshold(edge_threshold),.char_adjust(applied_adjust),
     .in_valid(roi_valid),.in_sop(roi_sop),.in_eop(roi_eop),.in_gray(gray_data),.in_x(roi_x),.in_y(roi_y),
     .capture_ready(canny_capture_ready),.snapshot_ready(snapshot_ready),
     .pixel_clk(clk_pixel),.pixel_rst_n(rstn_pixel),.pixel_vsync(lcd_vs),
     .frame_start(canny_frame_start),.frame_done(canny_frame_done),.busy(canny_busy),.source_take(rgb_store_en),
     .preview_valid(edge_store_en),.preview_data(canny_data),.capture_hold(plate_capture_hold),.app_state(core_state),.segment_state(plate_state),
     .recognized_locked(plate_locked),.recognized_valid(plate_valid),.recognized_ascii(plate_ascii),
     .characters(plate_count),.binary_threshold(plate_threshold),.low_contrast(plate_low),.overflow(plate_overflow),
     .reject_reason(plate_reject),.locator_diagnostic(locator_diagnostic),
     .box_valid(core_box_valid),.box_x(core_box_x),.box_y(core_box_y),.box_w(core_box_w),.box_h(core_box_h),
     .box_frame(core_box_frame),.captured_frame_id(captured_frame_id),.edge_frame_toggle(edge_frame_toggle));
    wire history_freeze_request=plate_capture_hold;
    wire thumbnail_valid,thumbnail_eol;wire [23:0] thumbnail_rgb;
    video_thumbnail2 u_video_thumbnail2(
     .clk(cmos_pclk),.rst_n(rstn_sys),.in_valid(rgb_store_en),
     .in_x(full_view_x),.in_y(full_view_y),.in_rgb(camera_rgb),
     .out_valid(thumbnail_valid),.out_eol(thumbnail_eol),.out_rgb(thumbnail_rgb));
    wire [9:0] thumbnail_gray_sum={2'b0,thumbnail_rgb[23:16]}+{1'b0,thumbnail_rgb[15:8],1'b0}+{2'b0,thumbnail_rgb[7:0]};
    reg [3:0] gray_pad_count;
    always @(posedge cmos_pclk or negedge rstn_sys)
     if(!rstn_sys) gray_pad_count<=0;
     else if(thumbnail_valid && thumbnail_eol) gray_pad_count<=8;
     else if(gray_pad_count!=0) gray_pad_count<=gray_pad_count-1'b1;
    wire gray_store_en=thumbnail_valid || gray_pad_count!=0;
    wire [7:0] gray_store_data=thumbnail_valid ? thumbnail_gray_sum[9:2]:8'd0;
    wire split_store_eof=canny_frame_done;
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
	

    // One complete grayscale image. No split panes or character thumbnails.
    wire display_stream_request,stream_available;
    wire [31:0] display_frame_id;
    wire [9:0] fifo_missing_frame,fifo_missing_total,cache_missing_frame,cache_missing_total;
    wire [10:0] missing_frame_sum={1'b0,fifo_missing_frame}+{1'b0,cache_missing_frame};
    wire [10:0] missing_total_sum={1'b0,fifo_missing_total}+{1'b0,cache_missing_total};
    wire [9:0] display_underflow_frame=missing_frame_sum>999 ? 10'd999:missing_frame_sum[9:0];
    wire [9:0] display_underflow_total=missing_total_sum>999 ? 10'd999:missing_total_sum[9:0];
    wire [23:0] lcd_overlay_rgb;
	split_frame_ctrl #(.SINGLE_VIEW(1),.NATIVE_GRAY(1),.EDGE_LINES(1080),.GRAY_LINES(0),.LETTERBOX_TOP(0),.HISTORY_ENABLE(1),.FRAME_DEPTH(FRAME_DEPTH),.COMPACT_BURSTS(1),.COLOR_ENABLE(0),.C_BUF_SIZE(23),.C_ID_LEN(4),.OVERLAY_SINGLE(0),.HISTORY_COMPARE_NATIVE(0),.TEMPORAL_ENABLE(0),.CONFIG_GUARD(0),.MOTION_PROTECT(0)) u_split_frame_ctrl (

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
		.gray_data_en   (1'b0         ),
		.gray_data      (gray_store_data       ),
		.edge_data_en   (native_take         ),
		.edge_data      (native_gray            ),
        .rgb_data_en    (rgb_store_en),
        .rgb_data       (camera_rgb),
        .left_rgb_data_en(thumbnail_valid),
        .left_rgb_data(thumbnail_rgb),
        .rframe_left(1'b0),
        .overlay_requested(1'b0),
        .temporal_requested(1'b0),.edge_configuration(12'd0),.edge_protect(1'b0),
        .freeze_requested(history_freeze_request),.history_requested(1'b0),
        .compare_requested(1'b0),
        .replay_requested(3'd7),.left_requested(3'd0),.right_requested(3'd7),
        .display_history(),.display_compare(),
        .display_replay(),.display_left(),.display_right(),
        .frozen(history_frozen),.history_count(),
        .history_underflow_frame(),.history_underflow_total(),
        .display_underflow_frame(fifo_missing_frame),.display_underflow_total(fifo_missing_total),
        .stream_available(stream_available),.display_frame_id(display_frame_id),
        .display_overlay(),
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


    wire [76:0] box_packet_pixel;
    wire [76:0] box_packet_camera={core_box_frame,core_box_valid,core_box_x,core_box_y,core_box_w,core_box_h};
    status_snapshot #(.WIDTH(77)) u_box_snapshot(
     .source_clk(cmos_pclk),.source_rst_n(rstn_sys),.source_data(box_packet_camera),
     .target_clk(clk_pixel),.target_rst_n(rstn_pixel),.request(1'b1),.busy(),.valid(),.data(box_packet_pixel));
    wire [52:0] display_meta_pixel={display_frame_id,history_frozen,display_underflow_total,display_underflow_frame};
    status_snapshot #(.WIDTH(53)) u_display_snapshot(
     .source_clk(clk_pixel),.source_rst_n(rstn_pixel),.source_data(display_meta_pixel),
     .target_clk(cmos_pclk),.target_rst_n(rstn_sys),.request(1'b1),.busy(),.valid(),.data(display_meta_cam));
    wire [23:0] display_rgb_osd;
    single_gray_view #(.SOURCE_WIDTH(1920),.SOURCE_HEIGHT(1080),.BOX_SOURCE_WIDTH(1920),.BOX_SOURCE_HEIGHT(1080)) u_single_gray_view(
     .clk(clk_pixel),.rst_n(rstn_pixel),.vsync(lcd_vs),.lcd_request(lcd_request),.x_pos(lcd_xpos),.y_pos(lcd_ypos),
     .stream_data(lcd_data),.stream_available(stream_available),.stream_request(display_stream_request),
     .box_valid(box_packet_pixel[44] && box_packet_pixel[76:45]==display_frame_id),
     .box_x(box_packet_pixel[43:33]),.box_y(box_packet_pixel[32:22]),.box_w(box_packet_pixel[21:11]),.box_h(box_packet_pixel[10:0]),
     .rgb(display_rgb_osd),.underflow_frame(cache_missing_frame),.underflow_total(cache_missing_total));
    reg camera_frame_toggle,raw_frame_d;
    always @(posedge cmos_pclk or negedge rstn_sys)
     if(!rstn_sys) begin camera_frame_toggle<=0;raw_frame_d<=0;end
     else begin raw_frame_d<=ov_frame_valid;if(ov_frame_valid && !raw_frame_d) camera_frame_toggle<=!camera_frame_toggle;end
    wire [9:0] camera_input_fps,edge_input_fps;
    frame_rate_meter #(.CLOCK_HZ(84000000)) u_camera_input_fps(
     .clk(cmos_pclk),.rst_n(rstn_sys),.frame_toggle(camera_frame_toggle),.fps(camera_input_fps));
    frame_rate_meter #(.CLOCK_HZ(84000000)) u_edge_input_fps(
     .clk(cmos_pclk),.rst_n(rstn_sys),.frame_toggle(edge_frame_toggle),.fps(edge_input_fps));
    integer status_char;
    always @* begin
     camera_status=0;
     camera_status[0+:8]=1;
     camera_status[2*8+:8]=!i2c_config_done || ov_size_error ? 0:core_state;
     camera_status[3*8+:8]={run_enable,plate_capture_hold,plate_valid,plate_overflow,plate_low,
      (plate_capture_hold && plate_state!=2 && plate_state!=49 && plate_state!=50),core_box_valid,(i2c_config_done && !ov_size_error)};
     camera_status[4*8+:16]={6'd0,edge_threshold};camera_status[6*8+:8]=applied_adjust;
     camera_status[7*8+:8]={4'd0,plate_count};
     for(status_char=0;status_char<6;status_char=status_char+1)
      camera_status[(8+status_char)*8+:8]=plate_ascii[(5-status_char)*8+:8];
     camera_status[14*8+:8]={5'd0,plate_reject};camera_status[15*8+:8]={6'd0,locator_diagnostic};
     camera_status[16*8+:16]={5'd0,core_box_x};camera_status[18*8+:16]={5'd0,core_box_y};
     camera_status[20*8+:16]={5'd0,core_box_w};camera_status[22*8+:16]={5'd0,core_box_h};
     camera_status[24*8+:16]={6'd0,camera_input_fps};camera_status[26*8+:16]={6'd0,edge_input_fps};
     camera_status[28*8+:16]={6'd0,display_meta_cam[9:0]};camera_status[30*8+:16]={6'd0,display_meta_cam[19:10]};
     camera_status[32*8+:32]=captured_frame_id;
     camera_status[36*8+:16]=1920;camera_status[38*8+:16]=1080;
     camera_status[40*8+:16]=1920;camera_status[42*8+:16]=1080;
     camera_status[44*8+:8]=plate_threshold;camera_status[45*8+:8]=1;camera_status[46*8+:16]=1;
    end
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
		
    .PixelClk                          (clk_pixel                 ),//pixel clk = 74.25M (1080p30)
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



