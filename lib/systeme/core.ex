defmodule Systeme.Core do

  require Systeme.Signals

  defmacro __using__(_) do
    quote do
      unless Module.get_attribute(__MODULE__, :systeme_threads) do
        Module.register_attribute(__MODULE__, :systeme_threads, accumulate: true, persist: true)
        @before_compile Systeme.Core
        @on_definition  Systeme.Core
      end
      import Systeme.Core
    end
  end

  def __on_definition__(env, kind, name, _args, _guards, _body) do
    if kind == :def and is_systeme_thread_name?(atom_to_list(name)) do
      mod  = env.module
      Module.put_attribute(mod, :systeme_threads, {mod, name})
    end
  end

  defmacro __before_compile__(_) do
    quote bind_quoted: binding do
      ths = Module.get_attribute(__MODULE__, :systeme_threads)
      def __systeme_threads__() do
        unquote(ths)
      end
    end
  end

  def __systeme_modules__() do
    Enum.reduce :code.all_loaded, [], fn({mod, _}, acc) ->
      r = try do
            if length(apply(mod, :__systeme_threads__, [])) > 0, do: true, else: false
          rescue
            _ -> false
          catch
            _ -> false
          end
      if r, do: [mod | acc], else: acc
    end 
  end

  def __all_systeme_threads__() do
    Enum.reduce :code.all_loaded, [], fn({mod, _}, acc) ->
      try do
        apply(mod, :__systeme_threads__, []) ++ acc
      rescue
        _ -> acc
      catch
        _ -> acc
      end
    end
  end
  def __all_systeme_threads__(type) do
    __all_systeme_threads__ |> Enum.filter(fn({_, name})->
       pre = "systeme_thread__" <> type
       String.slice(atom_to_binary(name), 0, String.length(pre)) == pre
    end)
  end

  defp is_systeme_thread_name?('systeme_thread__' ++ _), do: true
  defp is_systeme_thread_name?(_), do: false

  defmacro initial(do: body) do
    body = Macro.escape(body)
    quote bind_quoted: binding do
      id = length(Module.get_attribute(__MODULE__, :systeme_threads))
      n = :"systeme_thread__initial_#{id}"
      def unquote(n)() do
        spawn_link(fn ->
          Systeme.Core.set_current_time()
          Systeme.Core.active_thread()
          unquote(body)
    #      set_current_time(nil)
          Systeme.Core.inactive_thread()
          receive do
            :finish ->
              send(:systeme_simulate_thread, :finished)
              exit(:normal)
          end
        end)
      end
    end 
  end

  defmacro always(es, do: body) do
    body = Macro.escape(body)
    es = Macro.escape(es)
    quote bind_quoted: binding do
      id = length(Module.get_attribute(__MODULE__, :systeme_threads))
      n = :"systeme_thread__always_#{id}"
      def unquote(n)() do
        f = fn(_f) ->
          Systeme.Core.wait(unquote(es))
          unquote(body)
          _f.(_f)
        end
        spawn_link(fn ->
          Systeme.Core.set_current_time()
          Systeme.Core.active_thread()
          f.(f)
          Systeme.Core.inactive_thread()
          receive do
            :finish ->
              send(:systeme_simulate_thread, :finished)
              exit(:normal)
          end
        end)
      end
    end
  end

  def current_time() do
    Process.get(:sim_time)
  end

  def set_current_time(t \\ 0) do
    Process.put(:sim_time, t)
  end

  def wait(es) when is_list(es) do
    Enum.each(es, fn(e) ->
       case e do
         {:time, t} -> add_time(t)
         _ ->
       end
       :gproc.reg({:p, :l, e})
    end)
    inactive_thread()
    wait_loop(es)
    Enum.each(es, fn(e) ->
       :gproc.unreg({:p, :l, e})
    end)
    active_thread()
    wait_flush(current_time())
  end
  def wait(e) do
    wait([e])
  end

  defp wait_loop(es) do
    receive do
      :finish ->
         send(:systeme_simulate_thread, :finished)
         exit(:normal)
    after 0 ->
      receive do
        {e, t} ->
          if Enum.find(es, fn(ne) -> ne == e and t >= current_time() end) do
            if t > current_time() do
              set_current_time(t)
            end
          else
            wait_loop(es)
          end
        :finish ->
          send(:systeme_simulate_thread, :finished)
          exit(:normal)
      end
    end
  end

  defp wait_flush(t) do
    receive do
      {_, nt} -> if nt <= t, do: wait_flush(t)
    after 0 ->
    end
  end

  def notify(e) do
    send(:systeme_simulate_thread, {:active, :gproc.lookup_pids({:p, :l, e})})
    :gproc.send({:p, :l, e}, {e, current_time()})
  end

  defmacro event(n) do
    quote do
      {:event, unquote(n)}
    end
  end

  defmacro signal(n) do
    quote do
      {:signal, unquote(n)}
    end
  end

  defmacro time(n) do
    quote do
      {:time, current_time() + unquote(n)}
    end
  end

  def read_signal(s) do
    Systeme.Signals.read(s)
  end

  def write_signal(s, v) do
    Systeme.Signals.write(s, v)
    notify(signal(s))
  end

  def run_simulate() do
    size = length(__all_systeme_threads__)
    spawn_link(__MODULE__, :simulate, [size]) |> Process.register(:systeme_simulate_thread)
  end

  def simulate(size, ths \\ HashDict.new(), ts \\ HashDict.new()) do
    ts = simulate_collect_time(ts)
    receive do
      :finish -> simulate_terminate(size, ths)
      {:time, t} ->
        simulate(size, ths, Dict.put(ts, t, t))
      {:active, pids} ->
        if !is_list(pids) do
          pids = [pids]
        end
        ths = Enum.reduce(pids, ths, fn(pid, acc) ->
          Dict.delete(ths, pid)
        end)
        simulate(size, ths, ts)
      {:inactive, pid, t} ->
        ths = Dict.put(ths, pid, t)
        if Dict.size(ths) == size do
          if Dict.size(ts) > 0 do
            receive do
              :finish -> simulate_terminate(size, ths)
              {:time, t} ->
                simulate(size, ths, Dict.put(ts, t, t))
              {:active, pids} ->
                if !is_list(pids) do
                  pids = [pids]
                end
                ths = Enum.reduce(pids, ths, fn(pid, acc) ->
                  Dict.delete(ths, pid)
                end)
                simulate(size, ths, ts)
            after 0 ->
              #if all_threads_waiting?(ths) do
                #ct = Enum.reduce(ths, nil, fn({_, t}, acc)->
                #  if t == nil do
                #    acc
                #  else
                #    if acc == nil or t < acc, do: t, else: acc
                #  end
                #end)
                #IO.puts ct
                #Systeme.Signal.remove_old_signals(ct)
                simulate(size, ths, notify_time(ts))
              #else
              #  simulate(size, ths, ts)
              #end
            end
          else
            simulate(size, ths, ts)
          end
        else
          simulate(size, ths, ts)
        end
      _ -> exit(:abnormal) #IO.inspect e; simulate(size, ths, ts)
    end
  end

  defp simulate_collect_time(ts) do
    receive do
      {:time, t} ->
        simulate_collect_time(Dict.put(ts, t, t))
    after 0 ->
      ts
    end
  end

  defp simulate_terminate(size, ths) do
    receive do
      {:inactive, pid, t} ->
        ths = Dict.put(ths, pid, t)
        if Dict.size(ths) == size do
          Enum.each(Dict.keys(ths), fn(th)-> send(th, :finish) end)
          threads_terminate(size)
          send(:systeme_main_thread, :finished)
          exit(:normal)
        else
          simulate_terminate(size, ths)
        end
      _ -> simulate_terminate(size, ths)
   after 5 ->
      send(:systeme_main_thread, :finished)
    #  exit(:abnormal)
    end
  end

  defp threads_terminate(size) when size > 0 do
    receive do

      :finished -> threads_terminate(size - 1)
    end
  end
  defp threads_terminate(0) do
  end

  #defp all_threads_waiting?(ths) do
  #  Enum.reduce(ths, true, fn(th, acc)->
  #    {_, stat} = :erlang.process_info(th, :status)
  #    if stat != :waiting, do: false, else: acc
  #  end)
  #end

  defp add_time(t) do
    send(:systeme_simulate_thread, {:time, t})
  end

  defp notify_time(ts) do
    t = Dict.keys(ts) |> Enum.sort |> List.first
    ts = Dict.delete(ts, t)
    set_current_time(t)
    notify({:time, t})
    ts
  end

  def info(msg) do
    IO.puts "[SE #{current_time()} I]: #{msg}"
  end

  def warn(msg) do
    IO.puts "[SE #{current_time()} W]: #{msg}"
  end

  def debug(msg) do
    IO.puts "[SE #{current_time()} D]: #{msg}"
  end

  def error(msg) do
    IO.puts "[SE #{current_time()} E]: #{msg}"
  end

  def active_thread() do
    send(:systeme_simulate_thread, {:active, self})
  end

  def inactive_thread() do
    send(:systeme_simulate_thread, {:inactive, self, current_time()})
  end

  def run_initial() do
    __all_systeme_threads__("initial") |> Enum.each(fn({mod, name}) ->
      apply(mod, name, [])
    end)
  end
  
  def run_always() do
    __all_systeme_threads__("always") |> Enum.each(fn({mod, name}) ->
      apply(mod, name, [])
    end)
  end

  def run() do
    IO.puts "Systeme simulator start"
    Process.register(self, :systeme_main_thread)
    Systeme.Signals.start()
    :application.start(:gproc)
    run_simulate()
    run_initial()
    run_always()
    receive do
      :finish -> send(:systeme_simulate_thread, :finish)
    end
    receive do
      :finished -> 
    end
    IO.puts "Simulation finished"
  end

  def start_link() do
    pid = spawn_link(&run/0)
    {:ok, pid}
  end

  def finish() do
    send(:systeme_main_thread, :finish)
  end

end
