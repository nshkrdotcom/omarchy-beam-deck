-module(bd_test_worker).
-behaviour(gen_server).
-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3,
         walltime_owner/0, make_tables/1]).

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
init([]) ->
    put(private_fixture_data, <<"BD_FIXTURE_DICTIONARY_MUST_NOT_LEAVE_TARGET">>),
    Table = ets:new(bd_test_table, [named_table, protected, set]),
    ets:insert(Table, {private_fixture_key, <<"BD_FIXTURE_ETS_MUST_NOT_LEAVE_TARGET">>}),
    Binary = binary:copy(<<"BD_FIXTURE_BINARY_MUST_NOT_LEAVE_TARGET">>, 32768),
    {ok, {Binary, Table}}.
handle_call(ping, _From, State) -> {reply, pong, State};
handle_call({make_tables, Count}, _From, State) ->
    Tables = [ets:new(bd_extra, [set, private]) || _ <- lists:seq(1, Count)],
    {reply, length(Tables), State};
handle_call(_Request, _From, State) -> {reply, unsupported, State}.
handle_cast(pause, State) -> receive resume -> {noreply, State} end;
handle_cast(_Request, State) -> {noreply, State}.
handle_info(_Message, State) -> {noreply, State}.
terminate(_Reason, _State) -> ok.
code_change(_Old, State, _Extra) -> {ok, State}.
make_tables(Count) -> gen_server:call(?MODULE, {make_tables, Count}).
walltime_owner() ->
    Caller = self(),
    Pid = spawn(fun() ->
        erlang:system_flag(scheduler_wall_time, true),
        Caller ! {self(), ready},
        receive stop -> ok end
    end),
    receive {Pid, ready} -> Pid after 1000 -> exit(Pid, kill), timeout end.
