-module(put_redirect_eqc).

-compile(export_all).

-include_lib("eqc/include/eqc.hrl").
-include_lib("eqc/include/eqc_component.hrl").

-record(state, 
        { fsm_pid = not_started,
          next_state = not_started
        }).


-define(BUCKET_TYPE, <<"my_bucket_type">>).
-define(BUCKET, <<"my_bucket">>).
-define(KEY, <<"da_key">>).
-define(VALUE, 42).


-define(APP_HELPER_CALLOUT(Args), 
        ?CALLOUT(app_helper, get_env, Args,
                 erlang:apply(?MODULE, app_get_env, Args))).

-define(KV_STAT_CALLOUT,
        ?CALLOUT(riak_kv_stat, update, [?WILDCARD], ok)).

prop_redirect() ->
    ?SETUP( fun setup/0,
            ?FORALL(Cmds, 
                    commands(?MODULE),
                    begin
                        start(),
                        {H, S, Res} = run_commands(?MODULE,Cmds),
                        stop(S),
                        io:format("mock trace: ~p~n", [eqc_mocking:get_trace(api_spec())]),
                        pretty_commands(?MODULE, Cmds, {H, S, Res},
                                        aggregate(command_names(Cmds),
                                                  Res == ok))
                    end)).

setup() ->
    eqc_mocking:start_mocking(api_spec()),
    fun teardown/0.

teardown() ->
    eqc_mocking:stop_mocking().



start() ->
    ok.

stop(S) ->
    catch exit(S#state.fsm_pid, kill).


initial_state() ->
    #state{}.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%% Mocking

api_spec() ->
    #api_spec{
       language = erlang,
       modules  = [
                   #api_module{
                      name = app_helper,
                      functions = [ #api_fun{ name = get_env, arity = 2},
                                    #api_fun{ name = get_env, arity = 3} ]},
                   #api_module{
                      name = riak_kv_stat,
                      functions = [ #api_fun{ name = update, arity = 1} ]},
                   #api_module{
                      name = riak_core_bucket,
                      functions = [ #api_fun{ name = get_bucket, arity = 1} ]},
                   #api_module{
                      name = riak_kv_put_fsm_comm,
                      functions = [ #api_fun{ name = start_state, arity = 0} ]},
                   #api_module{
                      name = riak_core_node_watcher, 
                      functions = [ #api_fun{ name = nodes, arity=1}
                                                % returns : 
                                                % -type preflist_ann() :: [{{index(),
                                                % node()}, primary|fallback}].
                                  ]},
                   #api_module{
                      name = riak_core_apl,
                      functions = [ #api_fun{ name = get_apl_ann, arity=3},
                                    #api_fun{ name = get_primary_apl, arity=3}
                                  ]}
                  ]}.
                                              


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%% Commands

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
start_put(From, Object, PutOptions) ->
    {ok, Pid} = riak_kv_put_fsm:start_link(From, Object, PutOptions),
    unlink(Pid),
    Pid.


start_put_args(_S) ->
    [from(), new_object(), put_options()].

start_put_pre(S) ->
    S#state.fsm_pid == not_started.


%% @todo: mock riak_kv_get_put_monitor and avoid the parallelism with the
%% KV_STAT_CALLOUT that it causes.
start_put_callouts(_S, _Args) ->
    ?SEQ([?APP_HELPER_CALLOUT([riak_kv, put_coordinator_failure_timeout, 3000])
         ,?APP_HELPER_CALLOUT([riak_kv, fsm_trace_enabled])
         ,?PAR([?KV_STAT_CALLOUT
               ,?CALLOUT(riak_kv_put_fsm_comm, start_state, [], ok)])]).   

start_put_post(_S, _Args, Pid) ->
    is_pid(Pid) andalso erlang:is_process_alive(Pid).

start_put_next(S, Pid, _Args) ->
    S#state{fsm_pid = Pid,
            next_state = prepare}.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
start_prepare(Pid) ->
    gen_fsm:send_event(Pid, start).

%% Do this in a worker process so that the previous step has collected all callouts
%% before we begin.
%% In a newer EQC/OTP combo it would be safe to use 
%%  with_parameter(default_process, worker, commands(?MODULE))
%% in the ?FORALL.
start_prepare_process(_,_) ->
    worker.

start_prepare_args(S) ->
    [S#state.fsm_pid].

start_prepare_pre(S) ->
    S#state.next_state==prepare.

start_prepare_callouts(_S, _Args) ->
    ?SEQ([
          ?APP_HELPER_CALLOUT([riak_core, default_bucket_props])
         ,?CALLOUT(riak_core_bucket, get_bucket, [?WILDCARD], 
                   app_get_env(riak_core, default_bucket_props))
      ]).
        

start_prepare_next(S, _, _Args) ->
    S#state{next_state = waiting_local_vnode}.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%% Generators

from() ->
    {raw, 1, self()}.

new_object() ->
    riak_object:new({?BUCKET_TYPE, ?BUCKET}, ?KEY, ?VALUE).

put_options() ->
    [{n_val, 3}, 
     {w, quorum}, 
     {chash_keyfun, {riak_core_util, chash_std_keyfun}}].


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%% Mocking functions

app_get_env(riak_kv, fsm_trace_enabled) ->
    false;
app_get_env(riak_core, default_bucket_props) ->
    [{chash_keyfun, {riak_core_util, chash_std_keyfun}},
     {pw, 0},
     {w, quorum},
     {dw, quorum}].


app_get_env(riak_kv, put_coordinator_failure_timeout, 3000) ->
    3000.


