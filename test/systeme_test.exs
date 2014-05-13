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
    IO.inspect SystemeTest.__systeme_threads__
    IO.inspect Systeme.Core.__systeme_modules__
    IO.inspect Systeme.Core.__all_systeme_threads__
    Systeme.Core.run
    assert(true)
  end
end
