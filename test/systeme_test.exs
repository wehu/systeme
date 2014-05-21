defmodule SystemeTest do
  use ExUnit.Case
  use Systeme.Core

  initial(output: [signal(:bbb)]) do
   write_signal(:bbb, 0)
   info "a"
   wait(time(2))
   write_signal(:bbb, 1)
  end
  initial(output: signal(:aaa)) do
   write_signal(:aaa, 1)
   info "b"
   wait(time(1))
   info "c"
   info read_signal(:aaa)
   wait(time(10))
  end

  always(on: time(1), output: [signal(:clk), event(:aaa), event(:bbb)]) do
    clk = read_signal(:clk, 0)
    write_signal(:clk, (if clk == 1, do: 0, else: 1))
    notify(event(:aaa))
    if clk == 0 do
      notify(event(:bbb))
    end
  end

  Enum.each(1..100, fn(_)->
  always(on: signal(:clk)) do
    info read_signal(:clk)
  end
  always(on: event(:aaa)) do
    info "aaa"
  end
  end)
  always(on: [event(:aaa), event(:bbb)], output: [event(:ccc)]) do
    info "bbb"
    wait(time(2))
    notify(event(:ccc))
  end
  always(on: event(:ccc)) do
    info "ccc"
  end

  always(on: signal(:aaa)) do
    info "aaaaa"
    info read_signal(:aaa)
  end
  always(on: [signal(:bbb), signal(:aaa)]) do
    info "bbbbb"
    info read_signal(:aaa)
  end

  test "the truth" do
    run(10000)
    assert(true)
  end
end
