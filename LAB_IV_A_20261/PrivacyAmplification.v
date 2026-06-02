// Copyright (C) 2018  Intel Corporation. All rights reserved.
// Your use of Intel Corporation's design tools, logic functions 
// and other software and tools, and its AMPP partner logic 
// functions, and any output files from any of the foregoing 
// (including device programming or simulation files), and any 
// associated documentation or information are expressly subject 
// to the terms and conditions of the Intel Program License 
// Subscription Agreement, the Intel Quartus Prime License Agreement,
// the Intel FPGA IP License Agreement, or other applicable license
// agreement, including, without limitation, that your use is for
// the sole purpose of programming logic devices manufactured by
// Intel and sold by Intel or its authorized distributors.  Please
// refer to the applicable agreement for further details.

// PROGRAM		"Quartus Prime"
// VERSION		"Version 18.1.0 Build 625 09/12/2018 SJ Lite Edition"
// CREATED		"Mon May 25 18:39:49 2026"

module PrivacyAmplification(
	cu_busy,
	cu_done,
	clk,
	rst,
	rst_soft,
	enable,
	secret_ready,
	cu_wren_a,
	cu_rden_b,
	cu_addr,
	cu_ram_addr_a,
	cu_ram_data_a,
	secret_bit,
	secret_valid,
	busy,
	done,
	error
);


input wire	cu_busy;
input wire	cu_done;
input wire	clk;
input wire	rst;
input wire	rst_soft;
input wire	enable;
input wire	secret_ready;
input wire	cu_wren_a;
input wire	cu_rden_b;
input wire	[16:0] cu_addr;
input wire	[16:0] cu_ram_addr_a;
input wire	[0:0] cu_ram_data_a;
output wire	secret_bit;
output wire	secret_valid;
output wire	busy;
output wire	done;
output wire	error;

wire	SYNTHESIZED_WIRE_0;
wire	[16:0] SYNTHESIZED_WIRE_1;
wire	SYNTHESIZED_WIRE_2;
wire	[16:0] SYNTHESIZED_WIRE_3;
wire	[0:0] SYNTHESIZED_WIRE_4;





RamMux	b2v_inst(
	.cu_rden(cu_rden_b),
	.oi_rden(SYNTHESIZED_WIRE_0),
	.cu_busy(cu_busy),
	.cu_done(cu_done),
	.cu_addr(cu_addr),
	.oi_addr(SYNTHESIZED_WIRE_1),
	.ram_rden(SYNTHESIZED_WIRE_2),
	.ram_addr(SYNTHESIZED_WIRE_3));
	defparam	b2v_inst.RAM_ADDR_WIDTH = 17;


RAM_OUT	b2v_inst1(
	.wren(cu_wren_a),
	.rden(SYNTHESIZED_WIRE_2),
	.clock(clk),
	.data(cu_ram_data_a),
	.rdaddress(SYNTHESIZED_WIRE_3),
	.wraddress(cu_ram_addr_a),
	.q(SYNTHESIZED_WIRE_4));


OutputInterface	b2v_inst2(
	.clk(clk),
	.rst(rst),
	.rst_soft(rst_soft),
	.enable(enable),
	.secret_ready(secret_ready),
	.ram_data(SYNTHESIZED_WIRE_4),
	.secret_bit(secret_bit),
	.secret_valid(secret_valid),
	.ram_rden(SYNTHESIZED_WIRE_0),
	.busy(busy),
	.done(done),
	.error(error),
	.ram_addr(SYNTHESIZED_WIRE_1));
	defparam	b2v_inst2.L = 100000;
	defparam	b2v_inst2.RAM_ADDR_WIDTH = 17;


endmodule
