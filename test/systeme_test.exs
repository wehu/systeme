defmodule SystemeTest do
  use ExUnit.Case
  use Systeme.Core

  initial(output: [signal(:data_in_0),
                   signal(:data_in_1),
                   signal(:data_in_2),
                   signal(:data_in_3),
                   signal(:data_in_4),
                   signal(:data_in_5),
                   signal(:data_in_6),
                   signal(:data_in_7)]) do
    write_signal(:data_in_0, 1)
    write_signal(:data_in_1, 0)
    write_signal(:data_in_2, 0)
    write_signal(:data_in_3, 0)
    write_signal(:data_in_4, 0)
    write_signal(:data_in_5, 0)
    write_signal(:data_in_6, 0)
    write_signal(:data_in_7, 0)
  end

  always(on: time(3), output: signal(:clk)) do
    clk = read_signal(:clk, 0)
    write_signal(:clk, (if clk == 1, do: 0, else: 1))
  end

  always(on: signal(:clk),
         output: [signal(:crc_reg_0),
                  signal(:crc_reg_1),
                  signal(:crc_reg_2),
                  signal(:crc_reg_3),
                  signal(:crc_reg_4),
                  signal(:crc_reg_5),
                  signal(:crc_reg_6),
                  signal(:crc_reg_7),
                  signal(:crc_reg_8),
                  signal(:crc_reg_9),
                  signal(:crc_reg_10),
                  signal(:crc_reg_11)],
         input: [signal(:next_crc_0),
                 signal(:next_crc_1),
                 signal(:next_crc_2),
                 signal(:next_crc_3),
                 signal(:next_crc_4),
                 signal(:next_crc_5),
                 signal(:next_crc_6),
                 signal(:next_crc_7),
                 signal(:next_crc_8),
                 signal(:next_crc_9),
                 signal(:next_crc_10),
                 signal(:next_crc_11)]) do
    next_crc_0 = read_signal(:next_crc_0, 1)
    next_crc_1 = read_signal(:next_crc_1, 1)
    next_crc_2 = read_signal(:next_crc_2, 1)
    next_crc_3 = read_signal(:next_crc_3, 1)
    next_crc_4 = read_signal(:next_crc_4, 1)
    next_crc_5 = read_signal(:next_crc_5, 1)
    next_crc_6 = read_signal(:next_crc_6, 1)
    next_crc_7 = read_signal(:next_crc_7, 1)
    next_crc_8 = read_signal(:next_crc_8, 1)
    next_crc_9 = read_signal(:next_crc_9, 1)
    next_crc_10 = read_signal(:next_crc_10, 1)
    next_crc_11 = read_signal(:next_crc_11, 1)
    write_signal(:crc_reg_0, next_crc_0)
    write_signal(:crc_reg_1, next_crc_1)
    write_signal(:crc_reg_2, next_crc_2)
    write_signal(:crc_reg_3, next_crc_3)
    write_signal(:crc_reg_4, next_crc_4)
    write_signal(:crc_reg_5, next_crc_5)
    write_signal(:crc_reg_6, next_crc_6)
    write_signal(:crc_reg_7, next_crc_7)
    write_signal(:crc_reg_8, next_crc_8)
    write_signal(:crc_reg_9, next_crc_9)
    write_signal(:crc_reg_10, next_crc_10)
    write_signal(:crc_reg_11, next_crc_11)
  end

  always(on: [signal(:crc_reg_4), signal(:crc_reg_11), signal(:data_in_0), signal(:data_in_7)],
      output: [signal(:next_crc_0)]) do
    data = :erlang.bxor read_signal(:crc_reg_4, 1), read_signal(:crc_reg_11, 1)
    data = :erlang.bxor data, read_signal(:data_in_0)
    data = :erlang.bxor data, read_signal(:data_in_7)
    write_signal(:next_crc_0, data)
  end

  always(on: [signal(:crc_reg_5), signal(:data_in_1)],
      output: [signal(:next_crc_1)]) do
    data = :erlang.bxor read_signal(:crc_reg_5, 1), read_signal(:data_in_1)
    write_signal(:next_crc_1, data)
  end

  always(on: [signal(:crc_reg_6), signal(:data_in_2)],
      output: [signal(:next_crc_2)]) do
    data = :erlang.bxor read_signal(:crc_reg_6, 1), read_signal(:data_in_2)
    write_signal(:next_crc_2, data)
  end

  always(on: [signal(:crc_reg_7), signal(:data_in_3)],
      output: [signal(:next_crc_3)]) do
    data = :erlang.bxor read_signal(:crc_reg_7, 1), read_signal(:data_in_3)
    write_signal(:next_crc_3, data)
  end

  always(on: [signal(:crc_reg_8), signal(:data_in_4)],
      output: [signal(:next_crc_4)]) do
    data = :erlang.bxor read_signal(:crc_reg_8, 1), read_signal(:data_in_4)
    write_signal(:next_crc_4, data)
  end

  always(on: [signal(:crc_reg_4), signal(:crc_reg_9), signal(:crc_reg_11), signal(:data_in_0), signal(:data_in_5), signal(:data_in_7)],
      output: [signal(:next_crc_5)]) do
    data = :erlang.bxor read_signal(:crc_reg_4, 1), read_signal(:crc_reg_9, 1)
    data = :erlang.bxor data, read_signal(:crc_reg_11, 1)
    data = :erlang.bxor data, read_signal(:data_in_0)
    data = :erlang.bxor data, read_signal(:data_in_5)
    data = :erlang.bxor data, read_signal(:data_in_7)
    write_signal(:next_crc_5, data)
  end

  always(on: [signal(:crc_reg_5), signal(:crc_reg_10), signal(:data_in_1), signal(:data_in_6)],
      output: [signal(:next_crc_6)]) do
    data = :erlang.bxor read_signal(:crc_reg_5, 1), read_signal(:crc_reg_10, 1)
    data = :erlang.bxor data, read_signal(:data_in_1)
    data = :erlang.bxor data, read_signal(:data_in_6)
    write_signal(:next_crc_6, data)
  end

  always(on: [signal(:crc_reg_6), signal(:crc_reg_11), signal(:data_in_2), signal(:data_in_7)],
      output: [signal(:next_crc_7)]) do
    data = :erlang.bxor read_signal(:crc_reg_6, 1), read_signal(:crc_reg_11, 1)
    data = :erlang.bxor data, read_signal(:data_in_2)
    data = :erlang.bxor data, read_signal(:data_in_7)
    write_signal(:next_crc_7, data)
  end

  always(on: [signal(:crc_reg_0), signal(:crc_reg_7), signal(:data_in_3)],
      output: [signal(:next_crc_8)]) do
    data = :erlang.bxor read_signal(:crc_reg_0, 1), read_signal(:crc_reg_7, 1)
    data = :erlang.bxor data, read_signal(:data_in_3)
    write_signal(:next_crc_8, data)
  end

  always(on: [signal(:crc_reg_1), signal(:crc_reg_8), signal(:data_in_4)],
      output: [signal(:next_crc_9)]) do
    data = :erlang.bxor read_signal(:crc_reg_1, 1), read_signal(:crc_reg_8, 1)
    data = :erlang.bxor data, read_signal(:data_in_4)
    write_signal(:next_crc_9, data)
  end

  always(on: [signal(:crc_reg_2), signal(:crc_reg_9), signal(:data_in_5)],
      output: [signal(:next_crc_10)]) do
    data = :erlang.bxor read_signal(:crc_reg_2, 1), read_signal(:crc_reg_9, 1) 
    data = :erlang.bxor data, read_signal(:data_in_5)
    write_signal(:next_crc_10, data)
  end

  always(on: [signal(:crc_reg_3), signal(:crc_reg_10), signal(:data_in_6)],
      output: [signal(:next_crc_11)]) do
    data = :erlang.bxor read_signal(:crc_reg_3, 1), read_signal(:crc_reg_10, 1)
    data = :erlang.bxor data, read_signal(:data_in_6)
    write_signal(:next_crc_11, data)
  end

  always(on: [signal(:crc_reg_0),
              signal(:crc_reg_1),
              signal(:crc_reg_2),
              signal(:crc_reg_3),
              signal(:crc_reg_4),
              signal(:crc_reg_5),
              signal(:crc_reg_6),
              signal(:crc_reg_7),
              signal(:crc_reg_8),
              signal(:crc_reg_9),
              signal(:crc_reg_10),
              signal(:crc_reg_11)]) do
    info (read_signal(:crc_reg_0, 1) + 2 * (read_signal(:crc_reg_1, 1) +
          read_signal(:crc_reg_2, 1) + 2 * (read_signal(:crc_reg_3, 1) +
          read_signal(:crc_reg_4, 1) + 2 * (read_signal(:crc_reg_5, 1) +
          read_signal(:crc_reg_6, 1) + 2 * (read_signal(:crc_reg_7, 1) +
          read_signal(:crc_reg_8, 1) + 2 * (read_signal(:crc_reg_9, 1) +
          read_signal(:crc_reg_10, 1) + 2 * (read_signal(:crc_reg_11, 1))))))))
  end

  test "the truth" do
    run(100000, sync_interval: 100)
    assert(true)
  end
end
