//////////////////////////////////////////////////////////////////////////////
//
//  Xilinx, Inc. 2010                 www.xilinx.com
//
//  XAPP xxx
//
//////////////////////////////////////////////////////////////////////////////
//
//  File name :       decoder.v
//
//  Description :     Spartan-6 dvi decoder 
//
//
//  Author :          Bob Feng
//
//  Disclaimer: LIMITED WARRANTY AND DISCLAMER. These designs are
//              provided to you "as is". Xilinx and its licensors makeand you
//              receive no warranties or conditions, express, implied,
//              statutory or otherwise, and Xilinx specificallydisclaims any
//              implied warranties of merchantability, non-infringement,or
//              fitness for a particular purpose. Xilinx does notwarrant that
//              the functions contained in these designs will meet your
//              requirements, or that the operation of these designswill be
//              uninterrupted or error free, or that defects in theDesigns
//              will be corrected. Furthermore, Xilinx does not warrantor
//              make any representations regarding use or the results ofthe
//              use of the designs in terms of correctness, accuracy,
//              reliability, or otherwise.
//
//              LIMITATION OF LIABILITY. In no event will Xilinx or its
//              licensors be liable for any loss of data, lost profits,cost
//              or procurement of substitute goods or services, or forany
//              special, incidental, consequential, or indirect damages
//              arising from the use or operation of the designs or
//              accompanying documentation, however caused and on anytheory
//              of liability. This limitation will apply even if Xilinx
//              has been advised of the possibility of such damage. This
//              limitation shall apply not-withstanding the failure ofthe
//              essential purpose of any limited remedies herein.
//
//  Copyright � 2004 Xilinx, Inc.
//  All rights reserved
//
//////////////////////////////////////////////////////////////////////////////
// Modifications copyright (c) 2011, Andrew "bunnie" Huang
// All rights reserved as permitted by law.
//
// Redistribution and use in source and binary forms, with or without modification, 
// are permitted provided that the following conditions are met:
//
//  * Redistributions of source code must retain the above copyright notice, 
//    this list of conditions and the following disclaimer.
//  * Redistributions in binary form must reproduce the above copyright notice, 
//    this list of conditions and the following disclaimer in the documentation and/or 
//    other materials provided with the distribution.
//
//    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY 
//    EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
//    OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT 
//    SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, 
//    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT 
//    LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR 
//    PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, 
//    WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) 
//    ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE 
//    POSSIBILITY OF SUCH DAMAGE.
//
//////////////////////////////////////////////////////////////////////////////
`timescale 1 ns / 1ps

module decoder (
  input  wire reset,            //
  input  wire pclk,             //  pixel clock
  input  wire pclkx2,           //  double pixel rate for gear box
  input  wire pclkx10,          //  IOCLK
  input  wire serdesstrobe,     //  serdesstrobe for iserdes2
  input  wire din_p,            //  data from dvi cable
  input  wire din_n,            //  data from dvi cable
  input  wire other_ch0_vld,    //  other channel0 has valid data now
  input  wire other_ch1_vld,    //  other channel1 has valid data now
  input  wire other_ch0_rdy,    //  other channel0 has detected a valid starting pixel
  input  wire other_ch1_rdy,    //  other channel1 has detected a valid starting pixel

  output wire iamvld,           //  I have valid data now
  output wire iamrdy,           //  I have detected a valid new pixel
  output wire psalgnerr,        //  Phase alignment error
  output reg  c0,
  output reg  c1,
  output reg  de,     
  output reg [9:0] sdout,
  output reg [7:0] dout,
  output reg  dgb,
  output reg  vgb,
  output reg  ctl_vld,
  output wire line_end);

  ////////////////////////////////
  //
  // 5-bit to 10-bit gear box
  //
  ////////////////////////////////
  wire flipgear;
  reg flipgearx2;

  always @ (posedge pclkx2) begin
    flipgearx2 <=#1 flipgear;
  end

  reg toggle = 1'b0;

  always @ (posedge pclkx2 or posedge reset)
    if (reset == 1'b1) begin
      toggle <= 1'b0 ;
    end else begin
      toggle <=#1 ~toggle;
    end
  
  wire rx_toggle;

  assign rx_toggle = toggle ^ flipgearx2; //reverse hi-lo position

  wire [4:0] raw5bit;
  reg [4:0] raw5bit_q;
  reg [9:0] rawword;

  always @ (posedge pclkx2) begin
    raw5bit_q    <=#1 raw5bit;

    if(rx_toggle) //gear from 5 bit to 10 bit
      rawword <=#1 {raw5bit, raw5bit_q};
  end

  ////////////////////////////////
  //
  // bitslip signal sync to pclkx2
  //
  ////////////////////////////////
  reg bitslipx2 = 1'b0;
  reg bitslip_q = 1'b0;
  wire bitslip;

  always @ (posedge pclkx2) begin
    bitslip_q <=#1 bitslip;
    bitslipx2 <=#1 bitslip & !bitslip_q;
  end 

  /////////////////////////////////////////////
  //
  // 1:5 de-serializer working at x2 pclk rate
  //
  /////////////////////////////////////////////
  serdes_1_to_5_diff_data # (
    .DIFF_TERM("FALSE"),
    .BITSLIP_ENABLE("TRUE")
  ) des_0 (
    .use_phase_detector(1'b1),
    .datain_p(din_p),
    .datain_n(din_n),
    .rxioclk(pclkx10),
    .rxserdesstrobe(serdesstrobe),
    .reset(reset),
    .gclk(pclkx2),
    .bitslip(bitslipx2),
    .data_out(raw5bit)
  );

  /////////////////////////////////////////////////////
  // Doing word boundary detection here
  /////////////////////////////////////////////////////
  wire [9:0] rawdata = rawword;

  ///////////////////////////////////////
  // Phase Alignment Instance
  ///////////////////////////////////////
  phsaligner phsalgn_0 (
     .rst(reset),
     .clk(pclk),
     .sdata(rawdata),
     .bitslip(bitslip),
     .flipgear(flipgear),
     .psaligned(iamvld)
   );

  assign psalgnerr = 1'b0;

  ///////////////////////////////////////
  // Per Channel De-skew Instance
  ///////////////////////////////////////
  wire [9:0] sdata;
  chnlbond cbnd (
    .clk(pclk),
    .rawdata(rawdata),
    .iamvld(iamvld),
    .other_ch0_vld(other_ch0_vld),
    .other_ch1_vld(other_ch1_vld),
    .other_ch0_rdy(other_ch0_rdy),
    .other_ch1_rdy(other_ch1_rdy),
    .iamrdy(iamrdy),
    .sdata(sdata)
  );

   ////
   // hack to accelerate detection of line end so that HDCP rekey
   // can meet stringent timing spec requirement
   ////
   assign line_end = de &&
		     ((sdata == CTRLTOKEN0) ||
		      (sdata == CTRLTOKEN1) ||
		      (sdata == CTRLTOKEN2) ||
		      (sdata == CTRLTOKEN3));
   
  /////////////////////////////////////////////////////////////////
  // Below performs the 10B-8B decoding function defined in DVI 1.0
  // Specification: Section 3.3.3, Figure 3-6, page 31. 
  /////////////////////////////////////////////////////////////////
  // Distinct Control Tokens
  parameter CTRLTOKEN0 = 10'b1101010100;
  parameter CTRLTOKEN1 = 10'b0010101011;
  parameter CTRLTOKEN2 = 10'b0101010100;
  parameter CTRLTOKEN3 = 10'b1010101011;

  parameter DATA_GB    = 10'b0100110011;
  parameter VID_B_GB   = 10'b1011001100;
  parameter VID_G_GB   = 10'b0100110011;
  parameter VID_R_GB   = 10'b1011001100;

  wire [7:0] data;
  assign data = (sdata[9]) ? ~sdata[7:0] : sdata[7:0]; 

  always @ (posedge pclk) begin
    if(iamrdy && other_ch0_rdy && other_ch1_rdy) begin
      case (sdata) 
        CTRLTOKEN0: begin
          c0 <=#1 1'b0;
          c1 <=#1 1'b0;
          de <=#1 1'b0;
           dgb <= #1 1'b0;
	   vgb <= #1 1'b0;
	   ctl_vld <= #1 1'b1;
        end

        CTRLTOKEN1: begin
          c0 <=#1 1'b1;
          c1 <=#1 1'b0;
          de <=#1 1'b0;
           dgb <= #1 1'b0;
	   vgb <= #1 1'b0;
	   ctl_vld <= #1 1'b1;
        end

        CTRLTOKEN2: begin
          c0 <=#1 1'b0;
          c1 <=#1 1'b1;
          de <=#1 1'b0;
           dgb <= #1 1'b0;
	   vgb <= #1 1'b0;
	   ctl_vld <= #1 1'b1;
        end
        
        CTRLTOKEN3: begin
          c0 <=#1 1'b1;
          c1 <=#1 1'b1;
          de <=#1 1'b0;
           dgb <= #1 1'b0;
	   vgb <= #1 1'b0;
	   ctl_vld <= #1 1'b1;
        end

	DATA_GB: begin
	   c0 <=#1 1'b0;
	   c1 <=#1 1'b0;
	   de <=#1 1'b0;
           dgb <= #1 1'b1;
	   vgb <= #1 1'b0;
	   ctl_vld <= #1 1'b0;
	end

	VID_R_GB: begin
	   c0 <=#1 1'b0;
	   c1 <=#1 1'b0;
	   de <=#1 1'b0;
           dgb <= #1 1'b0;
	   vgb <= #1 1'b1;
	   ctl_vld <= #1 1'b0;
	end
        
        default: begin 
          dout[0] <=#1 data[0];
          dout[1] <=#1 (sdata[8]) ? (data[1] ^ data[0]) : (data[1] ~^ data[0]);
          dout[2] <=#1 (sdata[8]) ? (data[2] ^ data[1]) : (data[2] ~^ data[1]);
          dout[3] <=#1 (sdata[8]) ? (data[3] ^ data[2]) : (data[3] ~^ data[2]);
          dout[4] <=#1 (sdata[8]) ? (data[4] ^ data[3]) : (data[4] ~^ data[3]);
          dout[5] <=#1 (sdata[8]) ? (data[5] ^ data[4]) : (data[5] ~^ data[4]);
          dout[6] <=#1 (sdata[8]) ? (data[6] ^ data[5]) : (data[6] ~^ data[5]);
          dout[7] <=#1 (sdata[8]) ? (data[7] ^ data[6]) : (data[7] ~^ data[6]);

          de <=#1 1'b1;

           dgb <= #1 1'b0;
	   vgb <= #1 1'b0;
	   ctl_vld <= #1 1'b0;
        end                                                                      
      endcase                                                                    

      sdout <=#1 sdata;
    end else begin
      c0 <= 1'b0;
      c1 <= 1'b0;
      de <= 1'b0;
      dout <= 8'h0;
      sdout <= 10'h0;

       dgb <= 1'b0;
       vgb <= 1'b0;
       ctl_vld <= 1'b0;
    end
  end
endmodule
