defmodule SystemeTest do
  use ExUnit.Case
  use Systeme.Core

  initial do
   write_signal(:clk, 0)
   info "a"
  end
  initial do
   write_signal(:aaa, 1)
   info "b"
   wait(time(1))
   info "c"
   info read_signal(:aaa)
   wait(time(50))
   finish()
  end

  always(time(1)) do
    clk = read_signal(:clk)
    write_signal(:clk, (if clk == 1, do: 0, else: 1))
    notify(event(:aaa))
  end

  Enum.each(1..10, fn(_) ->
  always(signal(:clk)) do
    info read_signal(:clk)
  end
  always(event(:aaa)) do
    info "bbb"
  end
  end)

  always(signal(:aaa)) do
    info read_signal(:aaa)
  end

  test "the truth" do
    run
    assert(true)
  end
end
