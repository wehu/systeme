defmodule Systeme.Signals do

  def start() do
    :ets.new(:systeme_signals, [:set, :named_table, :public, {:write_concurrency, true}, {:read_concurrency, true}])
  end

  def read(name) do
    ct = Systeme.Core.current_time()
    :ets.match(:systeme_signals, {{name, :'$1'}, :'$2'}) |>
    Enum.sort(fn([t1, _], [t2, _])-> t1 <= t2 end) |>
    Enum.reduce(nil, fn([t, v], acc)-> if t <= ct, do: v, else: acc; end)
  end

  def write(name, value) do
    ct = Systeme.Core.current_time()
    :ets.insert(:systeme_signals, {{name, ct}, value})
  end

  #def remove_old_signals(ct) do
  #  :ets.match(:systeme_signals, :'$1') |>
  #  Enum.each(fn([k = {_, t}])->
  #    if t <= ct do
  #      :ets.delete(:systeme_signals, k)
  #    end
  #  end)
  #end

end
