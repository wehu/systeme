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
   wait(time(10))
  end

  always(time(1)) do
    clk = read_signal(:clk)
    write_signal(:clk, (if clk == 1, do: 0, else: 1))
    notify(event(:aaa))
    if clk == 0 do
      notify(event(:bbb))
    end
  end

  Enum.each(1..3, fn(_) ->
    always(signal(:clk)) do
      info read_signal(:clk)
    end
    always(event(:aaa)) do
      info "aaa"
    end
    always(event(:bbb)) do
      info "bbb"
      wait(time(2))
      notify(event(:ccc))
    end
    always(event(:ccc)) do
      info "ccc"
    end
  end)

  #always(signal(:aaa)) do
  #  info read_signal(:aaa)
  #end

  test "the truth" do
    run(100)
    assert(true)
  end
end
