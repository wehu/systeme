defmodule SystemeTest do
  use ExUnit.Case
  use Systeme.Core

  initial([signal(:bbb)]) do
   write_signal(:bbb, 0)
   info "a"
   wait(time(2))
   write_signal(:bbb, 1)
  end
  initial(signal(:aaa)) do
   write_signal(:aaa, 1)
   info "b"
   wait(time(1))
   info "c"
   info read_signal(:aaa)
   wait(time(10))
  end

  always([signal(:clk), event(:aaa), event(:bbb)], time(3)) do
    clk = read_signal(:clk, 0)
    write_signal(:clk, (if clk == 1, do: 0, else: 1))
    notify(event(:aaa))
    if clk == 0 do
      notify(event(:bbb))
    end
  end

  Enum.each(1..100, fn(_)->
  always(signal(:clk)) do
    info read_signal(:clk)
  end
  always(event(:aaa)) do
    info "aaa"
  end
  end)
  always([event(:ccc)], [event(:aaa), event(:bbb)]) do
    info "bbb"
    wait(time(2))
    notify(event(:ccc))
  end
  always(event(:ccc)) do
    info "ccc"
  end

  always(signal(:aaa)) do
    info "aaaaa"
    info read_signal(:aaa)
  end
  always([signal(:bbb), signal(:aaa)]) do
    info "bbbbb"
    info read_signal(:aaa)
  end

  test "the truth" do
    run(100)
    assert(true)
  end
end
