defmodule Systeme.Core do

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
          Systeme.Core.inactive_thread()
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
    wait_flush(current_time())
    Enum.each(es, fn(e) ->
       :gproc.unreg({:p, :l, e})
    end)
    active_thread()
  end
  def wait(e) do
    wait([e])
  end

  defp wait_loop(es) do
    receive do
      :finish -> exit(:normal)
      {e, t} ->
        if Enum.find(es, fn(ne) -> ne == e; end) do
          if t > current_time() do
            set_current_time(t)
          end
        else
          wait_loop(es)
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

  def run_simulate() do
    size = length(__all_systeme_threads__)
    spawn_link(__MODULE__, :simulate, [size]) |> Process.register(:simulate_thread)
  end

  def simulate(size, ths \\ [], ts \\ []) do
    receive do
      :finish -> simulate_terminate(size, ths, ts)
      {:inactive, pid} ->
        ths = Enum.uniq([pid | ths])
        if length(ths) == size do
          if length(ts) > 0 do
            simulate(size, ths, notify_time(ts))
          else
            simulate(size, ths, ts)
          end
        else
          simulate(size, ths, ts)
        end
      {:active, pid} ->
        ths = List.delete(ths, pid)
        simulate(size, ths, ts)
      {:time, t} ->
        simulate(size, ths, Enum.uniq([t|ts]) |> Enum.sort)
      _ -> simulate(size, ths, ts)
    end
  end

  def simulate_terminate(size, ths \\ [], ts \\ []) do
    receive do
      {:inactive, pid} ->
        ths = Enum.uniq([pid | ths])
        if length(ths) == size do
          Enum.each(ths, fn(th)-> send(th, :finish) end)
          send(:main_thread, :finish_ok)
          exit(:normal)
        else
          simulate_terminate(size, ths, ts)
        end
      _ -> simulate_terminate(size, ths, ts)
    end
  end

  defp add_time(t) do
    send(:simulate_thread, {:time, t})
  end

  defp notify_time(ts) do
    [t|ts] = ts
    set_current_time(t)
    notify({:time, t})
    ts
  end

  def info(msg) do
    IO.puts "[SE #{current_time()} I]: #{msg}"
  end

  def active_thread() do
    send(:simulate_thread, {:active, self})
  end

  def inactive_thread() do
    send(:simulate_thread, {:inactive, self})
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
    Process.register(self, :main_thread)
    :application.start(:gproc)
    run_simulate()
    run_initial()
    run_always()
    receive do
      :finish -> send(:simulate_thread, :finish)
    end
    receive do
      :finish_ok -> 
    end
  end

  def finish() do
    send(:main_thread, :finish)
  end

end
