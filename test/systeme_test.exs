defmodule SystemeTest do
  use ExUnit.Case
  use Systeme.Core

  initial do
   info "a"
  end
  initial do
   info "b"
   wait(time(1))
   info "c"
   write_signal(:aaa, 1)
   info read_signal(:aaa)
   wait(time(3))
   finish()
  end

  always(time(1)) do
    notify(event(:a))
    info "aaa"
  end

  always(event(:a)) do
    info "bbb"
  end

  test "the truth" do
    run
    assert(true)
  end
end
