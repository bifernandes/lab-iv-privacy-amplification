//========================================================================================
// File: tb_output_interface.v
// Description: Testbench de unidade do OutputInterface (RF-08).
//              Valida: caminho feliz, consumidor estagnado (stall), reset no meio
//              da operacao (rst e rst_soft) e sinalizacao de 'error' (L invalido e
//              fim inesperado). Verilog puro, compativel com ModelSim e Icarus (iverilog).
//
// Modela um RAM com latencia de leitura REGISTRADA de 2 ciclos (igual a RAM_OUT:
// address_reg_b + outdata_reg_b), para exercitar a leitura pipelinada do DUT.
// A RamMux nao e necessaria no teste de unidade (em operacao normal apenas repassa
// os sinais do OutputInterface para a RAM quando a Compression Unit ja terminou).
//========================================================================================
`timescale 1ns/1ps

module tb_output_interface;

	//------------------------------------------------------------------ parametros do teste
	localparam AW  = 5;          // RAM_ADDR_WIDTH (cap = 32 >= L)
	localparam L   = 16;         // tamanho da chave no teste
	localparam LAT = 2;          // latencia de leitura da RAM modelada

	//------------------------------------------------------------------ clock
	reg clk = 1'b0;
	always #5 clk = ~clk;        // 100 MHz

	reg rst, rst_soft, enable;

	//------------------------------------------------------------------ geracao de secret_ready
	// ready_mode = 0 -> usa ready_const ; ready_mode = 1 -> padrao com stalls
	reg       ready_mode, ready_const;
	reg [1:0] rcnt;
	always @(posedge clk) rcnt <= rcnt + 1'b1;
	wire secret_ready = ready_mode ? (rcnt != 2'b00) : ready_const;

	//------------------------------------------------------------------ DUT principal
	wire          secret_bit, secret_valid;
	wire [AW-1:0] ram_addr;
	wire          ram_rden;
	wire          ram_data;
	wire          busy, done, error;

	OutputInterface #(
		.L(L), .RAM_ADDR_WIDTH(AW), .RAM_READ_LATENCY(LAT), .FIFO_DEPTH(4)
	) dut (
		.clk(clk), .rst(rst), .rst_soft(rst_soft), .enable(enable),
		.secret_bit(secret_bit), .secret_valid(secret_valid), .secret_ready(secret_ready),
		.ram_addr(ram_addr), .ram_rden(ram_rden), .ram_data(ram_data),
		.busy(busy), .done(done), .error(error)
	);

	//------------------------------------------------------------------ modelo de RAM (latencia 2)
	reg          ram_mem [0:(1<<AW)-1];
	reg [AW-1:0] ram_addr_r;
	reg          ram_q_r;
	integer      k;

	// padrao deterministico para a memoria / golden
	function automatic bit_pat;
		input integer idx;
		begin
			bit_pat = (idx ^ (idx >> 1) ^ (idx >> 2)) & 1'b1;
		end
	endfunction

	always @(posedge clk) begin
		ram_addr_r <= ram_addr;             // estagio 1: address_reg_b
		ram_q_r    <= ram_mem[ram_addr_r];  // estagio 2: outdata_reg_b => latencia total = 2
	end
	assign ram_data = ram_q_r;

	//------------------------------------------------------------------ coletor (consumidor)
	reg     collecting;
	integer rx_cnt;
	reg     rx_data [0:255];

	always @(posedge clk) begin
		if (collecting && secret_valid && secret_ready) begin
			rx_data[rx_cnt] = secret_bit;
			rx_cnt = rx_cnt + 1;
		end
	end

	//------------------------------------------------------------------ DUTs de erro (L invalido)
	reg  err0_enable, err1_enable;
	wire err0_error, err0_busy, err1_error;
	wire dump0_sb, dump0_sv, dump0_rden, dump0_busy, dump0_done;
	wire dump1_sb, dump1_sv, dump1_rden, dump1_busy, dump1_done;
	wire [AW-1:0] dump0_addr;
	wire [3:0]    dump1_addr;

	// L = 0 -> invalido
	OutputInterface #(.L(0), .RAM_ADDR_WIDTH(AW)) dut_L0 (
		.clk(clk), .rst(rst), .rst_soft(1'b0), .enable(err0_enable),
		.secret_bit(dump0_sb), .secret_valid(dump0_sv), .secret_ready(1'b1),
		.ram_addr(dump0_addr), .ram_rden(dump0_rden), .ram_data(1'b0),
		.busy(err0_busy), .done(dump0_done), .error(err0_error)
	);

	// L = 64 > 2^4 = 16 -> invalido (nao cabe na RAM)
	OutputInterface #(.L(64), .RAM_ADDR_WIDTH(4)) dut_Lbig (
		.clk(clk), .rst(rst), .rst_soft(1'b0), .enable(err1_enable),
		.secret_bit(dump1_sb), .secret_valid(dump1_sv), .secret_ready(1'b1),
		.ram_addr(dump1_addr), .ram_rden(dump1_rden), .ram_data(1'b0),
		.busy(dump1_busy), .done(dump1_done), .error(err1_error)
	);

	//------------------------------------------------------------------ controle de teste
	integer fails = 0;

	task do_reset;
		begin
			rst = 1'b1; @(posedge clk); @(posedge clk); rst = 1'b0; @(posedge clk);
		end
	endtask

	task check_stream;
		integer j;
		begin
			if (rx_cnt !== L) begin
				$display("  [FAIL] recebidos %0d bits, esperados %0d", rx_cnt, L);
				fails = fails + 1;
			end else begin
				for (j = 0; j < L; j = j + 1)
					if (rx_data[j] !== bit_pat(j)) begin
						$display("  [FAIL] bit %0d = %b, esperado %b", j, rx_data[j], bit_pat(j));
						fails = fails + 1;
					end
			end
		end
	endtask

	// watchdog
	initial begin
		#200000;
		$display("[FAIL] watchdog: simulacao nao terminou a tempo");
		$finish;
	end

	//------------------------------------------------------------------ sequencia principal
	initial begin
		rst = 1'b0; rst_soft = 1'b0; enable = 1'b0;
		ready_mode = 1'b0; ready_const = 1'b0; rcnt = 2'b00;
		collecting = 1'b0; rx_cnt = 0; err0_enable = 1'b0; err1_enable = 1'b0;
		for (k = 0; k < (1<<AW); k = k + 1) ram_mem[k] = bit_pat(k);

		do_reset;

		//=============================================================== 1) CAMINHO FELIZ
		$display("== Teste 1: caminho feliz (secret_ready sempre alto) ==");
		rx_cnt = 0; collecting = 1'b1; ready_mode = 1'b0; ready_const = 1'b1; enable = 1'b1;
		wait (done === 1'b1);
		collecting = 1'b0;
		check_stream;
		if (error !== 1'b0) begin $display("  [FAIL] error inesperado"); fails = fails + 1; end
		if (fails == 0) $display("  [PASS] %0d bits entregues, done OK", rx_cnt);
		enable = 1'b0; wait (done === 1'b0); @(posedge clk);

		//=============================================================== 2) CONSUMIDOR ESTAGNADO
		$display("== Teste 2: consumidor estagnado (secret_ready oscilando) ==");
		do_reset;
		rx_cnt = 0; collecting = 1'b1; ready_mode = 1'b1; enable = 1'b1;
		wait (done === 1'b1);
		ready_mode = 1'b0; ready_const = 1'b1;
		collecting = 1'b0;
		check_stream;
		if (error !== 1'b0) begin $display("  [FAIL] error inesperado"); fails = fails + 1; end
		if (fails == 0) $display("  [PASS] stream integro sob stall (%0d bits)", rx_cnt);
		enable = 1'b0; wait (done === 1'b0); @(posedge clk);

		//=============================================================== 3) RESET (rst) NO MEIO
		$display("== Teste 3: reset assincrono (rst) no meio da operacao ==");
		do_reset;
		rx_cnt = 0; collecting = 1'b1; ready_mode = 1'b0; ready_const = 1'b1; enable = 1'b1;
		repeat (6) @(posedge clk);
		// Derruba enable junto com o reset para checar IDLE limpo (com enable alto o
		// modulo corretamente reiniciaria o streaming logo apos o reset).
		enable = 1'b0;
		rst = 1'b1; @(posedge clk); @(posedge clk); rst = 1'b0; @(posedge clk); #1;
		if (busy !== 1'b0 || secret_valid !== 1'b0 || done !== 1'b0 || error !== 1'b0) begin
			$display("  [FAIL] estado nao voltou a IDLE limpo apos rst");
			fails = fails + 1;
		end else $display("  [PASS] IDLE limpo apos rst");
		// recuperacao: novo stream completo (re-arma com borda de enable)
		rx_cnt = 0; enable = 1'b1;
		wait (done === 1'b1);
		collecting = 1'b0;
		check_stream;
		if (fails == 0) $display("  [PASS] recuperacao apos reset OK");
		enable = 1'b0; wait (done === 1'b0); @(posedge clk);

		//=============================================================== 3b) rst_soft NO MEIO
		$display("== Teste 3b: rst_soft no meio da operacao ==");
		rx_cnt = 0; collecting = 1'b1; ready_const = 1'b1; enable = 1'b1;
		repeat (6) @(posedge clk);
		enable = 1'b0;  // idem teste 3
		rst_soft = 1'b1; @(posedge clk); rst_soft = 1'b0; @(posedge clk); #1;
		if (busy !== 1'b0 || secret_valid !== 1'b0 || error !== 1'b0) begin
			$display("  [FAIL] rst_soft nao limpou o estado");
			fails = fails + 1;
		end else $display("  [PASS] estado limpo apos rst_soft");
		collecting = 1'b0; @(posedge clk);

		//=============================================================== 4) ERROR: L invalido
		$display("== Teste 4a: error com L = 0 ==");
		err0_enable = 1'b1;
		repeat (3) @(posedge clk);
		if (err0_error !== 1'b1)      begin $display("  [FAIL] error nao sinalizado (L=0)"); fails = fails + 1; end
		else if (err0_busy !== 1'b0)  begin $display("  [FAIL] busy alto em erro"); fails = fails + 1; end
		else $display("  [PASS] error com L=0");
		err0_enable = 1'b0;

		$display("== Teste 4b: error com L > capacidade da RAM ==");
		err1_enable = 1'b1;
		repeat (3) @(posedge clk);
		if (err1_error !== 1'b1) begin $display("  [FAIL] error nao sinalizado (L>cap)"); fails = fails + 1; end
		else $display("  [PASS] error com L>capacidade");
		err1_enable = 1'b0;

		//=============================================================== 5) ERROR: fim inesperado
		$display("== Teste 5: error por fim inesperado (enable cai no meio) ==");
		do_reset;
		rx_cnt = 0; collecting = 1'b1; ready_const = 1'b1; enable = 1'b1;
		repeat (6) @(posedge clk);   // streaming em andamento (ainda nao concluido)
		enable = 1'b0;               // derruba enable antes de done
		repeat (4) @(posedge clk);
		if (error !== 1'b1) begin $display("  [FAIL] error nao sinalizado em fim inesperado"); fails = fails + 1; end
		else $display("  [PASS] error em fim inesperado (latched)");
		collecting = 1'b0;
		// re-arme com nova borda de subida de enable
		enable = 1'b1; repeat (3) @(posedge clk); #1;
		if (error !== 1'b0) begin $display("  [FAIL] error nao re-armou apos nova requisicao"); fails = fails + 1; end
		else $display("  [PASS] error re-armado por nova borda de enable");
		enable = 1'b0; do_reset;

		//=============================================================== resultado
		$display("====================================================");
		if (fails == 0) $display("RESULTADO: TODOS OS TESTES PASSARAM");
		else            $display("RESULTADO: %0d FALHA(S)", fails);
		$display("====================================================");
		$finish;
	end

endmodule
