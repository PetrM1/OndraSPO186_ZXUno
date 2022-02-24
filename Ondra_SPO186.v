`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    09:35:12 09/24/2021 
// Design Name: 
// Module Name:    Ondra_SPO186 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module Ondra_SPO186(
		input wire CLK_IN,

		input wire PS2_CLK1,
		input wire PS2_DAT1,

		output wire VGA_VSYNC,
		output wire VGA_HSYNC,
		output wire [2:0] VGA_BLUE,
		output wire [2:0] VGA_GREEN,
		output wire [2:0] VGA_RED,
		
		input wire JOY1_UP,
		input wire JOY1_DOWN,
		input wire JOY1_LEFT,
		input wire JOY1_RIGHT,
		input wire JOY1_FIRE,

		input wire RXD,

		output wire AUDIO_LEFT,
		output wire AUDIO_RIGHT,

		input wire SD_MISO,
		output wire SD_SCK,
		output wire SD_MOSI,
		output wire SD_nCS,

		inout wire [7:0] SRAM_DATA,
		output wire [20:0] SRAM_ADDR,
		output wire SRAM_WE,

      output wire O_NTSC,
      output wire O_PAL,

		output wire LED,
		
		input wire NMI,
		input wire SERVICE,
		input wire EAR
    );

assign SD_nCS = 1'b1;
assign { SD_SCK, SD_MOSI} = 0;
assign O_NTSC = 1'b0;
assign O_PAL = 1'b1;

 
wire clk_sys;
wire reset_n;
 
wire clk_vga; // 16MHz
wire HSync;
wire VSync;
wire HBlank;
wire VBlank;	
wire pixel;
wire beeper;
wire LED_GREEN;
wire LED_YELLOW;
wire LED_RED;
wire RESERVA_IN;	//rxd
wire RESERVA_OUT; // txd		
wire MGF_IN;		// cassette line in (from ADC)
	
	
wire [7:0] VGA_R;
wire [7:0] VGA_G;
wire [7:0] VGA_B;

//------------------------------------------------------------
//-- Sigma Delta DAC
//------------------------------------------------------------
wire [4:0] AUDIO;
assign AUDIO_RIGHT = AUDIO_LEFT;
dac #(.msbi_g(4)) dac(
		.clk_i(clk_sys),
		.resetn(reset_n),
		.dac_i(AUDIO),
		.dac_o(AUDIO_LEFT)
);

		
assign VGA_VSYNC = scandoublerEnabled ? SD_VSYNC : 1;
assign VGA_HSYNC = scandoublerEnabled ? SD_HSYNC : (HSync ^ ~VSync);
assign VGA_BLUE  = (scandoublerEnabled ? SD_PIXEL : pixel) ? 3'b111 : 3'b000;
assign VGA_GREEN = (scandoublerEnabled ? SD_PIXEL : pixel) ? 3'b111 : 3'b000;
assign VGA_RED   = (scandoublerEnabled ? SD_PIXEL : pixel) ? 3'b111 : 3'b000;
assign LED = LED_RED;

wire [7:0] scancode;
wire released;
wire extended;
wire kb_interrupt;
reg kb_stb;
 

wire locked;	
reg [1:0] ROMVersion = 2'b01;	


wire [20:0] SRAM_ADDR_O;
wire SRAM_WE_O;
reg [2:0] reset_clk = 3'b111;
// Initial video output settings
reg [7:0] scandblr_reg; // same layout as in the Spectrum core, SCANDBLR_CTRL
	 // scandblr_reg[0] = VGA
	 // VGA: to 1 to enable scandoubler. The scandoubler's output is the same as normal RGB output, 
	 // but doubling the horizontal delay frequency. Set to 0 to use 15kHz RGB / composite video output. 
wire scandoublerEnabled = ~scandblr_reg[0];
	 
always @(negedge SERVICE)
	ROMVersion[0] <= ~ROMVersion[0];

assign reset_n = (reset_clk == 3'b000);
// 21'h008FD5;  // magic place where the scandoubler settings have been stored
assign SRAM_ADDR = reset_n ? SRAM_ADDR_O : 21'h008FD5;
assign SRAM_WE = reset_n ? SRAM_WE_O : 1'b0;
always @(posedge CLK_IN)
begin
	if (reset_clk == 3'b011)
		scandblr_reg <= SRAM_DATA;
	if (~(reset_clk == 3'b000))
		reset_clk <= reset_clk - 3'b001;	
end	
	
pll myClk( .CLK_50M(CLK_IN), .CLK_8M(clk_sys), .CLK_VGA(clk_vga), .RESET(1'b0), .LOCKED(locked));

ps2_port kbd_port(.clk(clk_sys), .enable_rcv(1'b1), .kb_or_mouse(1'b0), 
	.ps2clk_ext(PS2_CLK1), .ps2data_ext(PS2_DAT1),
	.kb_interrupt(kb_interrupt), .scancode(scancode), 
	.released(released), .extended(extended));

always @(posedge kb_interrupt)
	kb_stb <= ~kb_stb;
 
mist_scandoubler  myscandoubler
( 
    //input 
	 .clk(clk_vga),
	 .clk_16(clk_sys),
	 .clk_16_en(1'b1),
    .scanlines(1'b0),
    
	 .r_in(pixel),
    .g_in(pixel),
    .b_in(pixel),
    .hs_in(HSync),
    .vs_in(VSync),
    
    //output 
	 .r_out(SD_PIXEL),
//	 .r_out(VGA_RED),
//    .g_out(VGA_GREEN),
//    .b_out(VGA_BLUE),
    .hs_out(SD_HSYNC),
    .vs_out(SD_VSYNC)	 
);	

wire SD_HSYNC;
wire SD_VSYNC;
wire SD_PIXEL;	
 

Ondra_SPO186_core myOndra(
	.clk_50M(CLK_IN), // 50MHz main clock
	.clk_sys(clk_sys),  // 8MHz clock 	 	
	.reset(~reset_n),
	.ps2_key({kb_stb, ~released, extended, scancode}),
	.HSync(HSync),
	.VSync(VSync),
	.HBlank(HBlank),
	.VBlank(VBlank),	
	.pixel(pixel),
	.beeper(beeper),
   .AUDIO(AUDIO),
	.joy({10'd0, ~JOY1_FIRE, ~JOY1_UP, ~JOY1_DOWN, ~JOY1_LEFT, ~JOY1_RIGHT}),
	.LED_GREEN(LED_GREEN),
	.LED_YELLOW(LED_YELLOW),
	.RELAY(LED_RED),

	.RESERVA_IN(RXD), //rxd
	.RESERVA_OUT(RESERVA_OUT), // txd		
	.MGF_IN(EAR),				// cassette line in (from ADC)
	.ROMVersion(ROMVersion),
	
	.SRAM_DATA(SRAM_DATA),
	.SRAM_ADDR(SRAM_ADDR_O),
	.SRAM_WE(SRAM_WE_O)
);

 
endmodule
