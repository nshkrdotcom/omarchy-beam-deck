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
    process_flag(message_queue_data, off_heap),
    Ref = erlang:monitor(process, Parent),
    try
        Session = trace:session_create(nshkr_beam_deck, self(), []),
        ok = enable(Session, Options),
        Caller ! {self(), ready},
        Parent ! {beam_deck_probe, node(), started, self()},
        loop(Parent, Ref, Session, {erlang:monotonic_time(millisecond), 0, 0})
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


loop(Parent, Ref, Session, {Window, Count, Dropped}) ->
    receive
        {monitor, Who, Kind, Info} ->
            Now = erlang:monotonic_time(millisecond),
            {Start, Used, Lost} = case Now - Window >= 1000 of
                true ->
                    case Dropped > 0 of
                        true -> Parent ! {beam_deck_event, node(), events_dropped, <<"probe">>, Dropped, erlang:system_time(millisecond)};
                        false -> ok
                    end,
                    {Now, 0, 0};
                false -> {Window, Count, Dropped}
            end,
            {NextUsed, NextLost} = case Used < 100 of
                true ->
                    Parent ! {beam_deck_event, node(), Kind, printable(Who, 0), printable(Info, 0), erlang:system_time(millisecond)},
                    {Used + 1, Lost};
                false -> {Used, Lost + 1}
            end,
            case process_info(self(), message_queue_len) of
                {message_queue_len, Size} when Size > 10000 ->
                    trace:session_destroy(Session),
                    Parent ! {beam_deck_event, node(), probe_overloaded, <<"probe">>, Size, erlang:system_time(millisecond)},
                    ok;
                _ -> loop(Parent, Ref, Session, {Start, NextUsed, NextLost})
            end;
        stop -> trace:session_destroy(Session), ok;
        {'DOWN', Ref, process, Parent, _} -> trace:session_destroy(Session), ok;
        _Other -> loop(Parent, Ref, Session, {Window, Count, Dropped})
    end.

printable(_V, Depth) when Depth > 8 -> <<"truncated">>;
printable(P, _Depth) when is_pid(P); is_port(P); is_reference(P) -> list_to_binary(io_lib:format("~p", [P]));
printable(V, Depth) when is_tuple(V) -> [printable(X, Depth + 1) || X <- lists:sublist(tuple_to_list(V), 32)];
printable(V, Depth) when is_list(V) -> [printable(X, Depth + 1) || X <- lists:sublist(V, 32)];
printable(V, Depth) when is_map(V) -> maps:from_list([{K, printable(X, Depth + 1)} || {K, X} <- lists:sublist(maps:to_list(V), 32)]);
printable(V, _Depth) when is_binary(V), byte_size(V) > 512 -> binary:part(V, 0, 512);
printable(V, _Depth) -> V.
