-module(nshkr_beam_deck_probe).
-export([start/2, stop/1]).

start(Parent, Options) when is_pid(Parent), is_map(Options) ->
    Caller = self(),
    Pid = spawn(fun() -> init(Parent, Options, Caller) end),
    receive
        {Pid, ready} -> {ok, Pid};
        {Pid, error, Reason} -> {error, Reason}
    after 5000 ->
        exit(Pid, kill),
        {error, timeout}
    end.

stop(Pid) when is_pid(Pid) ->
    Ref = erlang:monitor(process, Pid),
    Pid ! stop,
    receive
        {'DOWN', Ref, process, Pid, _Reason} -> ok
    after 2000 ->
        erlang:demonitor(Ref, [flush]),
        {error, timeout}
    end.

init(Parent, Options, Caller) ->
    process_flag(trap_exit, true),
    Ref = erlang:monitor(process, Parent),
    try
        Session = trace:session_create(nshkr_beam_deck, self(), []),
        ok = enable(Session, Options),
        Caller ! {self(), ready},
        Parent ! {beam_deck_probe, node(), started, self()},
        loop(Parent, Ref, Session)
    catch
        C:R ->
            Caller ! {self(), error, {C,R}},
            Parent ! {beam_deck_probe, node(), error, {C,R}}
    end.

enable(Session, O) ->
    trace:system(Session, long_gc, maps:get(long_gc_ms, O, 100)),
    trace:system(Session, long_schedule, maps:get(long_schedule_ms, O, 100)),
    trace:system(Session, long_message_queue,
                 {maps:get(mailbox_disable, O, 1000), maps:get(mailbox_enable, O, 5000)}),
    trace:system(Session, large_heap, maps:get(large_heap_words, O, 8000000)),
    trace:system(Session, busy_port, true),
    trace:system(Session, busy_dist_port, true),
    ok.

loop(Parent, Ref, Session) ->
    receive
        {monitor, Who, Kind, Info} ->
            Parent ! {beam_deck_event, node(), Kind, printable(Who), printable(Info), erlang:system_time(millisecond)},
            loop(Parent, Ref, Session);
        stop -> trace:session_destroy(Session), ok;
        {'DOWN', Ref, process, Parent, _} -> trace:session_destroy(Session), ok;
        _Other -> loop(Parent, Ref, Session)
    end.

printable(P) when is_pid(P); is_port(P); is_reference(P) -> list_to_binary(io_lib:format("~p", [P]));
printable(V) when is_tuple(V) -> list_to_tuple([printable(X) || X <- tuple_to_list(V)]);
printable(V) when is_list(V) -> [printable(X) || X <- V];
printable(V) when is_map(V) -> maps:map(fun(_K, X) -> printable(X) end, V);
printable(V) -> V.
