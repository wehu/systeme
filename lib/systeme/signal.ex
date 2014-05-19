defmodule Systeme.Signal do

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

  def trace_signals(time \\ 0, pids \\ HashDict.new) do
    ot = time
    time = Enum.reduce(Dict.keys(pids), nil, fn(pid, acc)->
      t = Dict.get(pids, pid)
      if acc == nil or t < acc, do: t, else: acc
    end)
    if ot < time do
      remove_old_signals(time)
    end
    receive do
      {:update, pid, t} ->
        pids = Dict.put(pids, pid, t)
        trace_signals(time, pids)
      {:remove, pid} ->
        pids = Dict.delete(pids, pid)
        trace_signals(time, pids)
      {:finish, ref, pid} -> send(pid, {ref, :finished})
    end
  end

  def start_trace_signals(pids \\ []) do
    pids = Enum.reduce(pids, HashDict.new, fn(pid, acc)->
      Dict.put(acc, pid, 0)
    end)
    spawn_link(__MODULE__, :trace_signals, [0, pids]) |> Process.register(:systeme_signals_thread)
  end

  def update_thread_time(pid, t) do
    send(:systeme_signals_thread, {:update, pid, t})
  end

  def remove_thread(pid) do
    send(:systeme_signals_thread, {:remove, pid})
  end

  def finish() do
    ref = make_ref()
    send(:systeme_signals_thread, {:finish, ref, self})
    receive do
      {^ref, :finished} ->
    end
  end

  defp remove_old_signals(mt) do
    :ets.match(:systeme_signals, {:'$1', :'_'}) |>
    Enum.each(fn([k = {_, t}])->
      if t < mt do
        :ets.delete(:systeme_signals, k)
      end
    end)
  end

end
