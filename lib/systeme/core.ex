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

  def __systeme_thread_setup__(es, name, max_time, interval) do
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
    Process.put(:systeme_thread_messages, [])
    Process.put(:systeme_thread_outputs, oes)
    Process.put(:systeme_thread_inputs, ies)
    Process.put(:systeme_thread_waits, nes)
    Process.put(:systeme_thread_signals, HashDict.new)
    Process.put(:systeme_thread_name, name)
    Process.put(:systeme_thread_max_time, max_time)
    Process.put(:systeme_thread_barrier, interval)
    Process.put(:systeme_thread_barrier_interval, interval)
    Process.put(:systeme_thread_triggered, -1)
    receive do
      {:pids, pids} -> Process.put(:systeme_pids, pids)
    end
    send({:systeme_master, systeme_master_node()}, :ready)
    receive do
      :go ->
    end
    Systeme.Core.set_current_time(0)
  end

  defp get_messages() do
    Process.get(:systeme_thread_messages)
  end

  defp set_messages(ms) do
    Process.put(:systeme_thread_messages, ms)
  end

  #defp push_message(m) do
  #  set_messages(get_messages()++[m])
  #end

  defp unshift_messages(ms) do
    set_messages(ms++get_messages())
  end

  defp unshift_message(m) do
    set_messages([m|get_messages()])
  end

  defp get_message() do
    ms = get_messages()
    if length(ms) > 0 do
      [m|ms] = get_messages()
      set_messages(ms)
      m
    else
      receive do
        m -> m
      end
    end
  end

  def __systeme_thread_cleanup__() do
    send_null_message(Process.get(:systeme_thread_max_time))
    send({:system_barrier, systeme_master_node()}, {:finished, self})
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
      def unquote(n)(name, max_time, interval, node) do
        Node.spawn_link(node, fn ->
          Systeme.Core.__systeme_thread_setup__(unquote(es), name, max_time, interval)
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
      def unquote(n)(name, max_time, interval, node) do
        nes = Keyword.get(unquote(es), :on, [])
        f = fn(_f) ->
          Systeme.Core.wait(nes)
          unquote(body)
          Systeme.Core.wait_barrier()
          if Systeme.Core.current_time() < max_time do
            _f.(_f)
          end
        end
        Node.spawn_link(node, fn ->
          Systeme.Core.__systeme_thread_setup__(unquote(es), name, max_time, interval)
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
    send_null_message(t)
  end

  def name() do
    Process.get(:systeme_thread_name)
  end

  defp send_null_message(t) do
    Process.get(:systeme_thread_outputs) |> Enum.each(fn(e)->
      systeme_get_event_receivers(e) |> Enum.each(fn(pid) ->
       send(pid, {e, t, nil, false})
      end)
    end)
  end

  def wait_barrier() do
    barrier = Process.get(:systeme_thread_barrier)
    if current_time() >= barrier do
      send_null_message(current_time())
      send({:system_barrier, systeme_master_node()}, :reach_barrier)
      receive do
        :barrier ->
      end
      Process.put(:systeme_thread_barrier, barrier + Process.get(:systeme_thread_barrier_interval))
    end
  end

  def wait(es) when is_list(es) do
    #Enum.each(es, fn(e) ->
    #  :gproc.reg({:p, :l, e})
    #end)
    #wait_flush(current_time())
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
      end)
      send_null_message(current_time())
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
    e = {_, t, r} = Enum.reduce(Dict.keys(es), {nil, nil, nil}, fn(e, acc)->
      {t, rm} = Dict.get(es, e)
      {_, at, r} = acc
      if !at || t < at do
        {e, t, rm}
      else
        if t == at && !r do
          {e, t, rm}
        else
          acc
        end
      end
    end)
    if !r && t >= Process.get(:systeme_thread_max_time) do
      Systeme.Core.__systeme_thread_cleanup__()
    end
    e
  end

  defp wait_loop(es, ct, mq \\ []) do
    m = get_message()
    case m do
      {e, t, _, rm} ->
        mq = [m|mq]
        if Dict.has_key?(es, e) do
          if t >= ct do
            last_triggered_time = Process.get(:systeme_thread_triggered)
            {et, erm} = Dict.get(es, e)
            es = if erm do
              if rm && et > t do
                Dict.put(es, e, {t, true})
              else
                es
              end
            else
              if rm do
                if t > ct || last_triggered_time != current_time() do
                  Dict.put(es, e, {t, true})
                else
                  es
                end
              else
                if et <= t do
                  Dict.put(es, e, {t, false})
                else
                  es
                end
              end
            end
            {_, ct, r} = get_recent_event(es)
            if ct > current_time() do
              set_current_time(ct)
            end
            if r && last_triggered_time < current_time() do
              Process.put(:systeme_thread_triggered, current_time())
              unshift_messages(Enum.reverse(mq))
            else
              wait_loop(es, ct, mq)
            end
          else
            wait_loop(es, ct, mq)
          end
        else
          wait_loop(es, ct, mq)
        end
      _ -> wait_loop(es, ct, mq)
    end
  end

  defp wait_flush(ct) do
    get_messages() |>
    Enum.reduce([], fn(m, acc)->
      {e, t, v, rm} = m
      case e do
        {:signal, s} ->
          vt = get_signal(s)
          if vt do
            {ov, ot, r} = vt
            if ot <= t do
              v = if rm && t <= ct, do: v, else: ov
              set_signal(s, v, t, r)
            end
          else
            if rm && t <= ct, do: set_signal(s, v, t, rm)
          end
        _ ->
      end
      if t <= ct do
        acc
      else
        [m|acc]
      end
    end) |> Enum.reverse() |>
    set_messages()
    receive do
      {e, t, v, rm} when t <= ct ->
        case e do
          {:signal, s} ->
            vt = get_signal(s)
            if vt do
              {ov, ot, r} = vt
              if ot <= t do
                v = if rm, do: v, else: ov
                r = if rm, do: rm, else: r
                set_signal(s, v, t, r)
              end
            else
              if rm, do: set_signal(s, v, t, rm)
            end
          _ ->
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

  defp get_signal(s) do
    Process.get(:systeme_thread_signals) |> Dict.get(s)
  end

  defp set_signal(s, v, t, r) do
    Process.put(:systeme_thread_signals, Process.get(:systeme_thread_signals) |> Dict.put(s, {v, t, r}))
  end

  defp wait_signal(s) do
    ct = current_time()
    #send_null_message(ct)
    wait_flush(ct)
    vt = get_signal(s)
    if vt do
      {ov, ot, r} = vt
      if ot < ct || (ot == ct && Enum.find(Process.get(:systeme_thread_waits), fn(e)-> e == signal(s) end)) do
        receive do
          m = {{:signal, ^s}, t, v, rm} ->
            v = if rm && t <= ct, do: v, else: ov
            set_signal(s, v, t, r)
            if t > ct do
              unshift_message(m)
            end
            wait_signal(s)
        end
      end
    else
      receive do
        m = {{:signal, ^s}, t, v, rm} ->
          if t <= ct do
            if rm, do: set_signal(s, v, t, rm)
          else
            unshift_message(m)
          end
          wait_signal(s)
      end
    end
  end

  def read_signal(s, dv \\ nil) do
    systeme_check_event_receiver(signal(s))
    systeme_check_event_driver(signal(s))
    v = get_signal(s)
    if !v && dv do
      set_signal(s, dv, current_time(), true)
    end
    wait_signal(s)
    {v, _, _} = get_signal(s)
    v
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

  def run_initial(max_time, interval) do
    __all_systeme_threads__("initial") |> Enum.map(fn({mod, name}) ->
      apply(mod, name, [name, max_time, interval, find_node()])
    end)
  end
  
  def run_always(max_time, interval) do
    __all_systeme_threads__("always") |> Enum.map(fn({mod, name}) ->
      apply(mod, name, [name, max_time, interval, find_node()])
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

  defp start_barrier(pids) do
    spawn_link(__MODULE__, :run_barrier, [pids, length(pids)]) |> Process.register(:system_barrier)
  end

  def run_barrier(pids, size) when size > 0 do
    receive do
      {:finished, pid} ->
        pids = List.delete(pids, pid)
        run_barrier(pids, size - 1)
      :reach_barrier -> run_barrier(pids, size - 1)
    end
  end
  def run_barrier(pids, 0) do
    Enum.each(pids, fn(pid)->
      send(pid, :barrier)
    end)
    run_barrier(pids, length(pids))
  end

  def run(max_time, opts \\ []) do
    interval = Keyword.get(opts, :sync_interval) || 100
    IO.puts "Systeme simulator start"
    Process.register(self, :systeme_master)
    Systeme.Event.start()
    #:application.start(:gproc)
    initials = run_initial(max_time, interval)
    always   = run_always(max_time, interval)
    pids = initials ++ always
    start_barrier(pids)
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
