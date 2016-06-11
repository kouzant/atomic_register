%%%-------------------------------------------------------------------
%% @doc atomic_register public API
%% @end
%%%-------------------------------------------------------------------

-module(atomic_register_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%%====================================================================
%% API
%%====================================================================

start(_StartType, _StartArgs) ->
    atomic_register_sup:start_link().

%%--------------------------------------------------------------------
stop(_State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================