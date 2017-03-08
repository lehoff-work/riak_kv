%%% This module is to be used as a fallback module when doing mocking with EQC.
%%% It allows us to leave the calls to app_helper out of the callout specifications
%%% as they add nothing to the problem we need to validate.

-module(app_helper_mock).

-export([get_env/2,
         get_env/3]).

%% To induce a bug when we were not passing a default, leave this
%% 2-arity version of get_env for `fsm_trace_enabled' here. The
%% test would fail without the 3-arity version below.
get_env(riak_kv, fsm_trace_enabled) ->
    undefined;
get_env(riak_core, default_bucket_props) ->
    [{chash_keyfun, {riak_core_util, chash_std_keyfun}},
     {pw, 0},
     {w, quorum},
     {dw, quorum}].

get_env(riak_kv, fsm_trace_enabled, Default) ->
    Default;
get_env(riak_kv, put_coordinator_failure_timeout, 3000) ->
    3000;
get_env(riak_kv, retry_put_coordinator_failure, true) ->
    true.
