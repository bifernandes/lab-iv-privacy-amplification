# ModelSim/Questa Altera — script de compilacao e simulacao para US1
# Execucao (a partir de src/tb_pipeline/):
#   vsim -do sim_compression.do

quietly set ROOT [file join [file dirname [info script]] ..]

# Garante diretorio de saida
file mkdir sim

# Biblioteca de trabalho
vlib work

# Compilacao (ordem: dependencias antes de quem depende)
vlog $ROOT/hash_engine.v
vlog $ROOT/compression_unit.v
vlog $ROOT/dual_port_ram/dual_port_ram.v
vlog tb_compression_ram.v

# Simulacao
vsim -L altera_mf_ver work.tb_compression_ram

# Adiciona sinais ao waveform (opcional — util em modo interativo)
add wave -divider "Clock/Reset"
add wave /tb_compression_ram/clock
add wave /tb_compression_ram/reset
add wave /tb_compression_ram/start
add wave -divider "Compression Unit"
add wave /tb_compression_ram/compunit_busy
add wave /tb_compression_ram/compunit_done
add wave /tb_compression_ram/wr_addr
add wave /tb_compression_ram/wr_data
add wave /tb_compression_ram/wr_enable
add wave -divider "RAM Porta B"
add wave /tb_compression_ram/rd_addr
add wave /tb_compression_ram/rd_enable
add wave /tb_compression_ram/ram_q

run -all
quit
