-module(riak_kv_put_fsm_comm).

%% API
-export([start_state/1,
         schedule_request_timeout/1]).


start_state(StateName) ->
    gen_fsm:send_event(self(), {start, StateName}).

schedule_request_timeout(infinity) ->
    undefined;
schedule_request_timeout(Timeout) ->
    erlang:send_after(Timeout, self(), request_timeout).