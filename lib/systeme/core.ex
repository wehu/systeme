defmodule Systeme.Core do

  require Systeme.Signal

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
      def unquote(n)(name, master_pid) do
        spawn_link(fn ->
          Process.put(:systeme_thread_name, name)
          receive do
            {:pids, pids} -> Process.put(:systeme_pids, pids)
          end
          Systeme.Core.set_current_time(0)
          unquote(body)
          send(master_pid, :finished)
          Systeme.Signal.remove_thread(self)
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
      def unquote(n)(name, master_pid, max_time) do
        f = fn(_f) ->
          Systeme.Core.wait(unquote(es))
          unquote(body)
          if Systeme.Core.current_time() <= max_time do
            _f.(_f)
          end
        end
        spawn_link(fn ->
          Process.put(:systeme_thread_name, name)
          receive do
            {:pids, pids} -> Process.put(:systeme_pids, pids)
          end
          Systeme.Core.set_current_time(0)
          f.(f)
          send(master_pid, :finished)
          Systeme.Signal.remove_thread(self)
        end)
      end
    end
  end

  def current_time() do
    Process.get(:sim_time)
  end

  def set_current_time(t \\ 0) do
    ot = current_time()
    Process.put(:sim_time, t)
    if ot < t do
      Systeme.Signal.update_thread_time(self, t)
    end
  end

  def name() do
    Process.get(:systeme_thread_name)
  end

  def wait(es) when is_list(es) do
    #Enum.each(es, fn(e) ->
    #  :gproc.reg({:p, :l, e})
    #end)
    te = Enum.find(es, fn(e) ->
      case e do
        {:time, _} -> true
        _ -> false
      end
    end)
    if te do
      if length(es) > 1 do
        throw("Attempt to mix simultion time with events")
      end
      {_, t} = te
      set_current_time(t)
    else
      wait_loop(es, current_time())
    end
    #Enum.each(es, fn(e) ->
    #   :gproc.unreg({:p, :l, e})
    #end)
    wait_flush(current_time())
  end
  def wait(e) do
    wait([e])
  end

  defp wait_loop(es, ct) do
    receive do
      {e, t} ->
        if Enum.find(es, fn(ne) -> ne == e end) do
          if t >= ct do
            set_current_time(t)
          else
            wait_loop(es, ct)
          end
        else
          wait_loop(es, ct)
        end
    end
  end

  defp wait_flush(ct) do
    receive do
      {_, t} when t <= ct -> wait_flush(ct)
    after 0 ->
    end
  end

  def notify(e) do
    pids = Process.get(:systeme_pids)
    #send(:systeme_simulate_thread, {:active, pids}) #:gproc.lookup_pids({:p, :l, e})})
    Enum.each(pids, fn(pid)->
      send(pid, {e, current_time()})
    end)
    #:gproc.send({:p, :l, e}, {e, current_time()})
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
    Systeme.Signal.read(s)
  end

  def write_signal(s, v) do
    Systeme.Signal.write(s, v)
    notify(signal(s))
  end

  def info(msg) do
    IO.puts "[SE #{current_time()} #{name()} I]: #{msg}"
  end

  def warn(msg) do
    IO.puts "[SE #{current_time()} #{name()} W]: #{msg}"
  end

  def debug(msg) do
    IO.puts "[SE #{current_time()} #{name()} D]: #{msg}"
  end

  def error(msg) do
    IO.puts "[SE #{current_time()} #{name()} E]: #{msg}"
  end

  def run_initial() do
    __all_systeme_threads__("initial") |> Enum.map(fn({mod, name}) ->
      apply(mod, name, [name, self])
    end)
  end
  
  def run_always(max_time) do
    __all_systeme_threads__("always") |> Enum.map(fn({mod, name}) ->
      apply(mod, name, [name, self, max_time])
    end)
  end

  defp threads_terminated(size) when size > 0 do
    receive do
      :finished -> threads_terminated(size - 1)
    end
  end
  defp threads_terminated(0) do
  end

  def run(max_time) do
    IO.puts "Systeme simulator start"
    Systeme.Signal.start()
    #:application.start(:gproc)
    initials = run_initial()
    always   = run_always(max_time)
    pids = initials ++ always
    Systeme.Signal.start_trace_signals(pids)
    Enum.each(pids, fn(pid) ->
      send(pid, {:pids, pids})
    end)
    threads_terminated(length(pids))
    Systeme.Signal.finish()
    IO.puts "Simulation finished"
  end

  def start_link() do
    pid = spawn_link(__MODULE__, :run, [100])
    {:ok, pid}
  end

end
