-module(riak_kv_put_fsm_comm).

%% API
-export([start_state/0]).


start_state() ->
    gen_fsm:send_event(self(), start).