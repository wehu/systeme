defmodule Systeme.Signals do

  def start() do
    :ets.new(:systeme_signals, [:set, :named_table, :public, {:write_concurrency, true}, {:read_concurrency, true}])
  end

  def read(name) do
    [{_, v}] = :ets.lookup(:systeme_signals, name)
    v
  end

  def write(name, value) do
    :ets.insert(:systeme_signals, {name, value})
  end

end
