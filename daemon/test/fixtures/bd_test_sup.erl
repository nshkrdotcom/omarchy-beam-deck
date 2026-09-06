-module(bd_test_sup).
-behaviour(supervisor).
-export([start/0, init/1]).
start() ->
    {ok, Pid} = supervisor:start_link({local, ?MODULE}, ?MODULE, []),
    unlink(Pid),
    {ok, Pid}.
init([]) ->
    Child = #{id => bd_test_worker, start => {bd_test_worker, start_link, []},
              restart => permanent, shutdown => 1000, type => worker, modules => [bd_test_worker]},
    {ok, {{one_for_one, 5, 10}, [Child]}}.
