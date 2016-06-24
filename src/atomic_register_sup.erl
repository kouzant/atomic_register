%%%-------------------------------------------------------------------
%% @doc atomic_register top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(atomic_register_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API functions
%%====================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

%% Child :: {Id,StartFunc,Restart,Shutdown,Type,Modules}
init([]) ->
    Beb = {beb, {beb, start_link, []},
	  transient,
	  2000,
	  worker,
	  [beb]},
    Ar = {ar, {atomic_register, start_link, []},
	 transient,
	 2000,
	 worker,
	 [atomic_register]},
    {ok, { {rest_for_one, 5, 1}, [Beb, Ar]} }.

%%====================================================================
%% Internal functions
%%====================================================================
