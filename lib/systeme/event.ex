defmodule Systeme.Event do

  def start() do
    :ets.new(:systeme_events, [:bag, :named_table, :public, {:write_concurrency, true}, {:read_concurrency, true}])
  end

  def register_driver(name, pid) do
    :ets.insert(:systeme_events, {{:driver, name}, pid})
  end

  def get_driver(name) do
    case :ets.lookup(:systeme_events, {:driver, name}) do
      [{_, pid}] -> pid
      _ -> nil
    end
  end

  def register_receiver(name, pid) do
    :ets.insert(:systeme_events, {{:receiver, name}, pid})
  end

  def get_receivers(name) do
    :ets.lookup(:systeme_events, {:receiver, name}) |> Enum.map(fn({_, pid}) -> pid end)
  end

  def transaction(body) do
   try do
     :ets.safe_fixtable(:systeme_events, true)
     body.()
   after
     :ets.safe_fixtable(:systeme_events, false)
   end
  end

end
