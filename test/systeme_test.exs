defmodule SystemeTest do
  use ExUnit.Case
  use Systeme.Core

  initial(output: signal(:data_in)) do
    write_signal(:data_in, 1)
  end

  always(on: time(3), output: signal(:clk)) do
    clk = read_signal(:clk, 0)
    write_signal(:clk, (if clk == 1, do: 0, else: 1))
  end

  always(on: signal(:clk), output: signal(:crc_reg),
    input: [signal(:next_crc)]) do
    next_crc = read_signal(:next_crc, 0xffff)
    write_signal(:crc_reg, next_crc)
  end

  always(on: [signal(:crc_reg), signal(:data_in)],
      output: [signal(:next_crc)]) do
    data = read_signal(:crc_reg, 0xffff) + read_signal(:data_in)
    write_signal(:next_crc, data)
  end

  always(on: signal(:crc_reg)) do
    info read_signal(:crc_reg)
  end

  test "the truth" do
    run(100, sync_interval: 100)
    assert(true)
  end
end
