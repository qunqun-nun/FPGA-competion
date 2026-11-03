//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2022.2 (win64) Build 3671981 Fri Oct 14 05:00:03 MDT 2022
//Date        : Sun Nov  1 11:33:56 2026
//Host        : DESKTOP-O21508Q running 64-bit major release  (build 9200)
//Command     : generate_target design_1_wrapper.bd
//Design      : design_1_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module design_1_wrapper
   (HDMI_LOCKED_LED,
    HDMI_TX_CLK_N_OUT,
    HDMI_TX_CLK_P_OUT,
    HDMI_TX_DAT_N_OUT,
    HDMI_TX_DAT_P_OUT,
    IDT_8T49N241_LOL_IN,
    IDT_8T49N241_RST_OUT,
    TX_DDC_OUT_scl_io,
    TX_DDC_OUT_sda_io,
    TX_EN_OUT,
    TX_HPD_IN,
    TX_REFCLK_N_IN,
    TX_REFCLK_P_IN,
    fmch_iic_scl_io,
    fmch_iic_sda_io);
  output HDMI_LOCKED_LED;
  output HDMI_TX_CLK_N_OUT;
  output HDMI_TX_CLK_P_OUT;
  output [2:0]HDMI_TX_DAT_N_OUT;
  output [2:0]HDMI_TX_DAT_P_OUT;
  input IDT_8T49N241_LOL_IN;
  output [0:0]IDT_8T49N241_RST_OUT;
  inout TX_DDC_OUT_scl_io;
  inout TX_DDC_OUT_sda_io;
  output [0:0]TX_EN_OUT;
  input TX_HPD_IN;
  input TX_REFCLK_N_IN;
  input TX_REFCLK_P_IN;
  inout fmch_iic_scl_io;
  inout fmch_iic_sda_io;

  wire HDMI_LOCKED_LED;
  wire HDMI_TX_CLK_N_OUT;
  wire HDMI_TX_CLK_P_OUT;
  wire [2:0]HDMI_TX_DAT_N_OUT;
  wire [2:0]HDMI_TX_DAT_P_OUT;
  wire IDT_8T49N241_LOL_IN;
  wire [0:0]IDT_8T49N241_RST_OUT;
  wire TX_DDC_OUT_scl_i;
  wire TX_DDC_OUT_scl_io;
  wire TX_DDC_OUT_scl_o;
  wire TX_DDC_OUT_scl_t;
  wire TX_DDC_OUT_sda_i;
  wire TX_DDC_OUT_sda_io;
  wire TX_DDC_OUT_sda_o;
  wire TX_DDC_OUT_sda_t;
  wire [0:0]TX_EN_OUT;
  wire TX_HPD_IN;
  wire TX_REFCLK_N_IN;
  wire TX_REFCLK_P_IN;
  wire fmch_iic_scl_i;
  wire fmch_iic_scl_io;
  wire fmch_iic_scl_o;
  wire fmch_iic_scl_t;
  wire fmch_iic_sda_i;
  wire fmch_iic_sda_io;
  wire fmch_iic_sda_o;
  wire fmch_iic_sda_t;

  IOBUF TX_DDC_OUT_scl_iobuf
       (.I(TX_DDC_OUT_scl_o),
        .IO(TX_DDC_OUT_scl_io),
        .O(TX_DDC_OUT_scl_i),
        .T(TX_DDC_OUT_scl_t));
  IOBUF TX_DDC_OUT_sda_iobuf
       (.I(TX_DDC_OUT_sda_o),
        .IO(TX_DDC_OUT_sda_io),
        .O(TX_DDC_OUT_sda_i),
        .T(TX_DDC_OUT_sda_t));
  design_1 design_1_i
       (.HDMI_LOCKED_LED(HDMI_LOCKED_LED),
        .HDMI_TX_CLK_N_OUT(HDMI_TX_CLK_N_OUT),
        .HDMI_TX_CLK_P_OUT(HDMI_TX_CLK_P_OUT),
        .HDMI_TX_DAT_N_OUT(HDMI_TX_DAT_N_OUT),
        .HDMI_TX_DAT_P_OUT(HDMI_TX_DAT_P_OUT),
        .IDT_8T49N241_LOL_IN(IDT_8T49N241_LOL_IN),
        .IDT_8T49N241_RST_OUT(IDT_8T49N241_RST_OUT),
        .TX_DDC_OUT_scl_i(TX_DDC_OUT_scl_i),
        .TX_DDC_OUT_scl_o(TX_DDC_OUT_scl_o),
        .TX_DDC_OUT_scl_t(TX_DDC_OUT_scl_t),
        .TX_DDC_OUT_sda_i(TX_DDC_OUT_sda_i),
        .TX_DDC_OUT_sda_o(TX_DDC_OUT_sda_o),
        .TX_DDC_OUT_sda_t(TX_DDC_OUT_sda_t),
        .TX_EN_OUT(TX_EN_OUT),
        .TX_HPD_IN(TX_HPD_IN),
        .TX_REFCLK_N_IN(TX_REFCLK_N_IN),
        .TX_REFCLK_P_IN(TX_REFCLK_P_IN),
        .fmch_iic_scl_i(fmch_iic_scl_i),
        .fmch_iic_scl_o(fmch_iic_scl_o),
        .fmch_iic_scl_t(fmch_iic_scl_t),
        .fmch_iic_sda_i(fmch_iic_sda_i),
        .fmch_iic_sda_o(fmch_iic_sda_o),
        .fmch_iic_sda_t(fmch_iic_sda_t));
  IOBUF fmch_iic_scl_iobuf
       (.I(fmch_iic_scl_o),
        .IO(fmch_iic_scl_io),
        .O(fmch_iic_scl_i),
        .T(fmch_iic_scl_t));
  IOBUF fmch_iic_sda_iobuf
       (.I(fmch_iic_sda_o),
        .IO(fmch_iic_sda_io),
        .O(fmch_iic_sda_i),
        .T(fmch_iic_sda_t));
endmodule
