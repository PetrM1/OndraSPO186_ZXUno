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
 
assign O_NTSC = ~PAL;// 1'b0;
assign O_PAL = PAL; //1'b1;

reg PAL = 1'b1; 
wire clk_sys;
wire clk_sn;
wire clk_snen;
wire reset_n;
wire NMI_reset_n; // from core from keyboard;
 
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
wire MGF_IN;		// cassette line in (from ADC)
	
wire [7:0] VGA_R;
wire [7:0] VGA_G;
wire [7:0] VGA_B;
 
//------------------------------------------------------------
//-- Ondra Melodik (sn76489)
//------------------------------------------------------------
wire [7:0] Parallel_Data_OUT;
wire NON_STB;
wire [13:0] mix_audio_o;
reg  ondra_melodik_clk_enable;

always @(negedge reset_n or negedge NON_STB)
begin
  if (~reset_n)
    ondra_melodik_clk_enable <= 0;
  else
    ondra_melodik_clk_enable <= 1;
end

sn76489_audio #(.MIN_PERIOD_CNT_G(17)) sn76489_audio
(  .clk_i(clk_sys),                                     //System clock
   .en_clk_psg_i(clk_snen & ondra_melodik_clk_enable),  //PSG clock enable
   .ce_n_i(0),                                          //chip enable, active low
   .wr_n_i(NON_STB),                                    // write enable, active low
   .data_i(Parallel_Data_OUT),
   .mix_audio_o(mix_audio_o)
);

//------------------------------------------------------------
//-- Sigma Delta DAC
//------------------------------------------------------------
assign AUDIO_RIGHT = AUDIO_LEFT;
dac #(.msbi_g(13)) dac(
   .clk_i(clk_sys),
	.resetn(reset_n),
	.dac_i(mix_audio_o | {11{beeper}}),
	.dac_o(AUDIO_LEFT)
);

//------------------------------------------------------------
//-- Ondra SD
//------------------------------------------------------------
wire OndraSD_signal_led;
wire OndraSD_rxd;
wire OndraSD_txd;

OndraSD #(.sysclk_frequency(50000000)) OndraSD // 50MHz
(
   .clk(CLK_IN),
   .reset_in(reset_n && NMI_reset_n),
   .enter_key(kbd_enter),
   .signal_led(OndraSD_signal_led),
   // SPI signals
   .spi_miso(SD_MISO),
   .spi_mosi(SD_MOSI),
   .spi_clk(SD_SCK),
   .spi_cs(SD_nCS),
   // UART
   .rxd(OndraSD_rxd),
   .txd(OndraSD_txd)
); 
 
assign LED = ~SD_nCS;

//------------------------------------------------------------
//-- Keyboard controls
//------------------------------------------------------------
reg kbd_reset = 0;
reg kbd_ROM_change = 0;
reg kbd_scandoublerOverride = 0;
reg old_stb;    
reg kbd_enter = 0;

always @(posedge clk_sys) 
begin
	old_stb <= kb_stb;
   if ((old_stb != kb_stb) & (~extended))
	begin		
      case(scancode)
         8'h03: kbd_reset <= ~released;         // F5 = RESET
         8'h83: if (~released)                  // F7 = NTSC/PAL
            PAL <= ~PAL;
         8'h0A: if (~released)                  // F8 = scandoubler Override
            kbd_scandoublerOverride <= ~kbd_scandoublerOverride;            
         8'h01: kbd_ROM_change <= ~released;    // F9 =  change ROM & reset!
         8'h5a : kbd_enter <= ~released;        // ENTER         
      endcase	
   end
end	
      
      
assign VGA_VSYNC = scandoublerEnabled ? SD_VSYNC : 1;
assign VGA_HSYNC = scandoublerEnabled ? SD_HSYNC : (HSync ^ ~VSync);
assign VGA_BLUE  = (scandoublerEnabled ? SD_PIXEL : pixel) ? 3'b111 : 3'b000;
assign VGA_GREEN = (scandoublerEnabled ? SD_PIXEL : pixel) ? 3'b111 : 3'b000;
assign VGA_RED   = (scandoublerEnabled ? SD_PIXEL : pixel) ? 3'b111 : 3'b000;

wire [7:0] scancode;
wire released;
wire extended;
wire kb_interrupt;
reg kb_stb;
wire locked;	
reg [1:0] ROMVersion = 2'b00;	
always @(posedge kbd_ROM_change)
begin
   if (ROMVersion == 2'b10)
      ROMVersion <= 2'b00;
   else
      ROMVersion <= ROMVersion + 2'b01;
end

wire [20:0] SRAM_ADDR_O;
wire SRAM_WE_O;
reg [8:0] reset_clk = 8'hFF;
// Initial video output settings
reg [7:0] scandblr_reg; // same layout as in the Spectrum core, SCANDBLR_CTRL
reg scandblr_1stRead = 1'b1;
	 // scandblr_reg[0] = VGA
	 // VGA: to 1 to enable scandoubler. The scandoubler's output is the same as normal RGB output, 
	 // but doubling the horizontal delay frequency. Set to 0 to use 15kHz RGB / composite video output. 
wire scandoublerEnabled = ~scandblr_reg[0] ^ kbd_scandoublerOverride;
	 
assign reset_n = (reset_clk == 8'h00);
// 21'h008FD5;  // magic place where the scandoubler settings have been stored
assign SRAM_ADDR = reset_n ? SRAM_ADDR_O : 21'h008FD5;
assign SRAM_WE = reset_n ? SRAM_WE_O : 1'b0;
always @(posedge CLK_IN)
begin
	if ((reset_clk == 8'b011) & scandblr_1stRead)
   begin
		scandblr_reg <= SRAM_DATA;
      scandblr_1stRead <= 1'b0;
   end;
   if (kbd_reset | kbd_ROM_change)
      reset_clk <= 8'hFF;
	else if (~(reset_clk == 8'h00))
		reset_clk <= reset_clk - 8'h1;	
end	
	
pll myClk(.CLK_50M(CLK_IN), 
          .CLK_8M(clk_sys), .CLK_VGA(clk_vga), .CLK_SN(clk_sn), .CLK_SNen(clk_snen), 
          .RESET(1'b0), .LOCKED(locked));

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
   .NMI_n(NMI_reset_n),
	.ps2_key({kb_stb, ~released, extended, scancode}),
	.HSync(HSync),
	.VSync(VSync),
	.HBlank(HBlank),
	.VBlank(VBlank),	
	.pixel(pixel),
	.beeper(beeper),   
	.joy({10'd0, ~JOY1_FIRE, ~JOY1_UP, ~JOY1_DOWN, ~JOY1_LEFT, ~JOY1_RIGHT}),
	.LED_GREEN(LED_GREEN),
	.LED_YELLOW(LED_YELLOW),
	.RELAY(LED_RED),
	.RESERVA_IN(OndraSD_txd),  //rxd
	.RESERVA_OUT(OndraSD_rxd), // txd
	.MGF_IN(EAR),				   // cassette line in (from ADC)
	.ROMVersion(ROMVersion),
   .Parallel_Data_OUT(Parallel_Data_OUT),	
   .NON_STB(NON_STB),
	.SRAM_DATA(SRAM_DATA),
	.SRAM_ADDR(SRAM_ADDR_O),
	.SRAM_WE(SRAM_WE_O)
);

 
endmodule
