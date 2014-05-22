defmodule Systeme.Core do

  require Systeme.Event

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

  defp systeme_set_event_driver(e, pid) do
    #systeme_check_event_drivers(e, pid)
    :rpc.call(systeme_master_node(), Systeme.Event, :register_driver, [e, pid])
  end
  defp systeme_set_event_receiver(e, pid) do
    #systeme_check_event_drivers(e, pid)
    :rpc.call(systeme_master_node(), Systeme.Event, :register_receiver, [e, pid])
  end
  defp systeme_get_event_driver(e) do
    cache = Process.get(:systeme_event_driver_cache)
    unless cache do
      Process.put(:systeme_event_driver_cache, HashDict.new)
    end
    cache = Process.get(:systeme_event_driver_cache)
    if Dict.has_key?(cache, e) do
      Dict.get(cache, e)
    else
      r = :rpc.call(systeme_master_node(), Systeme.Event, :get_driver, [e])
      Process.put(:systeme_event_driver_cache, Dict.put(cache, e, r))
      r
    end
  end
  defp systeme_get_event_receivers(e) do
    cache = Process.get(:systeme_event_receivers_cache)
    unless cache do
      Process.put(:systeme_event_receivers_cache, HashDict.new)
    end
    cache = Process.get(:systeme_event_receivers_cache)
    if Dict.has_key?(cache, e) do
      Dict.get(cache, e)
    else
      r = :rpc.call(systeme_master_node(), Systeme.Event, :get_receivers, [e])
      Process.put(:systeme_event_receivers_cache, Dict.put(cache, e, r))
      r
    end
  end
  defp systeme_check_event_driver(e) do
    pid = systeme_get_event_driver(e)
    unless pid do
      throw("#{inspect(e)} has no driver")
    end
  end
  defp systeme_check_event_receiver(e) do
    unless Enum.find(Process.get(:systeme_thread_inputs), fn(ne) -> e == ne end) do
      throw("#{inspect(e)} is not a receiver of current thread")
    end
  end
  defp systeme_check_event_drivers(e, pid) do
    systeme_check_event_driver(e)
    opid = systeme_get_event_driver(e)
    if opid != pid do
      throw("Attempt to set multi-drivers for #{inspect(e)}: #{inspect(opid)} and #{inspect(pid)}")
    end
  end

  defp systeme_master_node() do
    Process.get(:systeme_master_node)
  end

  def __systeme_thread_setup__(es, name, max_time) do
    receive do
      {:node, n} -> Process.put(:systeme_master_node, n)
    end
    oes = Keyword.get(es, :output, [])
    oes = if is_list(oes), do: oes, else: [oes] |> Enum.uniq
    Enum.each(oes, fn(e)->
      systeme_set_event_driver(e, self)
    end)
    ies = Keyword.get(es, :input, [])
    ies = if is_list(ies), do: ies, else: [ies]
    nes = Keyword.get(es, :on, [])
    nes = if is_list(nes), do: nes, else: [nes]
    ies = oes ++ ies ++ nes |> Enum.uniq
    Enum.each(ies, fn(e)->
      systeme_set_event_receiver(e, self)
    end)
    Process.put(:systeme_thread_outputs, oes)
    Process.put(:systeme_thread_inputs, ies)
    Process.put(:systeme_signals, HashDict.new)
    Process.put(:systeme_thread_name, name)
    Process.put(:systeme_thread_max_time, max_time)
    receive do
      {:pids, pids} -> Process.put(:systeme_pids, pids)
    end
    Systeme.Core.set_current_time(0)
    send({:systeme_master, systeme_master_node()}, :ready)
    receive do
      :go ->
    end
  end

  def __systeme_thread_cleanup__() do
    Process.get(:systeme_thread_outputs) |> Enum.each(fn(e)->
      systeme_get_event_receivers(e) |> Enum.each(fn(pid) ->
        send(pid, {e, Process.get(:systeme_thread_max_time), nil, false})
      end)
    end)
    send({:systeme_master, systeme_master_node()}, :finished)
    receive do
      :finished_ok ->
    end
    exit(:normal)
  end

  defmacro initial(es \\ [], do: body) do
    es = Macro.escape(es)
    body = Macro.escape(body)
    quote bind_quoted: binding do
      id = length(Module.get_attribute(__MODULE__, :systeme_threads))
      n = :"systeme_thread__initial_#{id}"
      def unquote(n)(name, max_time, node) do
        Node.spawn_link(node, fn ->
          Systeme.Core.__systeme_thread_setup__(unquote(es), name, max_time)
          unquote(body)
          Systeme.Core.__systeme_thread_cleanup__()
        end)
      end
    end 
  end

  defmacro always(es \\ [], do: body) do
    body = Macro.escape(body)
    es = Macro.escape(es)
    quote bind_quoted: binding do
      id = length(Module.get_attribute(__MODULE__, :systeme_threads))
      n = :"systeme_thread__always_#{id}"
      def unquote(n)(name, max_time, node) do
        nes = Keyword.get(unquote(es), :on, [])
        f = fn(_f) ->
          Systeme.Core.wait(nes)
          unquote(body)
          if Systeme.Core.current_time() < max_time do
            _f.(_f)
          end
        end
        Node.spawn_link(node, fn ->
          Systeme.Core.__systeme_thread_setup__(unquote(es), name, max_time)
          f.(f)
          Systeme.Core.__systeme_thread_cleanup__()
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

  def name() do
    Process.get(:systeme_thread_name)
  end

  def wait(es) when is_list(es) do
    #Enum.each(es, fn(e) ->
    #  :gproc.reg({:p, :l, e})
    #end)
    te = Enum.find(es, fn(e)->
      case e do
        {:time, _} -> true
        _ -> false
      end
    end)
    if te do
      if length(es) > 1 do
        throw("Attempt to mix simulte time with other events")
      end
      {_, t} = te
      set_current_time(current_time() + t)
    else
      Enum.each(es, fn(e)->
        systeme_check_event_driver(e)
        systeme_check_event_receiver(e)
        Process.get(:systeme_thread_outputs) |> Enum.each(fn(e)->
          systeme_get_event_receivers(e) |> Enum.each(fn(pid) ->
            send(pid, {e, current_time(), nil, false})
          end)
        end)
      end)
      es = Enum.reduce(es, HashDict.new, fn(e, acc)->
        Dict.put(acc, e, {current_time(), false})
      end)
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

  defp get_recent_event(es) do
    e = {_, r, t} = Enum.reduce(Dict.keys(es), {nil, nil, nil}, fn(e, acc)->
      {t, ee} = Dict.get(es, e)
      {_, _, at} = acc
      if !at || t <= at do
        {e, ee, t}
      else
        acc
      end
    end)
    if !r && t >= Process.get(:systeme_thread_max_time) do
      Systeme.Core.__systeme_thread_cleanup__()
    end
    e
  end

  defp wait_loop(es, ct, mq \\ []) do
    receive do
      m = {e, t, _, rm} ->
        mq = [m|mq]
        if Dict.has_key?(es, e) do
          if t >= ct do
            {et, ee} = Dict.get(es, e)
            es = if ee do
              if rm && et > t do
                Dict.put(es, e, {t, true})
              else
                es
              end
            else
              if rm do
                Dict.put(es, e, {t, true})
              else
                if et <= t do
                  Dict.put(es, e, {t, false})
                else
                  es
                end
              end
            end
            {_, r, t} = get_recent_event(es)
            if r do
              set_current_time(t)
              Enum.each(Enum.reverse(mq), fn(m)->
                send(self, m)
              end)
            else
              wait_loop(es, ct, mq)
            end
          else
            wait_loop(es, ct, mq)
          end
        else
          wait_loop(es, ct, mq)
        end
    end
  end

  defp wait_flush(ct) do
    receive do
      {e, t, v, rm} when t <= ct ->
        if rm do
          case e do
            {:signal, s} ->
              vt = Process.get(:systeme_signals) |> Dict.get(s)
              if vt do
                {_, ot} = vt
                if ot <= t do
                  Process.put(:systeme_signals, (Process.get(:systeme_signals) |> Dict.put(s, {v, t})))
                end
              else
                Process.put(:systeme_signals, (Process.get(:systeme_signals) |> Dict.put(s, {v, t})))
              end
            _ ->
          end
        end
        wait_flush(ct)
    after 0 ->
    end
  end

  def notify(e, v \\ nil) do
    systeme_check_event_drivers(e, self)
    pids = systeme_get_event_receivers(e)
    #send(:systeme_simulate_thread, {:active, pids}) #:gproc.lookup_pids({:p, :l, e})})
    Enum.each(pids, fn(pid)->
      send(pid, {e, current_time(), v, true})
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
      {:time, unquote(n)}
    end
  end

  def read_signal(s, dv \\ nil) do
    systeme_check_event_receiver(signal(s))
    systeme_check_event_driver(signal(s))
    v = (Process.get(:systeme_signals) |> Dict.get(s))
    if v do
      {v, _} = v
      v
    else
      if dv do
        dv
      else
        wait(signal(s))
        {v, _} = Process.get(:systeme_signals) |> Dict.get(s)
        v
      end
    end
  end

  def write_signal(s, v) do
    notify(signal(s), v)
  end

  def info(msg) do
    IO.puts "[SE #{current_time()} I]: #{msg}"
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

  defp find_node() do
    nodes = [Node.self() | Node.list()] |> Enum.uniq
    l = length(nodes)
    ind = :erlang.trunc(:random.uniform() * l)
    ind = if ind == l, do: ind - 1, else: ind
    Enum.at(nodes, ind)
  end

  def run_initial(max_time) do
    __all_systeme_threads__("initial") |> Enum.map(fn({mod, name}) ->
      apply(mod, name, [name, max_time, find_node()])
    end)
  end
  
  def run_always(max_time) do
    __all_systeme_threads__("always") |> Enum.map(fn({mod, name}) ->
      apply(mod, name, [name, max_time, find_node()])
    end)
  end

  defp threads_ready(size) when size > 0 do
    receive do
      :ready -> threads_ready(size - 1)
    end
  end
  defp threads_ready(0) do
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
    Process.register(self, :systeme_master)
    Systeme.Event.start()
    #:application.start(:gproc)
    initials = run_initial(max_time)
    always   = run_always(max_time)
    pids = initials ++ always
    Enum.each(pids, fn(pid) ->
      send(pid, {:node, Node.self()})
      send(pid, {:pids, pids})
    end)
    threads_ready(length(pids))
    Enum.each(pids, fn(pid) ->
      send(pid, :go)
    end)
    threads_terminated(length(pids))
    Enum.each(pids, fn(pid) ->
      send(pid, :finished_ok)
    end)
    IO.puts "Simulation finished"
  end

  def finish() do
    Process.get(:systeme_pids) |> Enum.each(fn(pid)->
      send(pid, {:finish, current_time()})
    end)
  end

  def start_link() do
    pid = spawn_link(__MODULE__, :run, [100])
    {:ok, pid}
  end

end
