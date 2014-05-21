defmodule Systeme.Event do

  def start() do
    :ets.new(:systeme_events, [:set, :named_table, :public, {:write_concurrency, true}, {:read_concurrency, true}])
  end

  def register(name, pid) do
    try do
      :ets.safe_fixtable(:systeme_events, true)
      :ets.insert(:systeme_events, {name, pid})
    after
      :ets.safe_fixtable(:systeme_events, false)
    end
  end

  def get_owner(name) do
    try do
      :ets.safe_fixtable(:systeme_events, true)
      case :ets.lookup(:systeme_events, name) do
        [{_, pid}] -> pid
        _ -> nil
      end
    after
      :ets.safe_fixtable(:systeme_events, false)
    end
  end

end
